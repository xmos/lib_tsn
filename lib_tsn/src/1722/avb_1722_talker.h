// Copyright (c) 2015, XMOS Ltd, All rights reserved
/**
 * \file avb_1722_talker.h
 * \brief IEC 61883-6/AVB1722 Talker definitions
 */


#ifndef __AVB_AVB1722_TALKER_H__
#define __AVB_AVB1722_TALKER_H__ 1

#include "avb_1722_def.h"
#include <xccompat.h>
#include "default_avb_conf.h"
#include "gptp.h"
#include "audio_buffering.h"

#if AVB_NUM_SOURCES > 0

#ifndef AVB_MAX_CHANNELS_PER_TALKER_STREAM
#define AVB_MAX_CHANNELS_PER_TALKER_STREAM 8
#endif

#ifndef AVB_MAX_STREAMS_PER_TALKER_UNIT
#define AVB_MAX_STREAMS_PER_TALKER_UNIT (AVB_NUM_SOURCES)
#endif

//! Data structure to identify Ethernet/AVB stream configuration.
typedef struct avb1722_Talker_StreamConfig_t
{
  //! 0=disabled, 1=enabled, 2=streaming
  int active;
  //! the destination mac address - typically a multicast address
  unsigned char destMACAdrs[MAC_ADRS_BYTE_COUNT];
  //! the source mac address - typically my own address
  unsigned char srcMACAdrs[MAC_ADRS_BYTE_COUNT];
  //! the stream ID
  unsigned int  streamId[2];
  //! number of channels in the stream
  unsigned int  num_channels;
  //! map from media fifos to channels in the stream
  unsigned int map[AVB_MAX_CHANNELS_PER_TALKER_STREAM];
  //! word containing the bit flags for the fifo map above
  unsigned int fifo_mask;
  //! the type of samples in the stream
  unsigned int sampleType;

  unsigned int current_samples_in_packet;

  unsigned int timestamp_valid;

  unsigned int timestamp;

  //! Data Block Count (count of samples transmitted in the stream)
  //! From 61883: "A data block contains all data arriving at the transmitter within
  //! an audio sample period. The data block contains all the data which make up an event
  unsigned int dbc_at_start_of_last_fifo_packet;
  //! Number of samples per packet in the audio fifo (known as the SYT_INTERVAL in 61883)
  unsigned int ts_interval;
  //! Number of samples per 1722 packet (integer part)
  unsigned int samples_per_packet_base;
  //! Number of samples per 1722 packet (16.16)
  unsigned int samples_per_packet_fractional;
  //! An accumulator for the fractional part
  unsigned int rem;
  //! a flag, true when the stream has just been initialised
  unsigned int initial;
  //! the delay in ms that is added to the current PTP time
  unsigned presentation_delay;
  //! 1 when the packet should be transmitted without checking the transmission timer
  unsigned transmit_ok;
  //! the internal clock count when the last 1722 packet was transmitted
  int last_transmit_time;
  //! the port to transmit the packet on
  int txport;
  //! a transmitted packet sequence counter
  char sequence_number;
} avb1722_Talker_StreamConfig_t;


/** Sets the vlan id in outgoing packet buffer for outgoing 1722 packets.
 */
void avb1722_set_buffer_vlan(int vlan,
                             unsigned char Buf[]);

/** This configure AVB Talker buffer for a given stream configuration.
 *  It updates the static portion of Ehternet/AVB transport layer headers.
 */
void AVB1722_Talker_bufInit(unsigned char Buf[],
                            REFERENCE_PARAM(avb1722_Talker_StreamConfig_t,
                                            pStreamConfig),
                            int vlan_id);

/** This receives user defined audio samples from local out stream and packetize
 *  them into specified AVB1722 transport packet.
 */
 #ifdef __XC__
extern "C" {
#endif
int avb1722_create_packet(unsigned char Buf[],
                          REFERENCE_PARAM(avb1722_Talker_StreamConfig_t,
                                          stream_info),
                          REFERENCE_PARAM(ptp_time_info_mod64,
                                          timeInfo),
                          audio_frame_t *frame,
                          int stream);
#ifdef __XC__
}
#endif

#ifdef AVB_1722_FORMAT_61883_6
#define MAX_PKT_BUF_SIZE_TALKER (AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE + AVB_CIP_HDR_SIZE + AVB1722_TALKER_MAX_NUM_SAMPLES_PER_CHANNEL * AVB_MAX_CHANNELS_PER_TALKER_STREAM * 4 + 4)
#endif

typedef struct avb_1722_talker_state_s {
  unsigned int tx_buf[AVB_NUM_SOURCES][(MAX_PKT_BUF_SIZE_TALKER + 3) / 4];
  unsigned int tx_buf_fill_size[AVB_NUM_SOURCES];
  avb1722_Talker_StreamConfig_t
    talker_streams[AVB_MAX_STREAMS_PER_TALKER_UNIT];
  int max_active_avb_stream ;
  int cur_avb_stream;
  unsigned char mac_addr[6];
  int vlan;
} avb_1722_talker_state_t;

#endif // AVB_NUM_SOURCES > 0

#endif
