// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include "debug_print.h"
#include <print.h>
#include <xscope.h>
#include "default_avb_conf.h"
#include <xclib.h>

#if AVB_NUM_SOURCES > 0 && (defined(AVB_1722_FORMAT_61883_6) || defined(AVB_1722_FORMAT_SAF))

#include <xccompat.h>
#include <string.h>

#include "avb_1722_talker.h"
#include "gptp.h"

// default audio sample type 24bits.
unsigned int AVB1722_audioSampleType = MBLA_24BIT;

/** This generates the required CIP Header with specified DBC value.
 *  It is called for every PDU and only updates the fields which
 *  change for each PDU
 *
 *  \param   buf[] buffer array to be populated.
 *  \param   dbc DBC value of CIP header to be populated.
 */
static void AVB1722_CIP_HeaderGen(unsigned char Buf[], int dbc)
{
    AVB_AVB1722_CIP_Header_t *pAVB1722Hdr = (AVB_AVB1722_CIP_Header_t *) &(Buf[AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE]);

    SET_AVB1722_CIP_DBC(pAVB1722Hdr, dbc);
}

/** Update fields in the 1722 header which change for each PDU
 *
 *  \param Buf the buffer containing the packet
 *  \param valid_ts the timestamp is valid flag
 *  \param avbtp_ts the 32 bit PTP timestamp
 *  \param pkt_data_length the number of samples in the PDU
 *  \param sequence_number the 1722 sequence number
 *  \param stream_id0 the bottom 32 bits of the stream id
 */
static void AVB1722_AVBTP_HeaderGen(unsigned char Buf[],
        int valid_ts,
        unsigned avbtp_ts,
        int pkt_data_length,
        int sequence_number,
        const unsigned stream_id0)
{
    AVB_DataHeader_t *pAVBHdr = (AVB_DataHeader_t *) &(Buf[AVB_ETHERNET_HDR_SIZE]);

    SET_AVBTP_PACKET_DATA_LENGTH(pAVBHdr, pkt_data_length);

    // only stamp the AVBTP timestamp when required.
    if (valid_ts) {
        SET_AVBTP_TV(pAVBHdr, 1); // AVB timestamp valid.
        SET_AVBTP_TIMESTAMP(pAVBHdr, avbtp_ts); // Valid ns field.
    } else {
        SET_AVBTP_TV(pAVBHdr, 0); // AVB timestamp not valid.
        SET_AVBTP_TIMESTAMP(pAVBHdr, 0); // NULL the timestmap field as well.
    }

    // update stream ID by adding stream number to preloaded stream ID
    // (ignoring the fact that talkerStreamIdExt is stored MSB-first - it's just an ID)
    SET_AVBTP_STREAM_ID0(pAVBHdr, stream_id0);

    // update the ...
    SET_AVBTP_SEQUENCE_NUMBER(pAVBHdr, sequence_number);
}


/** This configure AVB Talker buffer for a given stream configuration.
 *  It updates the static portion of Ehternet/AVB transport layer headers.
 */
void AVB1722_Talker_bufInit(unsigned char Buf0[],
        avb1722_Talker_StreamConfig_t *pStreamConfig,
        int vlanid)
{
    int i;
    unsigned char *Buf = &Buf0[2];
    AVB_Frame_t *pEtherHdr = (AVB_Frame_t *) &(Buf[0]);
    AVB_DataHeader_t *p1722Hdr = (AVB_DataHeader_t *) &(Buf[AVB_ETHERNET_HDR_SIZE]);
    AVB_AVB1722_CIP_Header_t *p61883Hdr = (AVB_AVB1722_CIP_Header_t *) &(Buf[AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE]);

    unsigned data_block_size;

    // store the sample type
    switch (pStreamConfig->sampleType)
    {
    case MBLA_20BIT:
        AVB1722_audioSampleType = MBLA_20BIT;
        data_block_size = pStreamConfig->num_channels * 1;
        break;
    case MBLA_16BIT:
        AVB1722_audioSampleType = MBLA_16BIT;
        data_block_size = pStreamConfig->num_channels / 2;
        break;
    case MBLA_24BIT:
        AVB1722_audioSampleType = MBLA_24BIT;
        data_block_size = pStreamConfig->num_channels * 1;
        break;
    default:
        AVB1722_audioSampleType = MBLA_24BIT;
        data_block_size = pStreamConfig->num_channels * 1;
        break;
    }

    // clear all the bytes in header.
    memset( (void *) Buf, 0, (AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE + AVB_CIP_HDR_SIZE));

    // 1. Initialise the ethernet layer.
    // copy both Src/Dest MAC address
    for (i = 0; i < MAC_ADRS_BYTE_COUNT; i++) {
        pEtherHdr->DA[i] = pStreamConfig->destMACAdrs[i];
        pEtherHdr->SA[i] = pStreamConfig->srcMACAdrs[i];
    }
    SET_AVBTP_TPID(pEtherHdr, AVB_TPID);
    SET_AVBTP_PCP(pEtherHdr, AVB_DEFAULT_PCP);
    SET_AVBTP_CFI(pEtherHdr, AVB_DEFAULT_CFI);
    SET_AVBTP_VID(pEtherHdr, vlanid);
    SET_AVBTP_ETYPE(pEtherHdr, AVB_1722_ETHERTYPE);

    // 2. Initialise the AVB TP layer.
    // NOTE: Since the data structure is cleared before we only set the requird bits.
    SET_AVBTP_SV(p1722Hdr, 1); // set stream ID to valid.
    SET_AVBTP_STREAM_ID0(p1722Hdr, pStreamConfig->streamId[0]);
    SET_AVBTP_STREAM_ID1(p1722Hdr, pStreamConfig->streamId[1]);

    // 3. Initialise the 61883 CIP protocol specific part
    SET_AVB1722_CIP_TAG(p1722Hdr, AVB1722_DEFAULT_TAG);
    SET_AVB1722_CIP_CHANNEL(p1722Hdr, AVB1722_DEFAULT_CHANNEL);
    SET_AVB1722_CIP_TCODE(p1722Hdr, AVB1722_DEFAULT_TCODE);
    SET_AVB1722_CIP_SY(p1722Hdr, AVB1722_DEFAULT_SY);

    SET_AVB1722_CIP_EOH1(p61883Hdr, AVB1722_DEFAULT_EOH1);
    SET_AVB1722_CIP_SID(p61883Hdr, AVB1722_DEFAULT_SID);
    SET_AVB1722_CIP_DBS(p61883Hdr, data_block_size);

    SET_AVB1722_CIP_FN(p61883Hdr, AVB1722_DEFAULT_FN);
    SET_AVB1722_CIP_QPC(p61883Hdr, AVB1722_DEFAULT_QPC);
    SET_AVB1722_CIP_SPH(p61883Hdr, AVB1722_DEFAULT_SPH);
    SET_AVB1722_CIP_DBC(p61883Hdr, AVB1722_DEFAULT_DBC);

    SET_AVB1722_CIP_EOH2(p61883Hdr, AVB1722_DEFAULT_EOH2);
    SET_AVB1722_CIP_FMT(p61883Hdr, AVB1722_DEFAULT_FMT);
    SET_AVB1722_CIP_FDF(p61883Hdr, AVB1722_DEFAULT_FDF);
    SET_AVB1722_CIP_SYT(p61883Hdr, AVB1722_DEFAULT_SYT);

}

