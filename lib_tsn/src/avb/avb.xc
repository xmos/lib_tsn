// Copyright (c) 2013-2017, XMOS Ltd, All rights reserved
#include "avb.h"
#include <xccompat.h>
#include "avb_srp.h"
#include "avb_mvrp.h"
#include "avb_mrp.h"
#include "gptp_config.h"
#include <string.h>
#include "debug_print.h"
#include <print.h>
#include "ethernet.h"
#include "avb_1722_maap.h"
#include "nettypes.h"
#include "avb_1722_router.h"
#include "avb_1722_1_acmp.h"

#if AVB_ENABLE_1722_1
#include "avb_1722_1.h"
#include "avb_1722_1_adp.h"
#endif

//#define AVB_TRANSMIT_BEFORE_RESERVATION 1

#define UNMAPPED (-1)
#define AVB_CHANNEL_UNMAPPED (-1)

typedef struct media_info_t {
  int tile_id;
  unsigned clk_ctl;
  unsigned fifo;
  int local_id;
  int mapped_to;
} media_info_t;

static int max_talker_stream_id = 0;
static int max_listener_stream_id = 0;
static avb_source_info_t sources[AVB_NUM_SOURCES];
static avb_sink_info_t sinks[AVB_NUM_SINKS];
static media_info_t inputs[AVB_NUM_MEDIA_INPUTS];
static media_info_t outputs[AVB_NUM_MEDIA_OUTPUTS];

static void register_talkers(chanend (&?c_talker_ctl)[], unsigned char mac_addr[6])
{
  unsafe {
    for (int i=0;i<AVB_NUM_TALKER_UNITS;i++) {
      int tile_id, num_streams;
      c_talker_ctl[i] :> tile_id;
      c_talker_ctl[i] :> num_streams;
      for (int k=0; k < 6; k++) {
        c_talker_ctl[i] <: mac_addr[k];
      }
      for (int j=0;j<num_streams;j++) {
        avb_source_info_t *unsafe source = &sources[max_talker_stream_id];
        source->stream.state = AVB_SOURCE_STATE_DISABLED;
        chanend *unsafe p_talker_ctl = &c_talker_ctl[i];
        source->talker_ctl = p_talker_ctl;
        source->stream.tile_id = tile_id;
        source->stream.local_id = j;
        source->stream.flags = 0;
        source->reservation.stream_id[0] = (mac_addr[0] << 24) | (mac_addr[1] << 16) | (mac_addr[2] <<  8) | (mac_addr[3] <<  0);
        source->reservation.stream_id[1] = (mac_addr[4] << 24) | (mac_addr[5] << 16) | ((source->stream.local_id & 0xffff)<<0);
        source->presentation = AVB_DEFAULT_PRESENTATION_TIME_DELAY_NS;
        source->reservation.vlan_id = 0;
        source->reservation.tspec = (AVB_SRP_TSPEC_PRIORITY_DEFAULT << 5 |
            AVB_SRP_TSPEC_RANK_DEFAULT << 4 |
            AVB_SRP_TSPEC_RESERVED_VALUE);
        source->reservation.tspec_max_interval = AVB_SRP_MAX_INTERVAL_FRAMES_DEFAULT;
        source->reservation.accumulated_latency = AVB_SRP_ACCUMULATED_LATENCY_DEFAULT;
        max_talker_stream_id++;
      }
    }
  }
}


static int max_link_id = 0;


static void register_listeners(chanend (&?c_listener_ctl)[])
{
  unsafe {
    for (int i=0;i<AVB_NUM_LISTENER_UNITS;i++) {
      int tile_id, num_streams;
      c_listener_ctl[i] :> tile_id;
      c_listener_ctl[i] :> num_streams;
      for (int j=0;j<num_streams;j++) {
        avb_sink_info_t *unsafe sink = &sinks[max_listener_stream_id];
        sink->stream.state = AVB_SINK_STATE_DISABLED;
        chanend *unsafe p_listener_ctl = &c_listener_ctl[i];
        sink->listener_ctl = p_listener_ctl;
        sink->stream.tile_id = tile_id;
        sink->stream.local_id = j;
        sink->stream.flags = 0;
        sink->reservation.vlan_id = 0;
        max_listener_stream_id++;
      }
      c_listener_ctl[i] <: max_link_id;
      max_link_id++;
    }
  }
}

