// Copyright (c) 2016, XMOS Ltd, All rights reserved
/**
 * \file avb_1722_listener.xc
 * \brief AVB1722 Listener
 */
#include <xs1.h>
#include <platform.h>
#include <xclib.h>
#include <print.h>
#include "avb_1722_def.h"
#include "avb_1722_listener.h"
#include "ethernet.h"
#include "avb_srp.h"
#include "avb_internal.h"
#include "default_avb_conf.h"
#include <debug_print.h>
#include "audio_output_fifo.h"

#define TIMEINFO_UPDATE_INTERVAL 50000000

#ifdef AVB_1722_FORMAT_61883_6
#define MAX_PKT_BUF_SIZE_LISTENER (AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE + AVB_CIP_HDR_SIZE + AVB1722_LISTENER_MAX_NUM_SAMPLES_PER_CHANNEL * AVB_MAX_CHANNELS_PER_LISTENER_STREAM * 4 + 2)
#endif

static transaction configure_stream(chanend c,
                                    avb_1722_stream_info_t &s,
                                    buffer_handle_t h)
{
	int media_clock;

	c :> media_clock;
	c :> s.rate;
	c :> s.num_channels;

	for(int i=0;i<s.num_channels;i++) {
		c :> s.map[i];
		if (s.map[i] >= 0)
		{
      unsafe {
        enable_audio_output_fifo(h, s.map[i], media_clock);
      }
		}
	}

	s.active = 1;
	s.state = 0;
	s.num_channels_in_payload = 0;
	s.chan_lock = 0;
	s.prev_num_samples = 0;
	s.dbc = -1;
}

static transaction adjust_stream(chanend c,
                                 avb_1722_stream_info_t &s,
                                 buffer_handle_t h)
{
	int cmd;
	c :> cmd;
	switch (cmd) {
  case AVB1722_ADJUST_LISTENER_CHANNEL_MAP:
  {
    int new_map[AVB_MAX_CHANNELS_PER_LISTENER_STREAM];
    int media_clock;
    c :> media_clock;
    for(int i=0;i<s.num_channels;i++) {
      c :> new_map[i];
      if (new_map[i] != s.map[i])
      {
        s.map[i] = new_map[i];
      }
    }
    break;
  }
	case AVB1722_ADJUST_LISTENER_VOLUME:
		{
#ifdef MEDIA_OUTPUT_FIFO_VOLUME_CONTROL
			int volume, count;
			c :> count;
			for(int i=0;i<count;i++) {
				c :> volume;
				if (i < s.num_channels) audio_output_fifo_set_volume(h, s.map[i], volume);
			}
#endif
		}
		break;
	}
}


static void disable_stream(avb_1722_stream_info_t &s,
                           buffer_handle_t h)
{
	for(int i=0;i<s.num_channels;i++) {
		if (s.map[i] >= 0)
		{
      unsafe {
        disable_audio_output_fifo(h, s.map[i]);
      }
		}
	}

	s.active = 0;
	s.state = 0;
}

void avb_1722_listener_init(chanend c_listener_ctl,
                            avb_1722_listener_state_t &st,
                            int num_streams)
{
  // register how many streams this listener unit has
  st.router_link = avb_register_listener_streams(c_listener_ctl, num_streams);

  st.notified_buf_ctl = 0;

  for (int i=0;i<MAX_AVB_STREAMS_PER_LISTENER;i++) {
    st.listener_streams[i].active = 0;
    st.listener_streams[i].state = 0;
  }
}

void avb_1722_listener_handle_packet(unsigned int rxbuf[],
                                     ethernet_packet_info_t &packet_info,
                                     chanend c_buf_ctl,
                                     avb_1722_listener_state_t &st,
                                     ptp_time_info_mod64 &?timeInfo,
                                     buffer_handle_t h)
{
  unsigned stream_id = packet_info.filter_data;

  if (packet_info.type != ETH_DATA) {
    return;
  }

  // process the audio packet if enabled.
  if (stream_id < MAX_AVB_STREAMS_PER_LISTENER &&
      st.listener_streams[stream_id].active) {
    // process the current packet
    avb_1722_listener_process_packet(c_buf_ctl,
                                     &(rxbuf, unsigned char[])[2],
                                     packet_info.len,
                                     st.listener_streams[stream_id],
                                     timeInfo,
                                     stream_id,
                                     st.notified_buf_ctl,
                                     h);
  }
}


