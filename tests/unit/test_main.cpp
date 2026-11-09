// The one translation unit that holds doctest's implementation and its main().
// Every other file in tests/unit/ only includes "doctest.h" and adds TEST_CASEs.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest.h"