static void register_media(chanend media_ctl[])
{
  unsafe {
    int input_id = 0;
    int output_id = 0;

    for (int i=0;i<AVB_NUM_MEDIA_UNITS;i++) {
      int tile_id;
      int num_in;
      int num_out;
      unsigned clk_ctl;
      media_ctl[i] :> tile_id;
      media_ctl[i] :> clk_ctl;
      media_ctl[i] :> num_in;

      for (int j=0;j<num_in;j++) {
        media_ctl[i] <: input_id;
        inputs[input_id].tile_id = tile_id;
        inputs[input_id].clk_ctl = clk_ctl;
        inputs[input_id].local_id = j;
        inputs[input_id].mapped_to = UNMAPPED;
        media_ctl[i] :> inputs[input_id].fifo;
        input_id++;

      }
      media_ctl[i] :> num_out;
      for (int j=0;j<num_out;j++) {
        media_ctl[i] <: output_id;
        outputs[output_id].tile_id = tile_id;
        outputs[output_id].clk_ctl = clk_ctl;
        outputs[output_id].local_id = j;
        outputs[output_id].mapped_to = UNMAPPED;
        media_ctl[i] :> outputs[output_id].fifo;
        output_id++;
      }
    }
  }
}

static void init_media_clock_server(client interface media_clock_if
                                    media_clock_ctl)
{
  if (!isnull(media_clock_ctl)) {
    for (int i=0;i<AVB_NUM_MEDIA_OUTPUTS;i++) {
      media_clock_ctl.set_buf_fifo(i, outputs[i].fifo);
    }
  }
}

void avb_init(chanend c_media_ctl[],
              chanend (&?c_listener_ctl)[],
              chanend (&?c_talker_ctl)[],
              client interface media_clock_if ?i_media_clock_ctl,
              client interface ethernet_cfg_if i_eth_cfg)
{
  unsigned char mac_addr[6];
  i_eth_cfg.get_macaddr(0, mac_addr);
  register_talkers(c_talker_ctl, mac_addr);
  register_listeners(c_listener_ctl);
}

static int valid_to_leave_vlan(int vlan)
{
  int all_streams_disabled = 1;
  for (int i=0; i < AVB_NUM_SINKS; i++) {
    if (sinks[i].stream.state != AVB_SINK_STATE_DISABLED) {
      all_streams_disabled = 0;
      break;
    }
  }

  for (int i=0; i < AVB_NUM_SOURCES; i++) {
    if (sources[i].stream.state != AVB_SINK_STATE_DISABLED) {
      all_streams_disabled = 0;
      break;
    }
  }

  return all_streams_disabled;
}

static void set_avb_sink_map(chanend c, avb_sink_info_t &sink, unsigned sink_num) {
  debug_printf("Listener sink #%d chan map:\n", sink_num);
  master {
    c <: AVB1722_ADJUST_LISTENER_STREAM;
    c <: (int)sink.stream.local_id;
    c <: AVB1722_ADJUST_LISTENER_CHANNEL_MAP;
    c <: (int)sink.stream.sync;
    for (int i=0;i<sink.stream.num_channels;i++) {
      if (sink.map[i] == AVB_CHANNEL_UNMAPPED) {
        debug_printf("  %d unmapped\n", i);
      }
      else {
        debug_printf("  %d -> %x\n", i, sink.map[i]);
      }
      c <: sink.map[i];
    }
  }
}

