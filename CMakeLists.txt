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
