// Copyright (c) 2015, XMOS Ltd, All rights reserved

#ifndef _audio_clock_CS2300CP_h_
#define _audio_clock_CS2300CP_h_
#include "i2c.h"

void audio_clock_CS2300CP_init(client interface i2c_master_if i2c, unsigned mclks_per_wordclk);

#endif
