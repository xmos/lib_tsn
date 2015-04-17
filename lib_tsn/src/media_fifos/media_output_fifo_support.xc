// Copyright (c) 2015, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <xclib.h>
#include <print.h>
#include <stdlib.h>
#include <syscall.h>
#include <xscope.h>
#include "media_fifo.h"

void media_output_fifo_to_xc_channel(streaming chanend samples_out,
                                     media_output_fifo_t output_fifos[],
                                     int num_channels)
{
  while (1) {
    unsigned int size;
    unsigned timestamp;
    samples_out :> timestamp;
    for (int i=0;i<num_channels;i++) {
      unsigned sample;
      sample = media_output_fifo_pull_sample(output_fifos[i],
                                             timestamp);
      samples_out <: sample;

    }
  }
}


#pragma unsafe arrays
void
media_output_fifo_to_xc_channel_split_lr(streaming chanend samples_out,
                                         media_output_fifo_t output_fifos[],
                                         int num_channels)
{
  while (1) {
    unsigned timestamp;
    samples_out :> timestamp;
    for (int i=0;i<num_channels;i+=2) {
      unsigned sample;
      sample = media_output_fifo_pull_sample(output_fifos[i],
                                             timestamp);
      samples_out <: sample;
    }
    for (int i=1;i<num_channels;i+=2) {
      unsigned sample;
      sample = media_output_fifo_pull_sample(output_fifos[i],
                                             timestamp);
      samples_out <: sample;
    }
  }
}