static void update_sink_state(unsigned sink_num,
                              enum avb_sink_state_t prev,
                              enum avb_sink_state_t state,
                              client interface ethernet_cfg_if i_eth_cfg,
                              client interface media_clock_if ?i_media_clock_ctl,
                              client interface srp_interface ?i_srp) {
  unsafe {
    avb_sink_info_t *sink = &sinks[sink_num];
    chanend *unsafe c = sink->listener_ctl;
    if (prev == AVB_SINK_STATE_DISABLED &&
        state == AVB_SINK_STATE_POTENTIAL) {

      unsigned clk_ctl = outputs[sink->map[0]].clk_ctl;
      debug_printf("Listener sink #%d chan map:\n", sink_num);
      master {
        *c <: AVB1722_CONFIGURE_LISTENER_STREAM;
        *c <: (int)sink->stream.local_id;
        *c <: (int)sink->stream.sync;
        *c <: sink->stream.rate;
        *c <: (int)sink->stream.num_channels;

        for (int i=0;i<sink->stream.num_channels;i++) {
          if (sink->map[i] == AVB_CHANNEL_UNMAPPED) {
            debug_printf("  %d unmapped\n", i);
          }
          else {
            debug_printf("  %d -> %d\n", i, sink->map[i]);
          }
          *c <: sink->map[i];
        }
      }

      if (!isnull(i_media_clock_ctl)) {
          i_media_clock_ctl.register_clock(clk_ctl, sink->stream.sync);
      }

      int router_link;

      master {
        *c <: AVB1722_GET_ROUTER_LINK;
        *c :> router_link;
      }

      ethernet_macaddr_filter_t stream_mutlicast_filter;
      stream_mutlicast_filter.appdata = sink->stream.local_id;
      memcpy(stream_mutlicast_filter.addr, sink->reservation.dest_mac_addr, 6);
      i_eth_cfg.add_macaddr_filter(0, 1, stream_mutlicast_filter);

      if (isnull(i_srp)) {
        debug_printf("MSRP: Register attach request %x:%x\n", sink->reservation.stream_id[0], sink->reservation.stream_id[1]);
        sink->reservation.vlan_id  = avb_srp_join_listener_attrs(sink->reservation.stream_id,  sink->reservation.vlan_id);
      }
      else {
        sink->reservation.vlan_id = i_srp.register_attach_request(sink->reservation.stream_id, sink->reservation.vlan_id);
      }

    }
    else if (prev != AVB_SINK_STATE_DISABLED &&
             state != AVB_SINK_STATE_DISABLED) {
      set_avb_sink_map(*c, *sink, sink_num);
    }
    else if (prev != AVB_SINK_STATE_DISABLED &&
            state == AVB_SINK_STATE_DISABLED) {

      master {
        *c <: AVB1722_DISABLE_LISTENER_STREAM;
        *c <: (int)sink->stream.local_id;
      }

      ethernet_macaddr_filter_t stream_mutlicast_filter;
      stream_mutlicast_filter.appdata = sink->stream.local_id;
      memcpy(stream_mutlicast_filter.addr, sink->reservation.dest_mac_addr, 6);
      i_eth_cfg.del_macaddr_filter(0, 1, stream_mutlicast_filter);

      if (isnull(i_srp)) {
        debug_printf("MSRP: Deregister attach request %x:%x\n", sink->reservation.stream_id[0], sink->reservation.stream_id[1]);
        avb_srp_leave_listener_attrs(sink->reservation.stream_id);
      }
      else {
        i_srp.deregister_attach_request(sink->reservation.stream_id);
      }

#if MRP_NUM_PORTS == 1
      int vid = sink->reservation.vlan_id;
      if (vid && valid_to_leave_vlan(vid)) {
        avb_leave_vlan(vid);
      }
#endif
    }
  }
}

static void configure_talker_stream(chanend c, avb_source_info_t *alias source, unsigned source_num) {
  unsigned fifo_mask = 0;

  for (int i=0;i<source->stream.num_channels;i++) {
    inputs[source->map[i]].mapped_to = source_num;
    fifo_mask |= (1 << source->map[i]);
  }

  master {
    c <: AVB1722_CONFIGURE_TALKER_STREAM;
    c <: (int)source->stream.local_id;
    c <: (int)source->stream.format;

    for (int i=0; i < 6;i++) {
      c <: (int)source->reservation.dest_mac_addr[i];
    }

    c <: source_num;
    c <: (int)source->stream.num_channels;
    c <: fifo_mask;

    for (int i=0;i<source->stream.num_channels;i++) {
      c <: source->map[i];
    }
    c <: (int)source->stream.rate;

    if (source->presentation)
      c <: source->presentation;
    else
      c <: AVB_DEFAULT_PRESENTATION_TIME_DELAY_NS;
  }
}

static unsigned avb_srp_calculate_max_framesize(avb_source_info_t *source_info)
{
#if defined(AVB_1722_FORMAT_61883_6) || defined(AVB_1722_FORMAT_SAF)
  const unsigned samples_per_packet = (AVB_MAX_AUDIO_SAMPLE_RATE + (AVB1722_PACKET_RATE-1))/AVB1722_PACKET_RATE;
  return AVB1722_PLUS_SIP_HEADER_SIZE + (source_info->stream.num_channels * samples_per_packet * 4);
#endif
#if defined(AVB_1722_FORMAT_61883_4)
  return AVB1722_PLUS_SIP_HEADER_SIZE + (192 * MAX_TS_PACKETS_PER_1722);
#endif
}

