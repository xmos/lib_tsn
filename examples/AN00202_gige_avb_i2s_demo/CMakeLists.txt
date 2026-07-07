cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_gige_avb_i2s_demo)

set(APP_HW_TARGET           SLICEKIT-ETH-TRIANGLE1-PLL-TRIANGLE0.xn)

set(APP_DEPENDENT_MODULES   "lib_tsn(8.0.0)"
                            "lib_i2s(6.0.1)")


set(APP_COMPILER_FLAGS      -Os
                            -g
                            -report
                            -lquadflash)

set(APP_COMPILER_FLAGS_main.xc ${APP_COMPILER_FLAGS} -falways-inline -O3)

set(APP_XSCOPE_SRCS         src/config.xscope)
set(APP_INCLUDES            src
                            src/aem_descriptors.generated)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)


# Run AEM descriptor script
execute_process(
    COMMAND python2 ${CMAKE_CURRENT_LIST_DIR}/src/generate.py ${CMAKE_CURRENT_LIST_DIR}/src/ ${CMAKE_CURRENT_LIST_DIR}/src/aem_descriptors.generated/
    COMMAND echo "running python AEM generate"
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})


XMOS_REGISTER_APP()
