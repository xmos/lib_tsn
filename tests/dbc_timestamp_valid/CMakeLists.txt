cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(dbc_timestamp_valid)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

set(APP_HW_TARGET           XCORE-200-EXPLORER)

set(APP_XC_SRCS             main.xc)

set(APP_DEPENDENT_MODULES   "lib_tsn(8.0.0)")

set(APP_COMPILER_FLAGS      -g
                            -Wall
                            -O0)

XMOS_REGISTER_APP()