static void update_source_state(unsigned source_num,
                                enum avb_source_state_t prev,
                                enum avb_source_state_t state,
                                client interface ethernet_cfg_if i_eth,
                                client interface media_clock_if ?i_media_clock_ctl,
                                client interface srp_interface ?i_srp) {
  unsafe {
    char stream_string[] = "Talker stream";
    avb_source_info_t *source = &sources[source_num];
    chanend *unsafe c = source->talker_ctl;
    if (prev == AVB_SOURCE_STATE_DISABLED &&
        state == AVB_SOURCE_STATE_POTENTIAL) {
      // enable the source
      int valid = 1;
      unsigned clk_ctl = inputs[source->map[0]].clk_ctl;

      if (source->stream.num_channels <= 0) {
        valid = 0;
      }

      if (source->reservation.vlan_id < 0) {
        valid = 0;
      }

      // check that the map is ok
      for (int i=0;i<source->stream.num_channels;i++) {
        if (inputs[source->map[i]].mapped_to != UNMAPPED) {
          valid = 0;
        }
        if (inputs[source->map[i]].clk_ctl != clk_ctl) {
          valid = 0;
        }
      }


      if (valid) {
        configure_talker_stream(*c, source, source_num);

        source->reservation.tspec_max_frame_size = avb_srp_calculate_max_framesize(source);
        if (isnull(i_srp)) {
          debug_printf("MSRP: Register stream request %x:%x\n", source->reservation.stream_id[0], source->reservation.stream_id[1]);
          source->reservation.vlan_id = avb_srp_create_and_join_talker_advertise_attrs(&source->reservation);
        }
        else {
          source->reservation.vlan_id = i_srp.register_stream_request(source->reservation);
        }

        master {
          *c <: AVB1722_SET_VLAN;
          *c <: (int)source->stream.local_id;
          *c <: (int)source->reservation.vlan_id;
        }

        if (!isnull(i_media_clock_ctl)) {
          i_media_clock_ctl.register_clock(clk_ctl, source->stream.sync);
        }

    #if defined(AVB_TRANSMIT_BEFORE_RESERVATION)
        master {
          *c <: AVB1722_TALKER_GO;
          *c <: (int)source->stream.local_id;

          debug_printf("%s #%d on\n", stream_string, source_num);
        }
    #else
        debug_printf("%s #%d ready\n", stream_string, source_num);
    #endif

      }
    }
    else if (prev == AVB_SOURCE_STATE_ENABLED &&
        state == AVB_SOURCE_STATE_POTENTIAL) {
      // stop transmission

        master {
          *c <: AVB1722_TALKER_STOP;
          *c <: (int)source->stream.local_id;
        }

        debug_printf("%s #%d off\n", stream_string, source_num);
    }
    else if (prev == AVB_SOURCE_STATE_POTENTIAL &&
             state == AVB_SOURCE_STATE_ENABLED) {
      // start transmitting
      configure_talker_stream(*c, source, source_num);

      debug_printf("%s #%d on\n", stream_string, source_num);

      master {
        *c <: AVB1722_TALKER_GO;
        *c <: (int)source->stream.local_id;
      }
    }
    else if (prev != AVB_SOURCE_STATE_DISABLED &&
             state == AVB_SOURCE_STATE_DISABLED) {
      // disabled the source
        for (int i=0;i<source->stream.num_channels;i++) {
          inputs[source->map[i]].mapped_to = UNMAPPED;
        }

        master {
          *c <: AVB1722_TALKER_STOP;
          *c <: (int)source->stream.local_id;
        }

        debug_printf("%s #%d off (disabled)\n", stream_string, source_num);

#if MRP_NUM_PORTS == 1
      int vid = source->reservation.vlan_id;
      if (vid && valid_to_leave_vlan(vid)) {
        avb_leave_vlan(vid);
      }
#endif

      if (isnull(i_srp)) {
        debug_printf("MSRP: Deregister stream request %x:%x\n", source->reservation.stream_id[0], source->reservation.stream_id[1]);
        avb_srp_leave_talker_attrs(source->reservation.stream_id);
      }
      else {
        i_srp.deregister_stream_request(source->reservation.stream_id);
      }

    }
  }
}

// Wrappers for interface calls from C
int avb_get_source_state(client interface avb_interface avb, unsigned source_num, enum avb_source_state_t &state) {
  return avb.get_source_state(source_num, state);
}

int avb_set_source_state(client interface avb_interface avb, unsigned source_num, enum avb_source_state_t state) {
  return avb.set_source_state(source_num, state);
}

int avb_get_source_vlan(client interface avb_interface avb, unsigned source_num, int &vlan) {
  return avb.get_source_vlan(source_num, vlan);
}

