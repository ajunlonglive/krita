include_directories(     ${CMAKE_SOURCE_DIR}/sdk/tests )

include(KritaAddBrokenUnitTest)

macro_add_unittest_definitions()


kis_add_test(
    KisGifTest.cpp
    TEST_NAME KisGifTest
    LINK_LIBRARIES kritaui Qt5::Test
    NAME_PREFIX "plugins-impex-"
    )
