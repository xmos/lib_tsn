// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#include <print.h>
#include <string.h>
#include "xassert.h"
#include "avb.h"
#include "avb_internal.h"
#include "avb_1722_common.h"
#include "avb_1722_1.h"
#include "avb_1722_1_common.h"
#include "avb_1722_1_adp.h"
#include "avb_1722_1_acmp.h"
#include "avb_1722_1_aecp.h"
#include "avb_1722_maap.h"
#include "ethernet.h"
#include "avb_1722_1_protocol.h"
#include "avb_mrp.h"
#include "avb_srp.h"
#include "avb_mvrp.h"
#include "otp_board_info.h"

#define PERIODIC_POLL_TIME 5000

unsigned char my_mac_addr[6];
extern unsigned char maap_dest_addr[6];
extern unsigned char avb_1722_1_adp_dest_addr[6];

// Buffer for constructing 1722.1 transmit packets
unsigned int avb_1722_1_buf[AVB_1722_1_PACKET_SIZE_WORDS];

// The GUID of this device
guid_t my_guid;

void avb_1722_1_init(unsigned char macaddr[6], unsigned serial_num)
{
    memcpy(my_mac_addr, macaddr, 6);

    my_guid.c[0] = macaddr[5];
    my_guid.c[1] =  macaddr[4];
    my_guid.c[2] = macaddr[3];
    my_guid.c[3] = 0xfe;
    my_guid.c[4] = 0xff;
    my_guid.c[5] = macaddr[2];
    my_guid.c[6] = macaddr[1];
    my_guid.c[7] = macaddr[0];

    avb_1722_1_adp_init();
#if (AVB_1722_1_AEM_ENABLED)
    avb_1722_1_aecp_aem_init(serial_num);
#endif

#if (AVB_1722_1_CONTROLLER_ENABLED)
    avb_1722_1_acmp_controller_init();
#endif
#if (AVB_1722_1_TALKER_ENABLED)
    // Talker state machine is initialised once MAAP has finished
#endif
#if (AVB_1722_1_LISTENER_ENABLED)
    avb_1722_1_acmp_listener_init();
#endif

}

void avb_1722_1_process_packet(unsigned char buf[len], unsigned len,
                                unsigned char src_addr[6],
                                client interface ethernet_tx_if i_eth,
                                CLIENT_INTERFACE(avb_interface, i_avb_api),
                                CLIENT_INTERFACE(avb_1722_1_control_callbacks, i_1722_1_entity))
{
    avb_1722_1_packet_header_t *pkt = (avb_1722_1_packet_header_t *) &buf[0];
    unsigned subtype = GET_1722_1_SUBTYPE(pkt);
    unsigned datalen = GET_1722_1_DATALENGTH(pkt);

    switch (subtype)
    {
    case DEFAULT_1722_1_ADP_SUBTYPE:
        if (datalen == AVB_1722_1_ADP_CD_LENGTH)
        {
          process_avb_1722_1_adp_packet(*(avb_1722_1_adp_packet_t*)pkt, i_eth);
        }
        return;
    case DEFAULT_1722_1_AECP_SUBTYPE:
        process_avb_1722_1_aecp_packet(src_addr, (avb_1722_1_aecp_packet_t*)pkt, len, i_eth, i_avb_api, i_1722_1_entity);
        return;
    case DEFAULT_1722_1_ACMP_SUBTYPE:
        if (datalen == AVB_1722_1_ACMP_CD_LENGTH)
        {
          process_avb_1722_1_acmp_packet((avb_1722_1_acmp_packet_t*)pkt, i_eth);
        }
        return;
    default:
        return;
    }
}

