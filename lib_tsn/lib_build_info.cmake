set(LIB_NAME lib_tsn)
set(LIB_VERSION 8.0.0)
set(LIB_DEPENDENT_MODULES   "lib_ethernet(develop)"
                            "lib_i2c(6.4.0)"
                            "lib_logging(2.1.0)"
                            "lib_xassert(4.3.1)"
                            "lib_otpinfo(2.1.0)"
                            "lib_random(1.2.0)")

set(LIB_OPTIONAL_HEADERS    "ethernet_conf.h"
                            "random_conf.h"
                            "avb_conf.h")

set(LIB_COMPILER_FLAGS      -g
                            -Os)

set(LIB_COMPILER_FLAGS_media_clock_server.xc            ${LIB_COMPILER_FLAGS} -g -O3)
set(LIB_COMPILER_FLAGS_audio_output_fifo.c              ${LIB_COMPILER_FLAGS} -O3)
set(LIB_COMPILER_FLAGS_avb_1722_talker_support_audio.c  ${LIB_COMPILER_FLAGS} -O3)
set(LIB_COMPILER_FLAGS_audio_buffering.xc               ${LIB_COMPILER_FLAGS} -O3)
set(LIB_COMPILER_FLAGS_avb_1722_talker.xc               ${LIB_COMPILER_FLAGS} -O3)

set(LIB_INCLUDES            api
                            src
                            src/util
                            src/srp
                            src/ptp
                            src/media_clock
                            src/media_clock/external_hw/CS2100CP
                            src/media_clock/external_hw/CS2300CP
                            src/avb
                            src/audio_buffering
                            src/1722_1
                            src/1722
                            src/1722/maap)

XMOS_REGISTER_MODULE()