int avb_set_source_vlan(client interface avb_interface avb, unsigned source_num, int vlan) {
  return avb.set_source_vlan(source_num, vlan);
}

int avb_get_sink_vlan(client interface avb_interface avb, unsigned sink_num, int &vlan) {
  return avb.get_sink_vlan(sink_num, vlan);
}

int avb_set_sink_vlan(client interface avb_interface avb, unsigned sink_num, int vlan) {
  return avb.set_sink_vlan(sink_num, vlan);
}

// Set the period inbetween periodic processing to 50us based
// on the Xcore 100Mhz timer.
#define PERIODIC_POLL_TIME 5000

[[combinable]]
void avb_manager(server interface avb_interface avb[num_avb_clients], unsigned num_avb_clients,
                 client interface srp_interface ?i_srp,
                 chanend c_media_ctl[],
                 chanend (&?c_listener_ctl)[],
                 chanend (&?c_talker_ctl)[],
                 client interface ethernet_cfg_if i_eth_cfg,
                 client interface media_clock_if ?i_media_clock_ctl) {

  register_media(c_media_ctl);
  init_media_clock_server(i_media_clock_ctl);

  unsafe {
    avb_init(c_media_ctl, c_listener_ctl, c_talker_ctl, i_media_clock_ctl, i_eth_cfg);
  }

  while (1) {
    select {
    case avb[int i]._get_source_info(unsigned source_num) -> avb_source_info_t info:
      info = sources[source_num];
      break;
    case avb[int i]._set_source_info(unsigned source_num, avb_source_info_t info):
      enum avb_source_state_t prev_state = sources[source_num].stream.state;
      sources[source_num] = info;
      unsafe {
        update_source_state(source_num, prev_state, info.stream.state, i_eth_cfg,
                            i_media_clock_ctl, i_srp);
      }
      break;
    case avb[int i]._get_sink_info(unsigned sink_num) -> avb_sink_info_t info:
      info = sinks[sink_num];
      break;
    case avb[int i]._set_sink_info(unsigned sink_num, avb_sink_info_t info):
      enum avb_sink_state_t prev_state = sinks[sink_num].stream.state;
      sinks[sink_num] = info;
      unsafe {
        update_sink_state(sink_num, prev_state, info.stream.state, i_eth_cfg,
                          i_media_clock_ctl, i_srp);
      }
      break;
    case avb[int i]._get_media_clock_info(unsigned clock_num)
      -> media_clock_info_t info:
      info = i_media_clock_ctl.get_clock_info(clock_num);
      break;
    case avb[int i]._set_media_clock_info(unsigned clock_num,
                                          media_clock_info_t info):
      media_clock_info_t old_info = i_media_clock_ctl.get_clock_info(clock_num);
      if (old_info.rate != info.rate) {
        c_media_ctl[0] <: DEVICE_MEDIA_CLOCK_SET_SAMPLING_RATE;
        c_media_ctl[0] <: info.rate;
      }
      i_media_clock_ctl.set_clock_info(clock_num, info);
      break;
    }
  }
}

int set_avb_source_port(unsigned source_num,
                        int srcport) {
  unsafe {
  if (source_num < AVB_NUM_SOURCES) {
    avb_source_info_t *source = &sources[source_num];
    chanend *unsafe c = source->talker_ctl;
    master {
      *c <: AVB1722_SET_PORT;
      *c <: (int)source->stream.local_id;
      *c <: srcport;
    }

    return 1;
  }
  else
    return 0;
  }
}

#ifdef MEDIA_OUTPUT_FIFO_VOLUME_CONTROL
void set_avb_source_volumes(unsigned sink_num, int volumes[], int count)
{
	if (sink_num < AVB_NUM_SINKS) {
    unsafe {
      avb_sink_info_t *sink = &sinks[sink_num];
      chanend *unsafe c = sink->listener_ctl;
      *c <: AVB1722_ADJUST_LISTENER_STREAM;
      *c <: sink->stream.local_id;
      *c <: AVB1722_ADJUST_LISTENER_VOLUME;
      *c <: count;
      for (int i=0;i<count;i++) {
        *c <:  volumes[i];
      }
    }
	}
}
#endif