void avb_1722_1_periodic(client interface ethernet_tx_if i_eth, chanend c_ptp, client interface avb_interface i_avb)
{
    avb_1722_1_adp_advertising_periodic(i_eth, c_ptp);
#if (AVB_1722_1_CONTROLLER_ENABLED)
    avb_1722_1_adp_discovery_periodic(i_eth, i_avb);
    avb_1722_1_acmp_controller_periodic(i_eth, i_avb);
#endif
#if (AVB_1722_1_TALKER_ENABLED)
    avb_1722_1_acmp_talker_periodic(i_eth, i_avb);
#endif
#if (AVB_1722_1_LISTENER_ENABLED)
    avb_1722_1_acmp_listener_periodic(i_eth, i_avb);
#endif
    avb_1722_1_aecp_aem_periodic(i_eth);
}

// avb_mrp.c:
extern unsigned char srp_dest_mac[6];
extern unsigned char mvrp_dest_mac[6];

#if AVB_1722_1_FAST_CONNECT_ENABLED
extern int fast_connect_info_valid;
extern avb_1722_1_acmp_cmd_resp acmp_listener_rcvd_cmd_resp;
#endif

[[combinable]]
void avb_1722_1_maap_srp_task(client interface avb_interface i_avb,
                              client interface avb_1722_1_control_callbacks i_1722_1_entity,
                              fl_QSPIPorts &?qspi_ports,
                              client interface ethernet_rx_if i_eth_rx,
                              client interface ethernet_tx_if i_eth_tx,
                              client interface ethernet_cfg_if i_eth_cfg,
                              chanend c_ptp,
                              otp_ports_t &?otp_ports) {
  unsigned periodic_timeout;
  timer tmr;
#if AVB_1722_1_FAST_CONNECT_ENABLED
  unsigned fast_connect_finished=0;
  unsigned fast_connect_seconds=0;
  unsigned fast_connect_timeout=0;
  unsigned t_fc;
  timer tmr_fc;
  tmr_fc :> t_fc;
#endif
  unsigned int buf[(ETHERNET_MAX_PACKET_SIZE+3)>>2];
  unsigned char mac_addr[6];
  unsigned int serial = 0x12345678;

  if (!isnull(otp_ports)) {
    otp_board_info_get_serial(otp_ports, serial);
  }

#if AVB_1722_1_FIRMWARE_UPGRADE_ENABLED
  if (isnull(qspi_ports)) {
    fail("Firmware upgrade enabled but QSPI ports null");
  }
  else if (fl_connect(qspi_ports)) {
    fail("Could not connect to flash");
  }
#endif

  srp_store_ethernet_interface(i_eth_tx);
  mrp_store_ethernet_interface(i_eth_tx);

  i_eth_cfg.get_macaddr(0, mac_addr);

  mrp_init(mac_addr);
  srp_domain_init();
  avb_mvrp_init();

  size_t eth_index = i_eth_rx.get_index();
  ethernet_macaddr_filter_t avdecc_maap_filter;
  avdecc_maap_filter.appdata = 0;
  memcpy(avdecc_maap_filter.addr, mac_addr, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, avdecc_maap_filter);
  memcpy(avdecc_maap_filter.addr, maap_dest_addr, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, avdecc_maap_filter);
  memcpy(avdecc_maap_filter.addr, avb_1722_1_adp_dest_addr, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, avdecc_maap_filter);
  i_eth_cfg.add_ethertype_filter(eth_index, AVB_1722_ETHERTYPE);

  ethernet_macaddr_filter_t msrp_mvrp_filter;
  msrp_mvrp_filter.appdata = 0;
  memcpy(msrp_mvrp_filter.addr, srp_dest_mac, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, msrp_mvrp_filter);
  memcpy(msrp_mvrp_filter.addr, mvrp_dest_mac, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, msrp_mvrp_filter);
  i_eth_cfg.add_ethertype_filter(eth_index, AVB_SRP_ETHERTYPE);
  i_eth_cfg.add_ethertype_filter(eth_index, AVB_MVRP_ETHERTYPE);

  avb_1722_1_init(mac_addr, serial);
  avb_1722_maap_init(mac_addr);
#if NUM_ETHERNET_PORTS > 1
  avb_1722_maap_request_addresses(AVB_NUM_SOURCES, null);
#endif

  tmr :> periodic_timeout;

  while (1) {
    select {
      // Receive and process any incoming AVB packets (802.1Qat, 1722_MAAP)
      case i_eth_rx.packet_ready():
      {
        ethernet_packet_info_t packet_info;
        i_eth_rx.get_packet(packet_info, (char *)buf, ETHERNET_MAX_PACKET_SIZE);
        avb_process_srp_control_packet(i_avb, buf, packet_info.len, packet_info.type, i_eth_tx, packet_info.src_ifnum);
        avb_process_1722_control_packet(buf, packet_info.len, packet_info.type, i_eth_tx, i_avb, i_1722_1_entity);
        break;
      }
      // Periodic processing
      case tmr when timerafter(periodic_timeout) :> unsigned int time_now:
      {
        avb_1722_1_periodic(i_eth_tx, c_ptp, i_avb);
        avb_1722_maap_periodic(i_eth_tx, i_avb);
        mrp_periodic(i_avb);

        periodic_timeout = time_now + PERIODIC_POLL_TIME;
        break;
      }
#if AVB_1722_1_FAST_CONNECT_ENABLED
      // The following logic is implemented in accordance with chapter 8.2.2.1.1 Fast Connect in IEEE Std 1722.1-2013.
      // If valid fast connect information was read from the flash (fast_connect_info_valid), 
      // the logic will try for 30 seconds to connect the local Listener to a previously connected remote Talker.
      // Timer period is 2 * CONNECT_TX_COMMAND timeout periods (4 seconds) according to page 274 in IEEE Std 1722.1-2013:
      // The AVDECC Entity may also run its own timer and retry the connection after waiting two CONNECT_TX_COMMAND timeout periods.
      case (fast_connect_info_valid && !fast_connect_timeout && !fast_connect_finished) => tmr_fc when timerafter(t_fc+(2*ACMP_TIMEOUT_CONNECT_TX_COMMAND*XS1_TIMER_KHZ)) :> t_fc:
      {

        fast_connect_finished = acmp_execute_fast_connect(i_eth_tx);

        fast_connect_seconds += 2*ACMP_TIMEOUT_CONNECT_TX_COMMAND/1000;
        if(fast_connect_seconds > 30) {
          fast_connect_timeout = 1;
          unsigned long long tguid = acmp_listener_rcvd_cmd_resp.talker_guid.l;
          debug_printf("Fast Connect: ERROR. Talker with GUID 0x%x%x not detected after %d seconds\n"
                    ,(unsigned) (tguid >> 32), (unsigned) tguid, fast_connect_seconds);
          debug_printf("Aborting Fast Connect\n");
          acmp_listener_rcvd_cmd_resp.flags = 0; // reset flag
        }
        break;
      }
#endif
    }
  }
}


