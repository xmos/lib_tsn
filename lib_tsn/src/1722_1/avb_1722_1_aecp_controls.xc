// Copyright (c) 2015, XMOS Ltd, All rights reserved
#include "avb_1722_1_aecp_controls.h"
#include "avb.h"
#include "avb_api.h"
#include "avb_1722_1_common.h"
#include "avb_1722_1_aecp.h"
#include "misc_timer.h"
#include "avb_srp_pdu.h"
#include <string.h>
#include "xassert.h"
#include "debug_print.h"
#include "xccompat.h"
#include "avb_1722_1.h"
#include "aem_descriptor_types.h"
#include "aem_descriptor_structs.h"

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

static int sampling_rate_from_sfc(int sfc)
{
  switch (sfc)
  {
    case 0: return 32000;
    case 1: return 44100;
    case 2: return 48000;
    case 3: return 88200;
    case 4: return 96000;
    case 5: return 176400;
    case 6: return 192000;
    default: return 0;
  }
}

static unsafe void set_stream_format_field(avb_stream_info_t *unsafe stream_info, unsigned char stream_format[8])
{
  stream_format[0] = 0x00;
  stream_format[1] = 0xa0;
  stream_format[2] = sfc_from_sampling_rate(stream_info->rate); // 10.3.2 in 61883-6
  stream_format[3] = stream_info->num_channels; // dbs
  stream_format[4] = 0x40; // b[0], nb[1], reserved[2:]
  stream_format[5] = 0; // label_iec_60958_cnt
  stream_format[6] = stream_info->num_channels; // label_mbla_cnt
  stream_format[7] = 0; // label_midi_cnt[0:3], label_smptecnt[4:]
}

unsafe void set_current_fields_in_descriptor(unsigned char *unsafe descriptor,
                                      unsigned int desc_size_bytes,
                                      unsigned int read_type, unsigned int read_id,
                                      CLIENT_INTERFACE(avb_interface, i_avb_api),
                                      CLIENT_INTERFACE(avb_1722_1_control_callbacks, i_1722_1_entity))
{
  switch (read_type) {
    case AEM_AUDIO_UNIT_TYPE:
    case AEM_CLOCK_DOMAIN_TYPE:
    {
      media_clock_info_t clock_info = i_avb_api._get_media_clock_info(0);
      if (read_type == AEM_AUDIO_UNIT_TYPE) {
        aem_desc_audio_unit_t *unsafe audio_unit = (aem_desc_audio_unit_t *)descriptor;
        hton_32(audio_unit->current_sampling_rate, clock_info.rate);
      }
      else {
        aem_desc_clock_domain_t *clock_domain = (aem_desc_clock_domain_t *)descriptor;
        hton_16(clock_domain->clock_source_index, clock_info.clock_type);
      }
      break;
    }
    case AEM_STREAM_INPUT_TYPE:
    case AEM_STREAM_OUTPUT_TYPE:
    {
      avb_stream_info_t *unsafe stream;
      aem_desc_stream_input_output_t *unsafe stream_inout = (aem_desc_stream_input_output_t *)descriptor;
      if (read_type == AEM_STREAM_INPUT_TYPE)
      {
        avb_sink_info_t sink = i_avb_api._get_sink_info(read_id);
        stream = &sink.stream;
      }
      else
      {
        avb_source_info_t source = i_avb_api._get_source_info(read_id);
        stream = &source.stream;
      }
      set_stream_format_field(stream, stream_inout->current_format);
      break;
    }
    case AEM_CONTROL_TYPE:
      aem_desc_control_t *unsafe control = (aem_desc_control_t *)descriptor;
      unsigned int value_size;
      unsigned short values_length;
      unsigned char values[12]; // Max value length * number of values
      i_1722_1_entity.get_control_value(read_id, value_size, values_length, values);
      if (value_size != values_length) {
        fail("value_size must equal values_length");
      }
      if (ntoh_16(control->control_value_type) <= AEM_CONTROL_LINEAR_DOUBLE) {
        // Calculate the correct current value offset in the descriptor for linear control types
        memcpy(descriptor + sizeof(aem_desc_control_t) + (4*value_size), values, value_size);
      }
      else {
        fail("Unsupported control value type");
      }
      break;
    case AEM_SIGNAL_SELECTOR_TYPE:
      aem_desc_signal_selector_t *unsafe signal_selector = (aem_desc_signal_selector_t *)descriptor;
      unsigned short signal_type;
      unsigned short signal_index;
      unsigned short signal_output;
      i_1722_1_entity.get_signal_selector(read_id, signal_type, signal_index, signal_output);

      hton_16(signal_selector->current_signal_type, signal_type);
      hton_16(signal_selector->current_signal_index, signal_index);
      hton_16(signal_selector->current_signal_output, signal_output);
      break;
    default:
      break;
  }
}

