// Copyright (c) 2015-2017, XMOS Ltd, All rights reserved
#ifndef __AUDIO_BUFFERING_H__
#define __AUDIO_BUFFERING_H__

#include "default_avb_conf.h"
#include <stdint.h>
#include <xccompat.h>
#include <string.h>
#include "xc2compat.h"
#include "hwlock.h"

/**
 * \brief This type provides a handle to an audio buffer.
 **/
typedef void * unsafe buffer_handle_t;

typedef struct audio_frame_t {
    uint32_t timestamp;
    uint32_t samples[AVB_NUM_MEDIA_INPUTS];
} audio_frame_t;

typedef struct audio_double_buffer_t {
  unsigned int active_buffer;
  unsigned int data_ready;
  unsigned int data_taken;
  audio_frame_t buffer[2];
} audio_double_buffer_t;

struct input_finfo {
  audio_double_buffer_t * unsafe p_buffer;
};

struct output_finfo {
  unsigned int *unsafe p_buffer[AVB_NUM_MEDIA_OUTPUTS];
};

typedef int audio_output_fifo_t;

#ifdef __XC__
typedef interface push_if {
  buffer_handle_t get_handle();
} push_if;

typedef interface pull_if {
  buffer_handle_t get_handle();
} pull_if ;

[[distributable]]
void audio_input_sample_buffer(server push_if i_push, server pull_if i_pull);
[[distributable]]
void audio_output_sample_buffer(server push_if i_push, server pull_if i_pull);

typedef enum audio_io_t
{
  AUDIO_I2S_IO,
  AUDIO_TDM_IO
} audio_io_t;

void audio_buffer_manager(streaming chanend c_audio,
                           client push_if audio_input_buf,
                           client pull_if audio_output_buf,
                           chanend c_media_ctrl,
                           const audio_io_t audio_io_type);
unsafe void media_ctl_register(chanend media_ctl,
                        unsigned num_in,
                        audio_output_fifo_t *unsafe output_fifos,
                        unsigned num_out,
                        int clk_ctl_index);
#endif


void audio_buffers_initialize(REFERENCE_PARAM(audio_double_buffer_t, buffer));


#define audio_buffers_swap_active_buffer audio_buffers_swap_active_buffer0

#ifdef __XC__

unsafe static audio_frame_t *unsafe audio_buffers_swap_active_buffer0(audio_double_buffer_t &buffer)
{
  volatile audio_double_buffer_t * unsafe p_buffer = (volatile audio_double_buffer_t * unsafe)(&buffer);
  asm("#write_active_buffer");
  p_buffer->active_buffer = !p_buffer->active_buffer;
  asm("#write_data_ready");
  p_buffer->data_ready = 1;

  return &p_buffer->buffer[p_buffer->active_buffer];
}

unsafe inline void audio_buffers_swap_active_buffer1(audio_double_buffer_t &buffer){
  audio_buffers_swap_active_buffer0(buffer);
}
#endif

#endif // __AUDIO_BUFFERING_H__
