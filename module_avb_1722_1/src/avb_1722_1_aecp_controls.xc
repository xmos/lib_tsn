#include "avb_1722_1_aecp_controls.h"
#include "avb.h"
#include "avb_api.h"
#include "avb_1722_1_common.h"
#include "avb_1722_1_aecp.h"
#include "misc_timer.h"
#include "avb_srp_pdu.h"
#include <string.h>
#include <print.h>
#include "debug_print.h"
#include "xccompat.h"
#include "avb_1722_1.h"

#if AVB_1722_1_AEM_ENABLED
#include "aem_descriptor_types.h"
#endif

unsafe unsigned short process_aem_cmd_getset_control(avb_1722_1_aecp_packet_t *unsafe pkt,
                                                     unsigned char &status,
                                                     unsigned short command_type,
                                                     client interface avb_1722_1_control_callbacks i_1722_1_entity)
{
  avb_1722_1_aem_getset_control_t *cmd = (avb_1722_1_aem_getset_control_t *)(pkt->data.aem.command.payload);
  unsigned short control_index = ntoh_16(cmd->descriptor_id);
  unsigned short control_type = ntoh_16(cmd->descriptor_type);
  unsigned char *values = pkt->data.aem.command.payload + sizeof(avb_1722_1_aem_getset_control_t);
  unsigned short values_length = GET_1722_1_DATALENGTH(&(pkt->header)) - sizeof(avb_1722_1_aem_getset_control_t) - AVB_1722_1_AECP_COMMAND_DATA_OFFSET;

  if (control_type != AEM_CONTROL_TYPE)
  {
    status = AECP_AEM_STATUS_BAD_ARGUMENTS;
    return values_length;
  }

  if (command_type == AECP_AEM_CMD_GET_CONTROL)
  {
    status = i_1722_1_entity.get_control_value(control_index, values_length, values);
  }
  else // AECP_AEM_CMD_SET_CONTROL
  {
    status = i_1722_1_entity.set_control_value(control_index, values_length, values);
  }
  return values_length;
}

static int sfc_from_sampling_rate(int rate)
{
  switch (rate)
  {
    case 32000: return 0;
    case 44100: return 1;
    case 48000: return 2;
    case 88200: return 3;
    case 96000: return 4;
    case 176400: return 5;
    case 192000: return 6;
    default: return 0;
  }
}