unsafe void process_aem_cmd_getset_signal_selector(avb_1722_1_aecp_packet_t *unsafe pkt,
                                                   unsigned char &status,
                                                   unsigned short command_type,
                                                   client interface avb_1722_1_control_callbacks i_1722_1_entity)
{
  avb_1722_1_aem_getset_signal_selector_t *cmd = (avb_1722_1_aem_getset_signal_selector_t *)(pkt->data.aem.command.payload);
  unsigned short selector_index = ntoh_16(cmd->descriptor_id);
  unsigned short selector_type = ntoh_16(cmd->descriptor_type);
  unsigned short signal_type = ntoh_16(cmd->signal_type);
  unsigned short signal_index = ntoh_16(cmd->signal_index);
  unsigned short signal_output = ntoh_16(cmd->signal_output);

  if (selector_type != AEM_SIGNAL_SELECTOR_TYPE)
  {
    status = AECP_AEM_STATUS_BAD_ARGUMENTS;
    return;
  }

  if (command_type == AECP_AEM_CMD_GET_SIGNAL_SELECTOR)
  {
    status = i_1722_1_entity.get_signal_selector(selector_index, signal_type, signal_index, signal_output);
  }
  else // AECP_AEM_CMD_SET_SIGNAL_SELECTOR
  {
    status = i_1722_1_entity.set_signal_selector(selector_index, signal_type, signal_index, signal_output);
  }
  return;
}

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
  unsigned int value_size;

  if (control_type != AEM_CONTROL_TYPE)
  {
    status = AECP_AEM_STATUS_BAD_ARGUMENTS;
    return values_length;
  }

  if (command_type == AECP_AEM_CMD_GET_CONTROL)
  {
    status = i_1722_1_entity.get_control_value(control_index, value_size, values_length, values);
  }
  else // AECP_AEM_CMD_SET_CONTROL
  {
    status = i_1722_1_entity.set_control_value(control_index, values_length, values);
  }
  return values_length;
}

unsafe void process_aem_cmd_getset_stream_format(avb_1722_1_aecp_packet_t *unsafe pkt,
                                          REFERENCE_PARAM(unsigned char, status),
                                          unsigned short command_type,
                                          CLIENT_INTERFACE(avb_interface, i_avb))
{
  avb_1722_1_aem_getset_stream_format_t *cmd = (avb_1722_1_aem_getset_stream_format_t *)(pkt->data.aem.command.payload);
  unsigned short stream_index = ntoh_16(cmd->descriptor_id);
  unsigned short desc_type = ntoh_16(cmd->descriptor_type);
  enum avb_stream_format_t format;
  int rate;
  int channels;
  avb_sink_info_t sink;
  avb_source_info_t source;
  avb_stream_info_t *unsafe stream;

  if ((desc_type == AEM_STREAM_INPUT_TYPE) && (stream_index < AVB_NUM_SINKS))
  {
    sink = i_avb._get_sink_info(stream_index);
    stream = &sink.stream;
  }
  else if ((desc_type == AEM_STREAM_OUTPUT_TYPE) && (stream_index < AVB_NUM_SOURCES))
  {
    source = i_avb._get_source_info(stream_index);
    stream = &source.stream;
  }
  else
  {
    status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
    return;
  }

  if (command_type == AECP_AEM_CMD_GET_STREAM_FORMAT)
  {
    set_stream_format_field(stream, cmd->stream_format);
  }
  else // AECP_AEM_CMD_SET_STREAM_FORMAT
  {
    format = AVB_SOURCE_FORMAT_MBLA_24BIT;
    rate = sampling_rate_from_sfc(cmd->stream_format[2]);
    channels = cmd->stream_format[6];

    if (stream->state == AVB_SOURCE_STATE_ENABLED)
    {
      status = AECP_AEM_STATUS_STREAM_IS_RUNNING;
      return;
    }

    stream->num_channels = channels;
    stream->rate = rate;
    stream->format = format;

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
    set_stream_format_field(stream, cmd->stream_format);

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
    }
    else {
      status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
    }
  }
  else // AECP_AEM_CMD_SET_SAMPLING_RATE
  {
    rate = ntoh_32(cmd->sampling_rate);
    avb.set_device_media_clock_state(media_clock_id, DEVICE_MEDIA_CLOCK_STATE_DISABLED);
    if (avb.set_device_media_clock_rate(media_clock_id, rate))
    {
      avb.set_device_media_clock_state(media_clock_id, DEVICE_MEDIA_CLOCK_STATE_ENABLED);
      debug_printf("SET SAMPLING RATE TO %d\n", rate);
      // Success
    }
    else {
      status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
    }
  }
  return;
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
    }
    else {
      status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
    }
  }
  else // AECP_AEM_CMD_SET_CLOCK_SOURCE
  {
    source_index = ntoh_16(cmd->clock_source_index);

    avb.set_device_media_clock_state(media_clock_id, DEVICE_MEDIA_CLOCK_STATE_DISABLED);
    if (avb.set_device_media_clock_type(media_clock_id, source_index))
    {
      avb.set_device_media_clock_state(media_clock_id, DEVICE_MEDIA_CLOCK_STATE_ENABLED);
      // Success
    }
    else {
      status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
    }
  }

  return;
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
        avb.set_sink_state(stream_index, AVB_SINK_STATE_POTENTIAL);
        avb.set_sink_state(stream_index, AVB_SINK_STATE_ENABLED);
      }
      else
      {
        if (state == AVB_SINK_STATE_ENABLED)
        {
          avb.set_sink_state(stream_index, AVB_SINK_STATE_POTENTIAL);
        }
        avb.set_sink_state(stream_index, AVB_SINK_STATE_DISABLED);
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
