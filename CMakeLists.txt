cmake_minimum_required(VERSION 3.20)

project(florv VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)


add_library(florv_warnings INTERFACE)
target_compile_options(florv_warnings INTERFACE -Wall -Wextra -Wpedantic -Werror)

# ---------------------------------------------------------------------------
# florv_core: everything in core/, shared by the PC and the Cortex-A9.
# CONFIGURE_DEPENDS re-runs the glob on every build, so a new .cpp is picked up
# without re-running cmake by hand.
# ---------------------------------------------------------------------------
file(GLOB FLORV_CORE_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/core/*.cpp")

add_library(florv_core STATIC ${FLORV_CORE_SOURCES})
target_include_directories(florv_core PUBLIC "${CMAKE_SOURCE_DIR}/core")
target_link_libraries(florv_core PRIVATE florv_warnings)

# ---------------------------------------------------------------------------
# florv: the PC-only command line tool.
# ---------------------------------------------------------------------------
add_executable(florv host/main.cpp)
target_link_libraries(florv PRIVATE florv_core florv_warnings)

# ---------------------------------------------------------------------------
# Unit tests: one executable, doctest as a single header in third_party/.
# SYSTEM stops -Werror from firing on warnings inside doctest.h itself.
# ---------------------------------------------------------------------------
add_library(doctest INTERFACE)
target_include_directories(doctest SYSTEM INTERFACE "${CMAKE_SOURCE_DIR}/third_party/doctest")

file(GLOB FLORV_TEST_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/tests/unit/*.cpp")

add_executable(florv_tests ${FLORV_TEST_SOURCES})
target_link_libraries(florv_tests PRIVATE florv_core doctest florv_warnings)
# Where the tests find committed data files such as tests/data/minimal.elf.
target_compile_definitions(florv_tests PRIVATE
    FLORV_TEST_DATA_DIR="${CMAKE_SOURCE_DIR}/tests/data")

# ---------------------------------------------------------------------------
# CTest: one registered test that runs the whole doctest executable.
# ---------------------------------------------------------------------------
enable_testing()
add_test(NAME unit COMMAND florv_tests)

# ---------------------------------------------------------------------------
# CLI tests: run the real florv and check its exit code (see host/main.cpp for
# the codes). tests/cli/run_florv.cmake does the checking; arguments are
# separated by | in ARGS.
#   florv_cli_test(<name> <expected exit code> <ARGS> [text florv must print])
# ---------------------------------------------------------------------------
set(FLORV_DATA "${CMAKE_SOURCE_DIR}/tests/data")

function(florv_cli_test name expected_exit arguments)
    set(extra "")
    if(ARGC GREATER 3)
        set(extra "-DEXPECT_STDOUT=${ARGV3}")
    endif()
    add_test(NAME cli.${name}
             COMMAND ${CMAKE_COMMAND}
                     "-DFLORV=$<TARGET_FILE:florv>"
                     "-DARGS=${arguments}"
                     "-DEXPECT_EXIT=${expected_exit}"
                     ${extra}
                     -P "${CMAKE_SOURCE_DIR}/tests/cli/run_florv.cmake")
endfunction()

# 0: halted with tohost 1.
florv_cli_test(pass          0 "iss|${FLORV_DATA}/minimal.elf" "tohost:  1")
# 1: halted with another tohost value.
florv_cli_test(fail_tohost   1 "iss|${FLORV_DATA}/fail.elf" "tohost:  2")
# 2: the step limit, and a trap.
florv_cli_test(step_limit    2 "iss|${FLORV_DATA}/minimal.elf|--max-steps|3" "status:  step limit")
florv_cli_test(trap          2 "iss|${FLORV_DATA}/trap.elf" "status:  trap")
florv_cli_test(trap_location 2 "iss|${FLORV_DATA}/trap.elf" "trap at: pc=80000004 insn=ffffffff")
# 3: a file that is not there, and a file that is not an ELF.
florv_cli_test(missing_file  3 "iss|${FLORV_DATA}/no_such_file.elf")
florv_cli_test(not_an_elf    3 "iss|${FLORV_DATA}/minimal.S")
# 4: wrong command lines.
florv_cli_test(no_arguments  4 "")
florv_cli_test(no_elf_given  4 "iss")
florv_cli_test(bad_max_steps 4 "iss|${FLORV_DATA}/minimal.elf|--max-steps|many")

# elf2hex: 0 the file is written, 3 a bad ELF, 4 a wrong command line or an
# output file that cannot be written (here: in a folder that does not exist).
florv_cli_test(elf2hex            0 "elf2hex|${FLORV_DATA}/minimal.elf|${CMAKE_BINARY_DIR}/minimal.hex" "wrote 16384 words")
florv_cli_test(elf2hex_missing    3 "elf2hex|${FLORV_DATA}/no_such_file.elf|${CMAKE_BINARY_DIR}/none.hex")
florv_cli_test(elf2hex_not_an_elf 3 "elf2hex|${FLORV_DATA}/minimal.S|${CMAKE_BINARY_DIR}/none.hex")
florv_cli_test(elf2hex_no_output  4 "elf2hex|${FLORV_DATA}/minimal.elf")
florv_cli_test(elf2hex_bad_output 4 "elf2hex|${FLORV_DATA}/minimal.elf|${CMAKE_BINARY_DIR}/no_such_folder/out.hex")

# ---------------------------------------------------------------------------
# arm-check: compile every core/*.cpp for the Cortex-A9, compile only, no link.
# Proves core/ stays buildable for the bare-metal ARM: -fno-exceptions makes any
# throw or try an error, -fno-rtti does the same for dynamic_cast and typeid.
# Run with:  cmake --build build --target arm-check
# Another machine can point at its own compiler with -DFLORV_ARM_CXX=<path>.
# ---------------------------------------------------------------------------
set(FLORV_ARM_CXX
    "C:/AMDDesignTools/2025.2/Vitis/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-g++.exe"
    CACHE FILEPATH "arm-none-eabi-g++ shipped with Vitis, used by the arm-check target")

# -mfpu and -mfloat-abi are the ones Vitis passes for the real application. They are
# required here: this toolchain ships its C++ headers for hard-float variants only,
# so -mcpu=cortex-a9 alone fails with "bits/c++config.h: No such file or directory".
set(FLORV_ARM_FLAGS -c -std=c++17 -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard
                    -fno-exceptions -fno-rtti -Os)

if(EXISTS "${FLORV_ARM_CXX}")
    set(FLORV_ARM_OUT "${CMAKE_BINARY_DIR}/arm-check")
    set(arm_check_commands COMMAND ${CMAKE_COMMAND} -E make_directory "${FLORV_ARM_OUT}")
    foreach(source ${FLORV_CORE_SOURCES})
        get_filename_component(name "${source}" NAME_WE)
        list(APPEND arm_check_commands
             COMMAND "${FLORV_ARM_CXX}" ${FLORV_ARM_FLAGS} "-I${CMAKE_SOURCE_DIR}/core"
                     "${source}" -o "${FLORV_ARM_OUT}/${name}.o")
    endforeach()
    # A custom target is always out of date, so every run recompiles all of core/.
    add_custom_target(arm-check
        ${arm_check_commands}
        COMMENT "arm-check: compiling core/ with arm-none-eabi-g++ for cortex-a9"
        VERBATIM)
else()
    # Keep the project configurable without Vitis; only arm-check itself fails.
    add_custom_target(arm-check
        COMMAND ${CMAKE_COMMAND} -E echo "arm-check: compiler not found at ${FLORV_ARM_CXX}"
        COMMAND ${CMAKE_COMMAND} -E echo "Set it with: cmake -S . -B build -DFLORV_ARM_CXX=<path to arm-none-eabi-g++>"
        COMMAND ${CMAKE_COMMAND} -E false
        VERBATIM)
endif()
