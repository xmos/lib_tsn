// Copyright (c) 2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include "gptp.h"
#include "avb_1722_talker.h"
#include "avb.h"
#include "simple_talker.h"

static struct simple_talker_config
{
  avb1722_Talker_StreamConfig_t sc;
} configs[1];

simple_talker_config_t simple_talker_init(unsigned char packet_buf[], int packet_buf_size,
  const unsigned char src_mac_addr[6])
{
  avb1722_Talker_StreamConfig_t *sc;
  unsigned tmp;

  sc = &configs[0].sc;

  sc->active = 2;
  sc->destMACAdrs[0] = 0xFF; /* TODO proper address */
  sc->destMACAdrs[1] = 0xFF;
  sc->destMACAdrs[2] = 0xFF;
  sc->destMACAdrs[3] = 0xFF;
  sc->destMACAdrs[4] = 0xFF;
  sc->destMACAdrs[5] = 0xFF;
  memcpy(sc->srcMACAdrs, src_mac_addr, 6);
  sc->streamId[1] = ntoh_32(sc->srcMACAdrs);
  sc->streamId[0] = ((unsigned)sc->srcMACAdrs[4] << 24) | ((unsigned)sc->srcMACAdrs[5] << 16);
  sc->streamId[0] |= 0; /* ext term */
  sc->num_channels = 1;
  sc->map[0] = 0;
  sc->fifo_mask = 1;
  sc->sampleType = AVB_FORMAT_MBLA_24BIT;
  sc->current_samples_in_packet = 0;
  sc->timestamp_valid = 0;
  sc->timestamp = 0;
  sc->dbc_at_start_of_last_fifo_packet = 0;

  sc->ts_interval = 8; /* 48000 */
  tmp = ((48000 / 100) << 16) / (AVB1722_PACKET_RATE / 100);
  sc->samples_per_packet_base = tmp >> 16;
  sc->samples_per_packet_fractional = tmp & 0xffff;
  sc->rem = 0;

  sc->initial = 1;
  sc->presentation_delay = AVB_DEFAULT_PRESENTATION_TIME_DELAY_NS;
  sc->transmit_ok = 1;
  sc->last_transmit_time = 0;
  sc->txport = 0;
  sc->sequence_number = 0;

  AVB1722_Talker_bufInit(packet_buf, *sc, 0);

  return 0;
}

int simple_talker_create_packet(simple_talker_config_t config,
  unsigned char packet_buf[], int packet_buf_size, ptp_time_info_mod64 time_info, int local_timestamp, int sample_value)
{
  audio_frame_t frame;
  int packet_size;

  frame.timestamp = local_timestamp;
  frame.samples[0] = sample_value;

  packet_size = avb1722_create_packet(packet_buf, configs[config].sc, time_info, &frame, 0);

  return packet_size;
}