int avb1722_create_packet(unsigned char Buf0[],
        avb1722_Talker_StreamConfig_t *stream_info,
        ptp_time_info_mod64 *timeInfo,
        audio_frame_t *frame,
        int stream)
{
    int num_channels = stream_info->num_channels;
    int current_samples_in_packet = stream_info->current_samples_in_packet;
    int stream_id0 = stream_info->streamId[0];
    unsigned int *map = stream_info->map;
    int total_samples_in_packet;
    int samples_per_channel;

    // align packet 2 chars into the buffer so that samples are
    // word align for fast copying.
    unsigned char *Buf = &Buf0[2];
    unsigned int *dest = (unsigned int *) &Buf[(AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE + AVB_CIP_HDR_SIZE)];

    int stride = num_channels;
    unsigned ptp_ts = 0;
    int pkt_data_length;

    dest += (current_samples_in_packet * stride);

    // Figure out the number of samples in the 1722 packet
    samples_per_channel = stream_info->samples_per_packet_base;

    if (stream_info->rem & 0xffff0000) {
        samples_per_channel += 1;
    }

    for (int i = 0; i < num_channels; i++) {
        unsigned sample = (frame->samples[map[i]] >> 8) | AVB1722_audioSampleType;
        sample = byterev(sample);
        *dest = sample;
        dest += 1;
    }

    current_samples_in_packet++;

    // samples_per_channel is the number of times we need to call this function
    // i.e. the number of audio frames we need to iterate through to get a full packet worth of samples
    if (current_samples_in_packet == samples_per_channel) {
        int timestamp_valid = 0;
        int dbc = stream_info->dbc_at_start_of_last_packet + 1;

        stream_info->rem += stream_info->samples_per_packet_fractional;
        if (samples_per_channel > stream_info->samples_per_packet_base) {
            stream_info->rem &= 0xffff;
        }

        total_samples_in_packet = samples_per_channel * num_channels;

        pkt_data_length = AVB_CIP_HDR_SIZE + (total_samples_in_packet << 2);

        // timestamp is valid in packets that contain a sample aligned to SYT_INTERVAL (i.e. DBC of K x SYT_INTERVAL)
        // DBC of current packet is DBC of last packet plus 1, call that d
        // current packet DBCs are d, d+1, ..., d+n-1, where n is number of samples in current packet
        // SYT interval starts at floor((d+n-1)/SYT_INTERVAL)*SYT_INTERVAL = s
        // for this to fall within current packet, we need s >= d
        // see 1722 section 6.3.4 (IEC 61883-6 timing and synchronization)
        timestamp_valid =
          ((dbc + current_samples_in_packet - 1) / stream_info->ts_interval * stream_info->ts_interval) >= dbc;

        AVB1722_CIP_HeaderGen(Buf, dbc & 0xff);

        // perform required updates to header
        if (timestamp_valid) {
            ptp_ts = local_timestamp_to_ptp_mod32(frame->timestamp, timeInfo);
            ptp_ts = ptp_ts + stream_info->presentation_delay;
        }

        // Update timestamp value and valid flag.
        AVB1722_AVBTP_HeaderGen(Buf, timestamp_valid, ptp_ts, pkt_data_length, stream_info->sequence_number, stream_id0);

        stream_info->dbc_at_start_of_last_packet = dbc + current_samples_in_packet - 1;
        stream_info->sequence_number++;
        stream_info->current_samples_in_packet = 0;

        return (AVB_ETHERNET_HDR_SIZE + AVB_TP_HDR_SIZE + pkt_data_length);
    }

    stream_info->current_samples_in_packet = current_samples_in_packet;

    return 0;
}

#endif
