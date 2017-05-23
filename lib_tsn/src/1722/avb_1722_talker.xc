// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <xclib.h>
#include <print.h>
#include <xscope.h>

#include "avb_1722_def.h"
#include "avb_1722_listener.h"
#include "avb_1722_talker.h"
#include "ethernet.h"
#include "avb_srp.h"
#include "avb_internal.h"
#include "default_avb_conf.h"
#include "debug_print.h"
#include "audio_buffering.h"

#if AVB_NUM_SOURCES != 0

static transaction configure_stream(chanend avb1722_tx_config,
               avb1722_Talker_StreamConfig_t &stream,
               unsigned char mac_addr[MAC_ADRS_BYTE_COUNT]) {
  unsigned int streamIdExt;
  unsigned int rate;
  unsigned int tmp;

  avb1722_tx_config :> stream.sampleType;

  for (int i = 0; i < MAC_ADRS_BYTE_COUNT; i++) {
    int x;
    avb1722_tx_config :> x;
    stream.destMACAdrs[i] = x;
    stream.srcMACAdrs[i] = mac_addr[i];
  }

  stream.streamId[1] = ntoh_32(stream.srcMACAdrs);

  stream.streamId[0] =
  ((unsigned) stream.srcMACAdrs[4] << 24) |
  ((unsigned) stream.srcMACAdrs[5] << 16);

  avb1722_tx_config :> streamIdExt;

  stream.streamId[0] |= streamIdExt;

  avb1722_tx_config :> stream.num_channels;

  avb1722_tx_config :> stream.fifo_mask;

  for (int i=0;i<stream.num_channels;i++) {
    avb1722_tx_config :> stream.map[i];
  }

  avb1722_tx_config :> rate;

  avb1722_tx_config :> stream.presentation_delay;

  switch (rate)
  {
  case 8000:   stream.ts_interval = 1; break;
  case 16000:  stream.ts_interval = 2; break;
  case 32000:  stream.ts_interval = 8; break;
  case 44100:  stream.ts_interval = 8; break;
  case 48000:  stream.ts_interval = 8; break;
  case 88200:  stream.ts_interval = 16; break;
  case 96000:  stream.ts_interval = 16; break;
  case 176400: stream.ts_interval = 32; break;
  case 192000: stream.ts_interval = 32; break;
  default: __builtin_trap(); break;
  }

  tmp = ((rate / 100) << 16) / (AVB1722_PACKET_RATE / 100);
  stream.samples_per_packet_base = tmp >> 16;
  stream.samples_per_packet_fractional = tmp & 0xffff;
  stream.rem = 0;

  stream.current_samples_in_packet = 0;
  stream.timestamp_valid = 0;

  stream.initial = 1;
  stream.dbc_at_start_of_last_packet = 0;
  stream.active = 1;
  stream.sequence_number = 0;
#if NUM_ETHERNET_PORTS > 1
  stream.txport = AVB1722_PORT_UNINITIALIZED;
#else
  stream.txport = 0;
#endif
}

static void disable_stream(avb1722_Talker_StreamConfig_t &stream) {

  stream.streamId[1] = 0;
  stream.streamId[0] = 0;
  stream.active = 0;
}


static void start_stream(avb1722_Talker_StreamConfig_t &stream) {
  stream.sequence_number = 0;
  stream.initial = 1;
  stream.active = 2;
}

static void stop_stream(avb1722_Talker_StreamConfig_t &stream) {
  stream.active = 1;
}


void avb_1722_talker_init(chanend c_talker_ctl,
                          avb_1722_talker_state_t &st,
                          int num_streams)
 {
  st.vlan = 0;
  st.cur_avb_stream = 0;
  st.max_active_avb_stream = -1;

  for (int i=0; i < AVB_NUM_SOURCES; i++) {
    memset(&st.tx_buf[i], MAX_PKT_BUF_SIZE_TALKER, 0);
    st.tx_buf_fill_size[i] = 0;
  }

  // register how many streams this talker unit has
  avb_register_talker_streams(c_talker_ctl, num_streams, st.mac_addr);

  for (int i = 0; i < AVB_MAX_STREAMS_PER_TALKER_UNIT; i++)
    st.talker_streams[i].active = 0;

  st.counters.sent_1722 = 0;
}


