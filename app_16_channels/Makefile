TARGET = XR-AUDIO-216-MC
XCC_FLAGS = -Os -save-temps -g -report -fxscope -DRGMII=1 -lquadflash
XCC_FLAGS_main.xc = $(XCC_FLAGS) -falways-inline -O3
USED_MODULES = lib_tsn(>=7.0.0) lib_i2s(>=2.0.1)

XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
