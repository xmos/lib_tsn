#include <debug_print.h>
#include "avb.h"
#include "avb_api.h"
#include "avb_mrp.h"
#include "avb_srp.h"
#include "avb_mvrp.h"
#include "ethernet.h"
#include "avb_1722_router.h"
#include "avb_srp_interface.h"

#define PERIODIC_POLL_TIME 5000

[[combinable]]
void avb_srp_task(client interface avb_interface i_avb,
                  server interface srp_interface i_srp,
                  client interface ethernet_if i_eth) {
  unsigned periodic_timeout;
  timer tmr;
  unsigned int buf[(MAX_AVB_CONTROL_PACKET_SIZE+3)>>2];
  unsigned char mac_addr[6];

  srp_store_ethernet_interface(i_eth);
  mrp_store_ethernet_interface(i_eth);

  i_eth.get_macaddr(0, mac_addr);
  mrp_init(mac_addr);
  srp_domain_init();
  avb_mvrp_init();

  // mac_initialize_routing_table(c_mac_tx);

  // TODO:configure client to receive correct packets
  //i_eth.set_receive_filter_mask(1 << MAC_FILTER_AVB_SRP);

  i_avb.initialise();

  tmr :> periodic_timeout;

  while (1) {
    select {
      case i_eth.packet_ready():
      {
        ethernet_packet_info_t packet_info;
        i_eth.get_packet(packet_info, (char *)buf, MAX_AVB_CONTROL_PACKET_SIZE);
        avb_process_srp_control_packet(i_avb, buf, packet_info.len, packet_info.type, i_eth, packet_info.src_ifnum);
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
