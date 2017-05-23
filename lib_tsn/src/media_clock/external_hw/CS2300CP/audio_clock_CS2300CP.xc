// Copyright (c) 2011-2017, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <xclib.h>
#include "print.h"
#include "i2c.h"
#include "media_clock_internal.h"
#include <stdlib.h>

static unsigned char regaddr[9] = {0x09,0x08,0x07,0x06,0x17,0x16,0x05,0x03,0x1E};
static unsigned char regdata[9] = {0x00,0x00,0x00,0x00,0x00,0x10,0x01,0x01,0x00};

// Set up the multiplier in the PLL clock generator
void audio_clock_CS2300CP_init(client interface i2c_master_if i2c)
{
  int deviceAddr = 0x4E;
  unsigned char data[1];
  int mult[1];
  const unsigned int mclks_per_wordclk = 512;

  // this is the muiltiplier in the PLL, which takes the PLL reference clock and
  // multiplies it up to the MCLK frequency.
  // example: PLL_TO_WORD_MULTIPLIER = 100
  //          CS2300 ratio 25600 in 20.12 format
  //          25600 = 512 (mclks_per_wordclk) x 100 (PLL_TO_WORD_MULTIPLIER) / 2
  mult[0] = ((PLL_TO_WORD_MULTIPLIER << 11) * mclks_per_wordclk);
  regdata[0] = (mult,char[])[0];
  regdata[1] = (mult,char[])[1];
  regdata[2] = (mult,char[])[2];
  regdata[3] = (mult,char[])[3];

  for(int i = 8; i >= 0; i--) {
    data[0] = (regdata,unsigned char[])[i];
    i2c.write_reg(deviceAddr, regaddr[i], data[0]);
  }
}
