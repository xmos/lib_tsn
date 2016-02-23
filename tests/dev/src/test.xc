// Copyright (c) 2016, XMOS Ltd, All rights reserved

#include <platform.h>
#include "xassert.h"
#include "debug_print.h"
#include "ethernet.h"
#include "gptp.h"
#include "simple_talker.h"
#include "simple_controller.h"
#include "test.h"

#define ETHERNET_BUFFER_ALIGNMENT 2
#define AUDIO_PACKET_RATE_HZ 48000
#define PTP_DEFAULT_GM_CAPABLE_PRIORITY1 250
#define ONE_SECOND (XS1_TIMER_HZ)

void test_app(client ethernet_cfg_if i_cfg, chanend c_ptp, streaming chanend c_tx_hp,
  client ethernet_rx_if i_rx, client ethernet_tx_if i_tx, struct test_conf &test_conf)
{
  timer tmr, tmr2;
  unsigned char priority_current;
  unsigned char packet_buf_talker[1500 + ETHERNET_BUFFER_ALIGNMENT];
  unsigned char packet_buf_controller_rx[1500];
  ethernet_packet_info_t packet_info;
  int packet_size;
  ptp_time_info_mod64 time_info, time_info_returned;
  int talker_timestamp_delay;
  int ptp_change_interval;
  unsigned audio_sample_count;
  unsigned audio_packet_count;
  int pending_timeinfo;
  int time_info_countdown;
  simple_talker_config_t talker_config;
  unsigned char own_mac_addr[6];
  unsigned char stream_id[8];
  int ptp_change_count;
  int t, t2;

  priority_current = PTP_DEFAULT_GM_CAPABLE_PRIORITY1;

  ptp_set_master_rate(c_ptp, test_conf.ptp_master_rate);

  i_cfg.get_macaddr(0, own_mac_addr);

  simple_controller_init(i_cfg, i_rx, own_mac_addr, stream_id);

  talker_config = simple_talker_init(packet_buf_talker, sizeof(packet_buf_talker), own_mac_addr, stream_id, !test_conf.disable_talker);
  audio_sample_count = 0;
  audio_packet_count = 0;

  ptp_get_time_info_mod64(c_ptp, time_info);
  pending_timeinfo = 0;
  time_info_countdown = 0;

  tmr :> t;
  t += ONE_SECOND;
  ptp_change_interval = test_conf.ptp_change_interval_min_sec;
  ptp_change_count = 0;
  talker_timestamp_delay = 0;

  tmr2 :> t2;
  t2 += XS1_TIMER_HZ / AUDIO_PACKET_RATE_HZ;  /* approximate rate - only integer division */

  while (1) {
    select {
      case ptp_get_requested_time_info_mod64(c_ptp, time_info_returned):
        if (time_info_countdown > 0) {
          debug_printf("1722T delayed time info transition %d\n", time_info_countdown);
          time_info_countdown--;
        }
        else {
          time_info = time_info_returned;
        }
        pending_timeinfo = 0;
        break;

      case i_rx.packet_ready():
        i_rx.get_packet(packet_info, packet_buf_controller_rx, sizeof(packet_buf_controller_rx));
        simple_controller_packet_received(packet_buf_controller_rx, packet_info);
        break;

      case tmr when timerafter(t) :> void: {
        if (ptp_change_count == ptp_change_interval) {
          if (priority_current == PTP_DEFAULT_GM_CAPABLE_PRIORITY1)
            priority_current = 100;
          else
            priority_current = PTP_DEFAULT_GM_CAPABLE_PRIORITY1;

          ptp_set_priority(c_ptp, priority_current, 248);
          ptp_reset_port(c_ptp, 0);
          time_info_countdown = talker_timestamp_delay;

          ptp_change_interval++;
          if (ptp_change_interval > test_conf.ptp_change_interval_max_sec)
            ptp_change_interval = test_conf.ptp_change_interval_min_sec;

          talker_timestamp_delay++;
          if (talker_timestamp_delay > test_conf.talker_timestamp_delay_max_sec)
            talker_timestamp_delay = 0;

          debug_printf("test: PTP change interval %d sec, talker timestamp delay %d sec\n",
            ptp_change_interval, talker_timestamp_delay);
          
          ptp_change_count = 0;
        }

        simple_controller_periodic(i_tx);

        if (!pending_timeinfo) {
          /* keep timeinfo request after any other PTP commands
           * so it's always completed before other commands are sent
           * PTP server doesn't maintain intermediate state and would
           * trap with a pending timeinfo request
           */
          ptp_request_time_info_mod64(c_ptp);
          pending_timeinfo = 1;
        }

        ptp_change_count++;
        t += ONE_SECOND;
        break;
      }

      case tmr2 when timerafter(t2) :> void: {
        packet_size = simple_talker_create_packet(talker_config, packet_buf_talker, sizeof(packet_buf_talker),
          time_info, t2, (audio_sample_count & 0xFFFFFF) << 8);

        if (packet_size > 0) {
          ethernet_send_hp_packet(c_tx_hp, &packet_buf_talker[ETHERNET_BUFFER_ALIGNMENT], packet_size, ETHERNET_ALL_INTERFACES);
          audio_packet_count++;
        }

        audio_sample_count++;
#if DEBUG_RUNNING_PACKET_COUNTER
        if ((audio_sample_count & 65535) == 0) {
          debug_printf("1722T last sample value %d (%d packets sent)\n", audio_sample_count, audio_packet_count);
        }
#endif

        t2 += XS1_TIMER_HZ / AUDIO_PACKET_RATE_HZ;
        break;
      }
    }
  }
}
