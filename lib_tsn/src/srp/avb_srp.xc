// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#include <debug_print.h>
#include "avb.h"
#include "avb_internal.h"
#include "avb_mrp.h"
#include "avb_srp.h"
#include "avb_mvrp.h"
#include "ethernet.h"
#include "avb_1722_router.h"
#include "nettypes.h"

// avb_mrp.c:
extern unsigned char srp_dest_mac[6];
extern unsigned char mvrp_dest_mac[6];

void avb_process_srp_control_packet(client interface avb_interface avb, unsigned int buf0[], unsigned nbytes, eth_packet_type_t packet_type, client interface ethernet_tx_if i_eth, unsigned int port_num)
{
  if (packet_type == ETH_IF_STATUS) {
    if (((unsigned char *)buf0)[0] == ETHERNET_LINK_UP) {
      srp_domain_join();
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

    if (etype != AVB_SRP_ETHERTYPE && etype != AVB_MVRP_ETHERTYPE) {
      return;
    }

    if (etype == AVB_SRP_ETHERTYPE) {
      for (int i=0; i < 6; i++) {
        if (ethernet_hdr->dest_addr[i] != srp_dest_mac[i]) {
          return;
        }
      }
    }

    if (etype == AVB_MVRP_ETHERTYPE) {
      for (int i=0; i < 6; i++) {
        if (ethernet_hdr->dest_addr[i] != mvrp_dest_mac[i]) {
          return;
        }
      }
    }

    avb_mrp_process_packet(&buf[eth_hdr_size], etype, len, port_num);
  }

}

#define PERIODIC_POLL_TIME 5000

[[combinable]]
void avb_srp_task(client interface avb_interface i_avb,
                  server interface srp_interface i_srp,
                  client interface ethernet_rx_if i_eth_rx,
                  client interface ethernet_tx_if i_eth_tx,
                  client interface ethernet_cfg_if i_eth_cfg) {
  unsigned periodic_timeout;
  timer tmr;
  unsigned int buf[(MAX_AVB_CONTROL_PACKET_SIZE+3)>>2];
  unsigned char mac_addr[6];

  srp_store_ethernet_interface(i_eth_tx);
  mrp_store_ethernet_interface(i_eth_tx);

  i_eth_cfg.get_macaddr(0, mac_addr);
  mrp_init(mac_addr);
  srp_domain_init();
  avb_mvrp_init();

  size_t eth_index = i_eth_rx.get_index();
  ethernet_macaddr_filter_t msrp_mvrp_filter;
  msrp_mvrp_filter.appdata = 0;
  memcpy(msrp_mvrp_filter.addr, srp_dest_mac, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, msrp_mvrp_filter);
  memcpy(msrp_mvrp_filter.addr, mvrp_dest_mac, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, msrp_mvrp_filter);
  i_eth_cfg.add_ethertype_filter(eth_index, AVB_SRP_ETHERTYPE);
  i_eth_cfg.add_ethertype_filter(eth_index, AVB_MVRP_ETHERTYPE);

  tmr :> periodic_timeout;

  while (1) {
    select {
      case i_eth_rx.packet_ready():
      {
        ethernet_packet_info_t packet_info;
        i_eth_rx.get_packet(packet_info, (char *)buf, MAX_AVB_CONTROL_PACKET_SIZE);
        avb_process_srp_control_packet(i_avb, buf, packet_info.len, packet_info.type, i_eth_tx, packet_info.src_ifnum);
        break;
      }
      // Periodic processing
      case tmr when timerafter(periodic_timeout) :> unsigned int time_now:
      {
        mrp_periodic(i_avb);

        periodic_timeout += PERIODIC_POLL_TIME;
        break;
      }
      case i_srp.register_stream_request(avb_srp_info_t stream_info) -> short vid_joined:
      {
        avb_srp_info_t local_stream_info = stream_info;
        debug_printf("MSRP: Register stream request %x:%x\n", stream_info.stream_id[0], stream_info.stream_id[1]);
        vid_joined = avb_srp_create_and_join_talker_advertise_attrs(&local_stream_info);
        break;
      }
      case i_srp.deregister_stream_request(unsigned stream_id[2]):
      {
        unsigned int local_stream_id[2];
        local_stream_id[0] = stream_id[0];
        local_stream_id[1] = stream_id[1];
        debug_printf("MSRP: Deregister stream request %x:%x\n", local_stream_id[0], local_stream_id[1]);
        avb_srp_leave_talker_attrs(local_stream_id);
        break;
      }
      case i_srp.register_attach_request(unsigned stream_id[2], short vlan_id) -> short vid_joined:
      {
        unsigned int local_stream_id[2];
        local_stream_id[0] = stream_id[0];
        local_stream_id[1] = stream_id[1];
        debug_printf("MSRP: Register attach request %x:%x\n", local_stream_id[0], local_stream_id[1]);
        vid_joined = avb_srp_join_listener_attrs(local_stream_id, vlan_id);
        break;
      }
      case i_srp.deregister_attach_request(unsigned stream_id[2]):
      {
        unsigned int local_stream_id[2];
        local_stream_id[0] = stream_id[0];
        local_stream_id[1] = stream_id[1];
        debug_printf("MSRP: Deregister attach request %x:%x\n", local_stream_id[0], local_stream_id[1]);
        avb_srp_leave_listener_attrs(local_stream_id);
        break;
      }
    }
  }
}