unsafe void process_aem_cmd_getset_stream_info(avb_1722_1_aecp_packet_t *unsafe pkt,
                                          REFERENCE_PARAM(unsigned char, status),
                                          unsigned short command_type,
                                          CLIENT_INTERFACE(avb_interface, i_avb))
{
  avb_1722_1_aem_getset_stream_info_t *cmd = (avb_1722_1_aem_getset_stream_info_t *)(pkt->data.aem.command.payload);
  unsigned short stream_index = ntoh_16(cmd->descriptor_id);
  unsigned short desc_type = ntoh_16(cmd->descriptor_type);

  avb_srp_info_t *unsafe reservation;
  avb_stream_info_t *unsafe stream;
  avb_sink_info_t sink;
  avb_source_info_t source;

  if ((desc_type == AEM_STREAM_INPUT_TYPE) && (stream_index < AVB_NUM_SINKS))
  {
    sink = i_avb._get_sink_info(stream_index);
    reservation = &sink.reservation;
    stream = &sink.stream;
  }
  else if ((desc_type == AEM_STREAM_OUTPUT_TYPE) && (stream_index < AVB_NUM_SOURCES))
  {
    source = i_avb._get_source_info(stream_index);
    reservation = &source.reservation;
    stream = &source.stream;
  }
  else
  {
    status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
    return;
  }

  if (command_type == AECP_AEM_CMD_GET_STREAM_INFO)
  {

    cmd->stream_format[0] = 0x00;
    cmd->stream_format[1] = 0xa0;
    cmd->stream_format[2] = sfc_from_sampling_rate(stream->rate); // 10.3.2 in 61883-6
    cmd->stream_format[3] = stream->num_channels; // dbs
    cmd->stream_format[4] = 0x40; // b[0], nb[1], reserved[2:]
    cmd->stream_format[5] = 0; // label_iec_60958_cnt
    cmd->stream_format[6] = stream->num_channels; // label_mbla_cnt
    cmd->stream_format[7] = 0; // label_midi_cnt[0:3], label_smptecnt[4:]

    hton_32(&cmd->stream_id[0], reservation->stream_id[0]);
    hton_32(&cmd->stream_id[4], reservation->stream_id[1]);
    hton_32(cmd->msrp_accumulated_latency, reservation->accumulated_latency);
    memcpy(&cmd->msrp_failure_bridge_id, &reservation->failure_bridge_id, 8);
    cmd->msrp_failure_code = reservation->failure_code;

    memcpy(cmd->stream_dest_mac, reservation->dest_mac_addr, 6);
    hton_16(cmd->stream_vlan_id, reservation->vlan_id);

    int flags = AECP_STREAM_INFO_FLAGS_STREAM_VLAN_ID_VALID |
                AECP_STREAM_INFO_FLAGS_STREAM_DESC_MAC_VALID |
                AECP_STREAM_INFO_FLAGS_STREAM_ID_VALID |
                AECP_STREAM_INFO_FLAGS_STREAM_FORMAT_VALID |
                AECP_STREAM_INFO_FLAGS_MSRP_ACC_LAT_VALID |
                reservation->failure_bridge_id[1] ? AECP_STREAM_INFO_FLAGS_MSRP_FAILURE_VALID : 0;

    hton_32(cmd->flags, flags);

  }
  else
  {
    if (stream->state != AVB_SOURCE_STATE_DISABLED)
    {
      status = AECP_AEM_STATUS_STREAM_IS_RUNNING;
      return;
    }

    int flags = ntoh_32(cmd->flags);

    if (flags & AECP_STREAM_INFO_FLAGS_STREAM_VLAN_ID_VALID)
    {
      reservation->vlan_id = ntoh_16(cmd->stream_vlan_id);
    }

    if (desc_type == AEM_STREAM_INPUT_TYPE)
    {
      i_avb._set_sink_info(stream_index, sink);
    }
    else
    {
      i_avb._set_source_info(stream_index, source);
    }

  }
}

unsafe void process_aem_cmd_getset_sampling_rate(avb_1722_1_aecp_packet_t *unsafe pkt,
                                          unsigned char &status,
                                          unsigned short command_type,
                                          client interface avb_interface avb)
{
  avb_1722_1_aem_getset_sampling_rate_t *cmd = (avb_1722_1_aem_getset_sampling_rate_t *)(pkt->data.aem.command.payload);
  unsigned short media_clock_id = ntoh_16(cmd->descriptor_id);
  int rate;

  if (command_type == AECP_AEM_CMD_GET_SAMPLING_RATE)
  {
    if (avb.get_device_media_clock_rate(media_clock_id, rate))
    {
      hton_32(cmd->sampling_rate, rate);
      return;
    }
  }
  else // AECP_AEM_CMD_SET_SAMPLING_RATE
  {
    rate = ntoh_32(cmd->sampling_rate);

    if (avb.set_device_media_clock_rate(media_clock_id, rate))
    {
      debug_printf("SET SAMPLING RATE TO %d\n", rate);
      // Success
      return;
    }
  }

  status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
}

