// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <stdio.h>
#include "avb_1722_listener.h"
#include "avb_1722_talker.h"
#include "audio_buffering.h"
#include "gptp.h"
#include "xassert.h"

void init_stream_info(avb1722_Talker_StreamConfig_t &stream_info)
{
  int i;

  stream_info.dbc_at_start_of_last_packet = -1;
  stream_info.current_samples_in_packet = 0;
  stream_info.rem = 0;
  stream_info.streamId[0] = 0;
  stream_info.streamId[1] = 0;
  for (i = 0; i < stream_info.num_channels; i++) {
    stream_info.map[i] = i;
  }
}

#define ETHERNET_BUFFER_ALIGNMENT 2

int check_packet(const unsigned char buf[], int size, int ts_interval)
{
  const AVB_AVB1722_CIP_Header_t *hdr_1722;
  const AVB_DataHeader_t *hdr_avbtp;
  unsigned packet_data_length, num_samples;
  int index;

  hdr_avbtp = (const AVB_DataHeader_t*)(buf + ETHERNET_BUFFER_ALIGNMENT + AVB_ETHERNET_HDR_SIZE);
  hdr_1722 = (const AVB_AVB1722_CIP_Header_t*)(buf + ETHERNET_BUFFER_ALIGNMENT + AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE);

  packet_data_length = NTOH_U16(hdr_avbtp->packet_data_length);
  num_samples = (packet_data_length - 8) / hdr_1722->DBS / 4;
  index = (ts_interval - (hdr_1722->DBC % ts_interval)) % ts_interval;

  printf("DBS=%d DBC=%d TV=%d PDL=%d (%d samples) index=%d ",
    hdr_1722->DBS, hdr_1722->DBC, AVBTP_TV(hdr_avbtp), packet_data_length, num_samples, index);

  /* for packets with a valid timestamp (TV bit set), listener will use
   * 1722 section 6.3.4 formula to work out index of sample that corresponds to DBC:
   *
   *   (SYT_INTERVAL - DBC mod SYT_INTERVAL) mod SYT_INTERVAL
   *
   * if TV bit wrong, the index can exceed number of samples in packet
   * check for that
   */
  return AVBTP_TV(hdr_avbtp) && index >= num_samples;
}

void test(avb1722_Talker_StreamConfig_t &stream_info, const char samplerate_str[])
{
  ptp_time_info_mod64 time_info; /* uninitialised */
  audio_frame_t frame; /* uninitialised */
  unsigned char buf[1504];
  static int first = 1;
  int size;
  int i;

  printf("+%s\n", samplerate_str);

  AVB1722_Talker_bufInit(buf, stream_info, 0);
  init_stream_info(stream_info);

  if (first) {
    printf("index = (SYT_INTERVAL - (DBC mod SYT_INTERVAL)) mod SYT_INTERVAL\n");
    first = 0;
  }

  for (i = 0; i < 100; i++) {
    size = avb1722_create_packet(buf, stream_info, time_info, &frame, 0);
    printf("%d ", i);
    if (size > 0) {
      if (check_packet(buf, size, stream_info.ts_interval)) {
        printf("\n");
        fail("DBC index too large");
      }
    }
    else {
      printf("-");
    }
    printf("\n");
  }

  printf("PASS\n");
}

int main(void)
{
  avb1722_Talker_StreamConfig_t stream_info;
  stream_info.num_channels = 8;

  /* how sample count is worked out:
   *
   *   tmp = ((rate / 100) << 16) / (AVB1722_PACKET_RATE / 100);
   *   samples_per_packet_base = tmp >> 16;
   *   samples_per_packet_fractional = tmp & 0xffff;
   *
   * class A packet rate is 8000
   *
   * not using talker's configure-stream command, it requires too much state
   * for unit testing, calling talker-init and separately initialising stream state is better
   */

  stream_info.ts_interval = 16;
  stream_info.samples_per_packet_base = 12;
  stream_info.samples_per_packet_fractional = 0;
  test(stream_info, "96000");

  stream_info.ts_interval = 8;
  stream_info.samples_per_packet_base = 6;
  stream_info.samples_per_packet_fractional = 0;
  test(stream_info, "48000");

  stream_info.ts_interval = 8;
  stream_info.samples_per_packet_base = 5;
  stream_info.samples_per_packet_fractional = 33587;
  test(stream_info, "44100");

  return 0;
}
