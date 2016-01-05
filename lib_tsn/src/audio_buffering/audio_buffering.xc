// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include "audio_buffering.h"
#include <xs1.h>
#include <string.h>
#include "debug_print.h"
#include <xscope.h>
#include <print.h>
#include "audio_output_fifo.h"

unsafe void media_ctl_register(chanend media_ctl,
                        unsigned num_in,
                        audio_output_fifo_t *unsafe output_fifos,
                        unsigned num_out,
                        int clk_ctl_index)
{
  unsigned tile_id;
  tile_id = get_local_tile_id();
  media_ctl <: tile_id;
  media_ctl <: clk_ctl_index;
  media_ctl <: num_in;
  for (int i=0;i<num_in;i++) {
    int stream_num;
    media_ctl :> stream_num;
    media_ctl <: 0;
  }
  media_ctl <: num_out;
  for (int i=0;i<num_out;i++) {
    int fifo_index;
    media_ctl :> fifo_index;
    media_ctl <: output_fifos[i];

    audio_output_fifo_init((buffer_handle_t)output_fifos, fifo_index);
  }
}

static void init_audio_input_buffer(audio_double_buffer_t &buffer)
{
  buffer.active_buffer = 0;
  buffer.data_ready = 0;
}

static void init_audio_output_fifos(struct output_finfo &inf,
                       audio_output_fifo_data_t ofifo_data[],
                       int n)
{
  unsafe {
    for(int i=0;i<n;i++) {
      inf.p_buffer[i] = (unsigned int *unsafe)&ofifo_data[i];
    }
  }
}


[[always_inline]]
#pragma unsafe arrays
unsafe static audio_frame_t *unsafe audio_buffers_swap_active_buffer(audio_double_buffer_t &buffer);


[[distributable]]
void audio_input_sample_buffer(server push_if i_push, server pull_if i_pull)
{
  audio_double_buffer_t input_sample_buf;
  init_audio_input_buffer(input_sample_buf);
  struct input_finfo inf;

  unsafe {
    inf.p_buffer = &input_sample_buf;
  }

  while (1) {
    select {
    case i_push.get_handle() -> buffer_handle_t res:
      unsafe {
        res = (void * unsafe) &inf;
      }
      break;
    case i_pull.get_handle() -> buffer_handle_t res:
      unsafe {
        res = (void * unsafe) &inf;
      }
      break;
    }
  }
}

[[distributable]]
void audio_output_sample_buffer(server push_if i_push, server pull_if i_pull)
{
  audio_output_fifo_data_t ofifo_data[AVB_NUM_MEDIA_OUTPUTS];
  struct output_finfo inf;
  init_audio_output_fifos(inf, ofifo_data, AVB_NUM_MEDIA_OUTPUTS);

  while (1) {
    select {
    case i_push.get_handle() -> buffer_handle_t res:
      unsafe {
        res = (void * unsafe) &inf;
      }
      break;
    case i_pull.get_handle() -> buffer_handle_t res:
      unsafe {
        res = (void * unsafe) &inf;
      }
      break;
    }
  }
}

#pragma unsafe arrays
void audio_buffer_manager(streaming chanend c_audio,
                         client push_if audio_input_buf,
                         client pull_if audio_output_buf,
                         chanend c_media_ctl,
                         const audio_io_t audio_io_type)
{
  unsafe {
    buffer_handle_t h_in = audio_input_buf.get_handle();
    audio_double_buffer_t *unsafe input_sample_buf = ((struct input_finfo *)h_in)->p_buffer;

    buffer_handle_t h_out = audio_output_buf.get_handle();
    audio_output_fifo_t *unsafe output_sample_buf = (audio_output_fifo_t *unsafe)((struct output_finfo *)h_out)->p_buffer;
    media_ctl_register(c_media_ctl, AVB_NUM_MEDIA_INPUTS,
                      output_sample_buf, AVB_NUM_MEDIA_OUTPUTS, 0);
    unsigned ctl_command;
    unsigned sample_rate;

    c_media_ctl :> ctl_command;
    c_media_ctl :> sample_rate;

    while (1) {

      int done = 0;
      unsigned timestamp = 0;
      int channel = 0;
      int32_t sample_out_buf[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
      unsigned tmp;
      unsigned restart = 0;

      c_audio <: input_sample_buf;
      c_audio <: sample_rate;

      if (audio_io_type == AUDIO_I2S_IO) {
        c_audio <: (int32_t *unsafe)&sample_out_buf;
      }
      else {
        for (int i=0; i < 2; i++) {
          c_audio <: (int32_t *unsafe)&sample_out_buf;
        }
      }

      while (!done) {
        select {
          #pragma ordered
          case c_audio :> uintptr_t buffer :
            audio_frame_t *buf = (audio_frame_t *)buffer;
            timestamp = buf->timestamp;
            break;

          case c_media_ctl :> ctl_command :
            c_media_ctl :> sample_rate;
            sample_out_buf[8] = 1;
            done = 1;
            soutct(c_audio, XS1_CT_END);
            break;

          default:
            unsafe {
              if (audio_io_type == AUDIO_I2S_IO) {
                #pragma loop unroll
                for (int i=0;i<AVB_NUM_MEDIA_OUTPUTS;i+=2) {
                  sample_out_buf[i] = audio_output_fifo_pull_sample(h_out, i,
                                                                    timestamp);
                }
                #pragma loop unroll
                for (int i=1;i<AVB_NUM_MEDIA_OUTPUTS;i+=2) {
                  sample_out_buf[i] = audio_output_fifo_pull_sample(h_out, i,
                                                                    timestamp);
                }
                c_audio <: (int32_t *unsafe)&sample_out_buf;
              }
              else {
                #pragma loop unroll
                for (int i=0;i<AVB_NUM_SINKS;i++) { // FIXME: This should be number of TDM lines
                  int index = channel + (i*8);
                  sample_out_buf[i] = audio_output_fifo_pull_sample(h_out, index,
                                                                    timestamp);
                }
                c_audio <: (int32_t *unsafe)&sample_out_buf;
                channel++;
                if (channel == 8) channel = 0;
              }
            }
            break;
        }
      }
    }
  }
}