#pragma select handler
void avb_1722_listener_handle_cmd(chanend c_listener_ctl,
                                  avb_1722_listener_state_t &st,
                                  buffer_handle_t h)
{
  int cmd;
  slave {
    c_listener_ctl :> cmd;
    switch (cmd)
      {
      case AVB1722_CONFIGURE_LISTENER_STREAM:
        {
          int stream_num;
          c_listener_ctl :> stream_num;
          configure_stream(c_listener_ctl,
                           st.listener_streams[stream_num],
                           h);
          break;
        }
      case AVB1722_ADJUST_LISTENER_STREAM:
        {
          int stream_num;
          c_listener_ctl :> stream_num;
          adjust_stream(c_listener_ctl,
                        st.listener_streams[stream_num], h);
          break;
        }
      case AVB1722_DISABLE_LISTENER_STREAM:
        {
          int stream_num;
          c_listener_ctl :> stream_num;
          disable_stream(st.listener_streams[stream_num], h);
          break;
        }
      case AVB1722_GET_ROUTER_LINK:
        c_listener_ctl <: st.router_link;
        break;
      default:
        break;
      }
    }
}


#pragma unsafe arrays
void avb_1722_listener(streaming chanend c_eth_rx_hp,
                       chanend? c_buf_ctl,
                       chanend? c_ptp,
                       chanend c_listener_ctl,
                       int num_streams,
                       client push_if audio_output_buf)
{
  avb_1722_listener_state_t st;
  timer tmr;
  ethernet_packet_info_t packet_info;
  unsigned int rxbuf[(MAX_PKT_BUF_SIZE_LISTENER+3)/4];

#if defined(AVB_1722_FORMAT_61883_4)
  // Conditional due to compiler bug 11998.
  unsigned t;
  int pending_timeinfo = 0;
  ptp_time_info_mod64 timeInfo;
#endif
  set_thread_fast_mode_on();
  avb_1722_listener_init(c_listener_ctl, st, num_streams);

#if defined(AVB_1722_FORMAT_61883_4)
  // Conditional due to compiler bug 11998.
  ptp_request_time_info_mod64(c_ptp);
  ptp_get_requested_time_info_mod64(c_ptp, timeinfo);
  tmr	:> t;
  t+=TIMEINFO_UPDATE_INTERVAL;
#endif

  buffer_handle_t h = audio_output_buf.get_handle();

  while (1) {

#pragma ordered
    select
      {
#if !defined(AVB_1722_FORMAT_61883_4)
        // Conditional due to compiler bug 11998.
        // FIXME: stream_num variable is not the stream num, it is the FIFO!
      case !isnull(c_buf_ctl) => c_buf_ctl :> int fifo_index:
          audio_output_fifo_handle_buf_ctl(c_buf_ctl, h, fifo_index, st.notified_buf_ctl, tmr);
        break;
#endif

#if defined(AVB_1722_FORMAT_61883_4)
        // The PTP server has sent new time information
      case !isnull(c_ptp) => ptp_get_requested_time_info_mod64(c_ptp, timeInfo):
        pending_timeinfo = 0;
        break;
#endif

      case ethernet_receive_hp_packet(c_eth_rx_hp, &(rxbuf, unsigned char[])[2], packet_info):
        avb_1722_listener_handle_packet(rxbuf,
                                        packet_info,
                                        c_buf_ctl,
                                        st,
                                        #ifdef AVB_1722_FORMAT_61883_4
                                        timeInfo
                                        #else
                                        null
                                        #endif
                                        ,h);
        break;


#if defined(AVB_1722_FORMAT_61883_4)
        // Conditional due to compiler bug 11998
        // Periodically ask the PTP server for new time information
      case !isnull(c_ptp) => tmr when timerafter(t) :> t:
        if (!pending_timeinfo) {
          ptp_request_time_info_mod64(c_ptp);
          pending_timeinfo = 1;
        }
        t+=TIMEINFO_UPDATE_INTERVAL;
        break;
#endif

      case avb_1722_listener_handle_cmd(c_listener_ctl, st, h):
        break;
      }
  }
}
