// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef _audio_codec_CS42448_h_
#define _audio_codec_CS42448_h_
#include "avb_conf.h"
#include "i2c.h"

void audio_codec_CS4270_init(out port p_codec_reset,
                             int mask,
                             int codec_addr,
                             client interface i2c_master_if i2c
                              );



#endif
