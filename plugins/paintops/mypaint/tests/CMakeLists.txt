########### next target ###############
include_directories(${CMAKE_SOURCE_DIR}/sdk/tests)
include_directories(${LIBMYPAINT_INCLUDE_DIR})
link_directories(${LIBMYPAINT_LIBRARIES})

macro_add_unittest_definitions()

include(KritaAddBrokenUnitTest)


kis_add_test(
    kis_mypaintop_test.cpp ../MyPaintPaintOpSettings.cpp ../MyPaintPaintOpPreset.cpp ../MyPaintSurface.cpp
    TEST_NAME KisMyPaintOpTest
    NAME_PREFIX "plugins-kismypaintop-"
    LINK_LIBRARIES kritaimage kritamypaintop_static kritalibpaintop mypaint Qt5::Test
    )

