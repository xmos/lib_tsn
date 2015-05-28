# The TARGET variable determines what target system the application is 
# compiled for. It either refers to an XN file in the source directories
# or a valid argument for the --target option when compiling.

TARGET = XR-AUDIO-216-MC

# The APP_NAME variable determines the name of the final .xe file. It should
# not include the .xe postfix. If left blank the name will default to 
# the project name

APP_NAME =

# This variable controls where the include files for the app are found.
# In this application the extra include files may be found in a target
# specific directory for XMOS development boards

INCLUDE_DIRS = src

# This header file is marked as optional since it is only included for
# a known XMOS development board
OPTIONAL_HEADERS = avb_app_board_config.h

# The flags passed to xcc when building the application
# You can also set the following to override flags for a particular language:
#
#    XCC_XC_FLAGS, XCC_C_FLAGS, XCC_ASM_FLAGS, XCC_CPP_FLAGS
#
# If the variable XCC_MAP_FLAGS is set it overrides the flags passed to 
# xcc for the final link (mapping) stage.

XCC_FLAGS = -Os -save-temps -g -report -Xmapper --map -Xmapper MAPFILE -fxscope  -fno-xta-info -DRGMII=1 -lquadflash

XCC_FLAGS_main.xc = $(XCC_FLAGS) -falways-inline -O3

# The USED_MODULES variable lists other module used by the application. 

USED_MODULES = lib_otpinfo(>=2.0.0) lib_tsn(>=7.0.0) lib_i2s(>=2.0.1)

#=============================================================================
# The following part of the Makefile includes the common build infrastructure
# for compiling XMOS applications. You should not need to edit below here.

XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
