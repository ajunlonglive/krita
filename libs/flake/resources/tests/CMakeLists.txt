include(ECMAddTests)

include_directories(${CMAKE_SOURCE_DIR}/sdk/tests)

macro_add_unittest_definitions()

kis_add_tests(
    KoGamutMaskTest.cpp
    LINK_LIBRARIES kritaflake kritaimage Qt5::Test
    NAME_PREFIX "libs-flake-"
    )