[[combinable]]
void avb_1722_1_maap_task(otp_ports_t &?otp_ports,
                              client interface avb_interface i_avb,
                              client interface avb_1722_1_control_callbacks i_1722_1_entity,
                              fl_QSPIPorts &?qspi_ports,
                              client interface ethernet_rx_if i_eth_rx,
                              client interface ethernet_tx_if i_eth_tx,
                              client interface ethernet_cfg_if i_eth_cfg,
                              chanend c_ptp) {
  unsigned periodic_timeout;
  timer tmr;
#if AVB_1722_1_FAST_CONNECT_ENABLED
  unsigned fast_connect_finished=0;
  unsigned fast_connect_seconds=0;
  unsigned fast_connect_timeout=0;
  unsigned t_fc;
  timer tmr_fc;
  tmr_fc :> t_fc;
#endif
  unsigned int buf[(ETHERNET_MAX_PACKET_SIZE+3)>>2];
  unsigned char mac_addr[6];
  unsigned int serial = 0x12345678;

  if (!isnull(otp_ports)) {
    otp_board_info_get_serial(otp_ports, serial);
  }
#if AVB_1722_1_FIRMWARE_UPGRADE_ENABLED
  if (isnull(qspi_ports)) {
    fail("Firmware upgrade enabled but QSPI ports null");
  }
  else if (fl_connect(qspi_ports)) {
    fail("Could not connect to flash");
  }
#endif

  i_eth_cfg.get_macaddr(0, mac_addr);

  size_t eth_index = i_eth_rx.get_index();
  ethernet_macaddr_filter_t avdecc_maap_filter;
  avdecc_maap_filter.appdata = 0;
  memcpy(avdecc_maap_filter.addr, mac_addr, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, avdecc_maap_filter);
  memcpy(avdecc_maap_filter.addr, maap_dest_addr, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, avdecc_maap_filter);
  memcpy(avdecc_maap_filter.addr, avb_1722_1_adp_dest_addr, 6);
  i_eth_cfg.add_macaddr_filter(eth_index, 0, avdecc_maap_filter);

  avb_1722_1_init(mac_addr, serial);
  avb_1722_maap_init(mac_addr);
#if NUM_ETHERNET_PORTS > 1
  avb_1722_maap_request_addresses(AVB_NUM_SOURCES, null);
#endif

  tmr :> periodic_timeout;

  printstrln("avb_1722_1_maap_task starting\n");

  while (1) {
    select {
      // Receive and process any incoming AVB packets (802.1Qat, 1722_MAAP)
      case i_eth_rx.packet_ready():
      {
        ethernet_packet_info_t packet_info;
        i_eth_rx.get_packet(packet_info, (char *)buf, AVB_1722_1_PACKET_SIZE_WORDS * 4);

        avb_process_1722_control_packet(buf, packet_info.len, packet_info.type, i_eth_tx, i_avb, i_1722_1_entity);
        break;
      }
      // Periodic processing
      case tmr when timerafter(periodic_timeout) :> unsigned int time_now:
      {
        avb_1722_1_periodic(i_eth_tx, c_ptp, i_avb);
        avb_1722_maap_periodic(i_eth_tx, i_avb);

        periodic_timeout += PERIODIC_POLL_TIME;
        break;
      }
#if AVB_1722_1_FAST_CONNECT_ENABLED
      // The following logic is implemented in accordance with chapter 8.2.2.1.1 Fast Connect in in IEEE Std 1722.1-2013.
      // If valid fast connect information was read from the flash (fast_connect_info_valid), 
      // the logic will try for 30 seconds to connect the local Listener to a previously connected remote Talker.
      // Timer period is 2 * CONNECT_TX_COMMAND timeout periods (4 seconds) according to page 274 in IEEE Std 1722.1-2013:
      // The AVDECC Entity may also run its own timer and retry the connection after waiting two CONNECT_TX_COMMAND timeout periods.
      case (fast_connect_info_valid && !fast_connect_timeout && !fast_connect_finished) => tmr_fc when timerafter(t_fc+(2*ACMP_TIMEOUT_CONNECT_TX_COMMAND*XS1_TIMER_KHZ)) :> t_fc:
      {

        fast_connect_finished = acmp_execute_fast_connect(i_eth_tx);

        fast_connect_seconds += 2*ACMP_TIMEOUT_CONNECT_TX_COMMAND/1000;
        if(fast_connect_seconds > 30) {
          fast_connect_timeout = 1;
          unsigned long long tguid = acmp_listener_rcvd_cmd_resp.talker_guid.l;
          debug_printf("Fast Connect: ERROR. Talker with GUID 0x%x%x not detected after %d seconds\n"
                    ,(unsigned) (tguid >> 32), (unsigned) tguid, fast_connect_seconds);
          debug_printf("Aborting Fast Connect\n");
          acmp_listener_rcvd_cmd_resp.flags = 0; // reset flag
        }
        break;
      }
#endif
    }
  }
}
