// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <stdio.h>
#include <stdlib.h>
#include "avb_1722_listener.h"
#include "avb_1722_talker.h"
#include "avb_1722_def.h"
#include "audio_buffering.h"
#include "gptp.h"
#include "xassert.h"

void init_stream_info(avb1722_Talker_StreamConfig_t &stream_info)
{
  int i;
  stream_info.dbc_at_start_of_last_packet = 0;
  stream_info.current_samples_in_packet = 0;
  stream_info.rem = 0;
  stream_info.streamId[0] = 0;
  stream_info.streamId[1] = 0;
  for (i = 0; i < stream_info.num_channels; i++) {
    stream_info.map[i] = i;
  }
}

#define ETHERNET_BUFFER_ALIGNMENT 2

int check_packet(const unsigned char buf[], int size, int ts_interval_samples, int ts_interval_us_nominal, unsigned &ts_prev, uint32_t frame_timestamp, int frame_index)
{
  const AVB_AVB1722_CIP_Header_t *hdr_1722;
  const AVB_DataHeader_t *hdr_avbtp;
  unsigned packet_data_length, num_samples;
  unsigned ts;
  unsigned diff_us;
  int index;
  int result;

  hdr_avbtp = (const AVB_DataHeader_t*)(buf + ETHERNET_BUFFER_ALIGNMENT + AVB_ETHERNET_HDR_SIZE);
  hdr_1722 = (const AVB_AVB1722_CIP_Header_t*)(buf + ETHERNET_BUFFER_ALIGNMENT + AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE);
  ts = AVBTP_TIMESTAMP(hdr_avbtp);

  packet_data_length = NTOH_U16(hdr_avbtp->packet_data_length);
  num_samples = (packet_data_length - 8) / hdr_1722->DBS / 4;
  index = (ts_interval_samples - (hdr_1722->DBC % ts_interval_samples)) % ts_interval_samples;

  /* called for each packet, so print details of frame that closed the packet */
  printf("frame=%d:%d DBC=%d TV=%d ts=%u -> num_samples=%d index=%d\n",
    frame_index, frame_timestamp, hdr_1722->DBC, AVBTP_TV(hdr_avbtp), ts, num_samples, index);

  result = 0;

  /* check that timestamp offset based on 1722 formula points to a valid sample
   *
   * 1722 D13 section 6.3.4:
   *
   *   (SYT_INTERVAL - DBC mod SYT_INTERVAL) mod SYT_INTERVAL
   */
  if (AVBTP_TV(hdr_avbtp) && index >= num_samples) {
    printf("DBC index too large: index=%d num_samples=%d\n", index, num_samples);
    result |= 1;
  }

  /* check that timestamps are valid and spaced apart by SYT_INTERVAL sample times
   * will be in PTP domain (nanoseconds)
   */
  diff_us = (ts - ts_prev) / 1000;
  if (ts_prev != 0 && AVBTP_TV(hdr_avbtp) &&
    (diff_us > ts_interval_us_nominal + 1 || diff_us < ts_interval_us_nominal - 1)) {
    printf("timestamp out of range: current=%d previous=%d diff_us=%d nominal_us=%d\n",
      ts, ts_prev, diff_us, ts_interval_us_nominal);
    result |= 2;
  }
  ts_prev = ts;

  return result;
}

void set_samples_per_packet(avb1722_Talker_StreamConfig_t &stream_info, unsigned samplerate)
{
  unsigned tmp;
  tmp = ((samplerate / 100) << 16) / (AVB1722_PACKET_RATE / 100);
  stream_info.samples_per_packet_base = tmp >> 16;
  stream_info.samples_per_packet_fractional = tmp & 0xffff;
}

unsigned syt_interval_table(unsigned samplerate)
{
  /* IEC 61883-6, Table 20 - Default SFC Table */
  switch (samplerate) {
    case 32000: return 8;
    case 44100: return 8;
    case 48000: return 8;
    case 88200: return 16;
    case 96000: return 16;
    case 176400: return 32;
    case 192000: return 32;
    default:
      __builtin_unreachable();
      return -1;
  }
}

void test(unsigned num_channels, unsigned samplerate, unsigned num_frames)
{
  avb1722_Talker_StreamConfig_t stream_info;
  ptp_time_info_mod64 time_info;
  audio_frame_t frame;
  unsigned char buf[1504];
  int size;
  int i;
  int ts_interval_us_nominal;
  unsigned ts_prev;

  /* PTP time info of all zeroes will just convert local timer timestamps to nanoseconds */
  time_info.local_ts = 0;
  time_info.ptp_ts_hi = 0;
  time_info.ptp_ts_lo = 0;
  time_info.ptp_adjust = 0;
  time_info.inv_ptp_adjust = 0;

  /* not using talker's configure-stream command, it requires too much state
   * for unit testing, calling talker-init and separately initialising stream state is ok
   */
  stream_info.num_channels = num_channels;
  stream_info.ts_interval = syt_interval_table(samplerate);
  set_samples_per_packet(stream_info, samplerate);
  AVB1722_Talker_bufInit(buf, stream_info, 0);
  init_stream_info(stream_info);

  ts_interval_us_nominal = 1000000 * stream_info.ts_interval / samplerate;

  printf("+%d channels %d frames %d, SYT_INTERVAL %d samples = %dus\n",
    num_channels, num_frames, samplerate, stream_info.ts_interval, ts_interval_us_nominal);

  ts_prev = 0;

  for (i = 0; i < num_frames; i++) {
    /* correct timestamp in timer units for given samplerate */
    frame.timestamp = (unsigned long long)XS1_TIMER_HZ * i / samplerate;

    size = avb1722_create_packet(buf, stream_info, time_info, &frame, 0);

    if (size > 0) {
      if (check_packet(buf, size, stream_info.ts_interval, ts_interval_us_nominal, ts_prev,
        frame.timestamp, i) != 0) {
        exit(1);
      }
    }
  }

  printf("PASS\n");
}

int main(void)
{
  unsigned num_channels[] = {1, 2, 4, 8};
  unsigned num_frames = 100;
  unsigned samplerate[] = {48000, 96000, 44100};
  unsigned i, j;

  for (i = 0; i < sizeof(num_channels) / sizeof(int); i++) {
    for (j = 0; j < sizeof(samplerate) / sizeof(int); j++) {
      test(num_channels[i], samplerate[j], num_frames);
    }
  }

  return 0;
}
