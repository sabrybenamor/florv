# Runs florv once and fails unless it exits with the expected code.
# ctest only knows "zero or not"; this script tells the exit codes apart.
#
#   cmake -DFLORV=<path to florv> -DARGS=<arguments separated by |>
#         -DEXPECT_EXIT=<number> [-DEXPECT_STDOUT=<text>] -P run_florv.cmake
#
# ARGS uses | between arguments because ; is CMake's own list separator.
# EXPECT_STDOUT, when given, must appear somewhere in what florv prints.

if(NOT DEFINED FLORV OR NOT DEFINED EXPECT_EXIT)
    message(FATAL_ERROR "run_florv.cmake needs -DFLORV=... and -DEXPECT_EXIT=...")
endif()

set(arguments "")
if(DEFINED ARGS AND NOT ARGS STREQUAL "")
    string(REPLACE "|" ";" arguments "${ARGS}")
endif()

execute_process(
    COMMAND "${FLORV}" ${arguments}
    RESULT_VARIABLE exit_code
    OUTPUT_VARIABLE standard_output
    ERROR_VARIABLE standard_error)

message(STATUS "command: florv ${arguments}")
message(STATUS "exit code: ${exit_code} (expected ${EXPECT_EXIT})")
message(STATUS "stdout:\n${standard_output}")
message(STATUS "stderr:\n${standard_error}")

if(NOT exit_code STREQUAL EXPECT_EXIT)
    message(FATAL_ERROR "florv exited with ${exit_code}, expected ${EXPECT_EXIT}")
endif()

if(DEFINED EXPECT_STDOUT)
    string(FIND "${standard_output}" "${EXPECT_STDOUT}" position)
    if(position EQUAL -1)
        message(FATAL_ERROR "florv did not print \"${EXPECT_STDOUT}\"")
    endif()
endif()
