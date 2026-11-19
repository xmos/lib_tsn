cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_100Mbit_avb_i2s_demo)

set(APP_HW_TARGET           src/AN02054-QF60B.xn)

set(APP_DEPENDENT_MODULES   "lib_tsn(8.0.0)"
                            "lib_ethernet(4.1.0)"
                            "lib_i2c(6.4.0)"
                            "lib_i2s(5.1.0)")


set(APP_COMPILER_FLAGS      -Os
                            -g
                            -report
                            -lquadflash)

set(APP_COMPILER_FLAGS_main.xc ${APP_COMPILER_FLAGS} -falways-inline -O3)

set(APP_XSCOPE_SRCS         src/config.xscope)
set(APP_INCLUDES            src
                            src/aem_descriptors.generated)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)


# Generate AEM descriptor headers (Python 3)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
execute_process(
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_LIST_DIR}/src/generate.py ${CMAKE_CURRENT_LIST_DIR}/src/ ${CMAKE_CURRENT_LIST_DIR}/src/aem_descriptors.generated/
    WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    RESULT_VARIABLE AEM_GEN_RESULT
    OUTPUT_VARIABLE AEM_GEN_OUTPUT
    ERROR_VARIABLE AEM_GEN_ERROR)
if(NOT AEM_GEN_RESULT EQUAL 0)
    message(FATAL_ERROR "AEM descriptor generation failed:\n${AEM_GEN_OUTPUT}${AEM_GEN_ERROR}")
endif()


XMOS_REGISTER_APP()