void avb_process_1722_control_packet(unsigned int buf0[],
                                     unsigned nbytes,
                                     eth_packet_type_t packet_type,
                                     client interface ethernet_tx_if i_eth,
                                     client interface avb_interface i_avb,
                                     client interface avb_1722_1_control_callbacks i_1722_1_entity) {

  if (packet_type == ETH_IF_STATUS) {
    if (((unsigned char *)buf0)[0] == ETHERNET_LINK_UP) {
      if (NUM_ETHERNET_PORTS == 1) {
        unsigned char base_addr[6];
        if (!avb_1722_maap_get_base_address(base_addr)) {
          avb_1722_maap_request_addresses(AVB_NUM_SOURCES, base_addr);
        }
        else {
          avb_1722_maap_request_addresses(AVB_NUM_SOURCES, null);
        }

#if AVB_1722_1_FAST_CONNECT_ENABLED
        acmp_start_fast_connect(i_eth);
#endif
      }
    }
  }
  else if (packet_type == ETH_DATA) {
    struct ethernet_hdr_t *ethernet_hdr = (ethernet_hdr_t *) &buf0[0];

    int etype, eth_hdr_size;
    int has_qtag = ethernet_hdr->ethertype.data[1]==0x18;
    eth_hdr_size = has_qtag ? 18 : 14;

    if (has_qtag) {
      struct tagged_ethernet_hdr_t *tagged_ethernet_hdr = (tagged_ethernet_hdr_t *) &buf0[0];
      etype = (int)(tagged_ethernet_hdr->ethertype.data[0] << 8) + (int)(tagged_ethernet_hdr->ethertype.data[1]);
    }
    else {
      etype = (int)(ethernet_hdr->ethertype.data[0] << 8) + (int)(ethernet_hdr->ethertype.data[1]);
    }
    int len = nbytes - eth_hdr_size;

    unsigned char *buf = (unsigned char *) buf0;

    switch (etype) {
      case AVB_1722_ETHERTYPE:
#if AVB_ENABLE_1722_1
        avb_1722_1_process_packet(&buf[eth_hdr_size], len, ethernet_hdr->src_addr, i_eth, i_avb, i_1722_1_entity);
#endif
#if AVB_ENABLE_1722_MAAP
        avb_1722_maap_process_packet(&buf[eth_hdr_size], len, ethernet_hdr->src_addr, i_eth);
#endif
        break;
    }
  }
}

int get_avb_ptp_gm(unsigned char a0[])
{
  // ptp_get_current_grandmaster(*c_ptp, a0);
  return 1;
}

int get_avb_ptp_port_pdelay(int srcport, unsigned *pdelay)
{
  if (srcport == 0)
  {
    // ptp_get_propagation_delay(*c_ptp, pdelay);
    return 1;
  }
  else
  {
    return 0;
  }
}

unsigned avb_get_source_stream_index_from_stream_id(unsigned int stream_id[2])
{
  for (unsigned i=0; i<AVB_NUM_SOURCES; ++i) {
    if (stream_id[0] == sources[i].reservation.stream_id[0] &&
        stream_id[1] == sources[i].reservation.stream_id[1]) {
      return i;
    }
  }
  return -1u;
}

unsigned avb_get_sink_stream_index_from_stream_id(unsigned int stream_id[2])
{
  for (unsigned i=0; i<AVB_NUM_SINKS; ++i) {
    if (stream_id[0] == sinks[i].reservation.stream_id[0] &&
        stream_id[1] == sinks[i].reservation.stream_id[1]) {
      return i;
    }
  }
  return -1u;
}

unsigned avb_get_source_stream_index_from_pointer(avb_source_info_t *unsafe p)
{
	for (unsigned i=0; i<AVB_NUM_SOURCES; ++i) {
		if (p == &sources[i]) return i;
	}
	return -1u;
}

unsigned avb_get_sink_stream_index_from_pointer(avb_sink_info_t *unsafe p)
{
	for (unsigned i=0; i<AVB_NUM_SINKS; ++i) {
		if (p == &sinks[i]) return i;
	}
	return -1u;
}

int avb_register_listener_streams(chanend listener_ctl,
                                   int num_streams)
{
  int tile_id;
  int link_id;
  tile_id = get_local_tile_id();
  listener_ctl <: tile_id;
  listener_ctl <: num_streams;
  listener_ctl :> link_id;
  return link_id;
}

void avb_register_talker_streams(chanend talker_ctl,
                                 int num_streams,
                                 unsigned char mac_addr[6])
{
  int tile_id;
  tile_id = get_local_tile_id();
  talker_ctl <: tile_id;
  talker_ctl <: num_streams;
  for (int i=0; i < 6; i++) {
    talker_ctl :> mac_addr[i];
  }
}