unsafe void process_aem_cmd_getset_clock_source(avb_1722_1_aecp_packet_t *unsafe pkt,
                                         unsigned char &status,
                                         unsigned short command_type,
                                         client interface avb_interface avb)
{
  avb_1722_1_aem_getset_clock_source_t *cmd = (avb_1722_1_aem_getset_clock_source_t *)(pkt->data.aem.command.payload);
  unsigned short media_clock_id = ntoh_16(cmd->descriptor_id);
  // The clock source descriptor's index corresponds to the clock type in our implementation
  enum device_media_clock_type_t source_index;

  if (command_type == AECP_AEM_CMD_GET_CLOCK_SOURCE)
  {
    if (avb.get_device_media_clock_type(media_clock_id, source_index))
    {
      hton_16(cmd->clock_source_index, source_index);
      return;
    }
  }
  else // AECP_AEM_CMD_SET_CLOCK_SOURCE
  {
    source_index = ntoh_16(cmd->clock_source_index);

    if (avb.set_device_media_clock_type(media_clock_id, source_index))
    {
      // Success
      return;
    }
  }

  status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
}

unsafe void process_aem_cmd_startstop_streaming(avb_1722_1_aecp_packet_t *unsafe pkt,
                                         unsigned char &status,
                                         unsigned short command_type,
                                         client interface avb_interface avb)
{
  avb_1722_1_aem_startstop_streaming_t *cmd = (avb_1722_1_aem_startstop_streaming_t *)(pkt->data.aem.command.payload);
  unsigned short stream_index = ntoh_16(cmd->descriptor_id);
  unsigned short desc_type = ntoh_16(cmd->descriptor_type);

  if (desc_type == AEM_STREAM_INPUT_TYPE)
  {
    enum avb_sink_state_t state;
    if (avb.get_sink_state(stream_index, state))
    {
      if (command_type == AECP_AEM_CMD_START_STREAMING)
      {
        avb.set_sink_state(stream_index, AVB_SINK_STATE_ENABLED);
      }
      else
      {
        if (state == AVB_SINK_STATE_ENABLED)
        {
          avb.set_sink_state(stream_index, AVB_SINK_STATE_POTENTIAL);
        }
      }
    }
    else status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;

  }
  else if ((desc_type == AEM_STREAM_OUTPUT_TYPE))
  {
    enum avb_source_state_t state;
    if (avb.get_source_state(stream_index, state))
    {
      if (command_type == AECP_AEM_CMD_START_STREAMING)
      {
        avb.set_source_state(stream_index, AVB_SOURCE_STATE_ENABLED);
      }
      else
      {
        if (state == AVB_SINK_STATE_ENABLED)
        {
          avb.set_source_state(stream_index, AVB_SOURCE_STATE_POTENTIAL);
        }
      }
    }
    else status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
  }
}

unsafe void process_aem_cmd_get_counters(avb_1722_1_aecp_packet_t *unsafe pkt,
                                         unsigned char &status,
                                         client interface avb_interface avb)
{
  avb_1722_1_aem_get_counters_t *cmd = (avb_1722_1_aem_get_counters_t *)(pkt->data.aem.command.payload);
  unsigned short clock_domain_id = ntoh_16(cmd->descriptor_id);
  unsigned short desc_type = ntoh_16(cmd->descriptor_type);

  if (desc_type == AEM_CLOCK_DOMAIN_TYPE)
  {
    if (clock_domain_id < AVB_NUM_MEDIA_CLOCKS) {
      media_clock_info_t info = avb._get_media_clock_info(clock_domain_id);
      const int counters_valid = AECP_GET_COUNTERS_CLOCK_DOMAIN_LOCKED_VALID |
                                 AECP_GET_COUNTERS_CLOCK_DOMAIN_UNLOCKED_VALID;
      hton_32(cmd->counters_valid, counters_valid);
      memset(&cmd->counters_block, 0, sizeof(cmd->counters_block));
      hton_32(&cmd->counters_block[AECP_GET_COUNTERS_CLOCK_DOMAIN_LOCKED_OFFSET], info.lock_counter);
      hton_32(&cmd->counters_block[AECP_GET_COUNTERS_CLOCK_DOMAIN_UNLOCKED_OFFSET], info.unlock_counter);
    }
    else status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
  }
  else status = AECP_AEM_STATUS_NOT_SUPPORTED;
}