#pragma select handler
void avb_1722_talker_handle_cmd(chanend c_talker_ctl,
                                avb_1722_talker_state_t &st)
{
  int cmd;
  slave {
    c_talker_ctl :> cmd;
    switch (cmd)
    {
    case AVB1722_CONFIGURE_TALKER_STREAM:
      {
        int stream_num;
        c_talker_ctl :> stream_num;
        configure_stream(c_talker_ctl,
                         st.talker_streams[stream_num],
                         st.mac_addr);
        if (stream_num > st.max_active_avb_stream)
          st.max_active_avb_stream = stream_num;

        AVB1722_Talker_bufInit((st.tx_buf[stream_num],unsigned char[]),
                               st.talker_streams[stream_num],
                               st.vlan);

    }
    break;
    case AVB1722_DISABLE_TALKER_STREAM:
    {
      int stream_num;
      c_talker_ctl :> stream_num;
      disable_stream(st.talker_streams[stream_num]);
    }
    break;
    case AVB1722_TALKER_GO:
    {
      int stream_num;
      c_talker_ctl :> stream_num;
      start_stream(st.talker_streams[stream_num]);
    }
    break;
    case AVB1722_TALKER_STOP:
    {
      int stream_num;
      c_talker_ctl :> stream_num;
      stop_stream(st.talker_streams[stream_num]);
    }
    break;
    case AVB1722_SET_PORT:
    {
      int stream_num;
      c_talker_ctl :> stream_num;
      c_talker_ctl :> st.talker_streams[stream_num].txport;
#if NUM_ETHERNET_PORTS > 1
      debug_printf("Setting stream %d 1722 TX port to %d\n", stream_num, st.talker_streams[stream_num].txport);
#endif
      break;
    }
    case AVB1722_SET_VLAN:
      int stream_num;
      c_talker_ctl :> stream_num;
      c_talker_ctl :> st.vlan; // Should we maintain a VLAN state per stream, or just set it in the buffer as below?
      avb1722_set_buffer_vlan(st.vlan,(st.tx_buf[stream_num],unsigned char[]));
      break;
    case AVB1722_GET_COUNTERS:
      c_talker_ctl <: st.counters;
      break;
    default:
      break;
    }
  }
}

unsafe void avb_1722_talker_send_packets(streaming chanend c_eth_tx_hp,
                                        avb_1722_talker_state_t &st,
                                        ptp_time_info_mod64 &timeInfo,
                                        audio_double_buffer_t &sample_buffer)
{
  volatile audio_double_buffer_t *unsafe p_buffer =  (audio_double_buffer_t *unsafe) &sample_buffer;
  if (!p_buffer->data_ready) {
    return;
  }

  unsigned rd_buf = !p_buffer->active_buffer;
  audio_frame_t * unsafe frame = (audio_frame_t *)&p_buffer->buffer[rd_buf];

  if (st.max_active_avb_stream != -1) {
    for (int i=0; i < (st.max_active_avb_stream+1); i++) {
      if (st.talker_streams[i].active==2) { // TODO: Replace int with enum
        int packet_size = avb1722_create_packet((st.tx_buf[i], unsigned char[]),
                                                st.talker_streams[i],
                                                timeInfo,
                                                frame, i);
        if (!st.tx_buf_fill_size[i]) st.tx_buf_fill_size[i] = packet_size;
      }
      if (i == st.max_active_avb_stream) {
        p_buffer->data_ready = 0;
      }
    }

    for (int i=0; i < (st.max_active_avb_stream+1); i++) {
      int packet_size = st.tx_buf_fill_size[i];
      if (packet_size) {
        ethernet_send_hp_packet(c_eth_tx_hp, &(st.tx_buf[i], unsigned char[])[2], packet_size, ETHERNET_ALL_INTERFACES);
        st.tx_buf_fill_size[i] = 0;
        st.counters.sent_1722++;
        break;
      }
    }
  }
}

#define TIMEINFO_UPDATE_INTERVAL 50000000
/** This packetizes Audio samples into an AVB payload and transmit it across
 *  Ethernet.
 *
 *  1. Get audio samples from ADC fifo.
 *  2. Convert the local timer value to global PTP timestamp.
 *  3. AVB payload generation and transmit to Ethernet.
 */
void avb_1722_talker(chanend c_ptp,
                     streaming chanend c_eth_tx_hp,
                     chanend c_talker_ctl,
                     int num_streams,
                     client pull_if audio_input_buf) {
  avb_1722_talker_state_t st;
  ptp_time_info_mod64 timeInfo;
  timer tmr;
  unsigned t;
  int pending_timeinfo = 0;

  set_thread_fast_mode_on();
  // set_core_high_priority_on();
  avb_1722_talker_init(c_talker_ctl, st, num_streams);

  ptp_request_time_info_mod64(c_ptp);
  ptp_get_requested_time_info_mod64(c_ptp, timeInfo);

  tmr :> t;
  t+=TIMEINFO_UPDATE_INTERVAL;

  unsafe {
    buffer_handle_t h = audio_input_buf.get_handle();

    audio_double_buffer_t *unsafe sample_buffer = ((struct input_finfo *)h)->p_buffer;

    while (1)
    {
      select
      {
          // Process commands from the AVB control/application thread
        case avb_1722_talker_handle_cmd(c_talker_ctl, st): break;

          // Periodically ask the PTP server for new time information
        case tmr when timerafter(t) :> t:
          if (!pending_timeinfo) {
            ptp_request_time_info_mod64(c_ptp);
            pending_timeinfo = 1;
          }
          t+=TIMEINFO_UPDATE_INTERVAL;
          break;

          // The PTP server has sent new time information
        case ptp_get_requested_time_info_mod64(c_ptp, timeInfo):
          pending_timeinfo = 0;
          break;


          // Call the 1722 packet construction
        default:
          unsafe {
            avb_1722_talker_send_packets(c_eth_tx_hp, st, timeInfo, *sample_buffer);
          }
          break;
      }
    }
  }
}

#endif // AVB_NUM_SOURCES != 0
