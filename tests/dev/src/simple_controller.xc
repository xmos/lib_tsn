// Copyright (c) 2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include "nettypes.h"
#include "avb_1722_common.h"
#include "avb_1722_1_protocol.h"
#include "avb_1722_1_acmp.h"
#include "avb_1722_1_adp.h"
#include "simple_controller.h"

#define DEBUG_STATE 1

static const unsigned char adp_mac[] = AVB_1722_1_ADP_DEST_MAC; /* 91 e0 f0 01 00 00 */

extern unsigned char my_mac_addr[6];

static struct simple_controller_config
{
  guid_t my_guid;
  guid_t listener_guid;
  avb_1722_1_acmp_cmd_resp tx_resp;
  avb_1722_1_acmp_cmd_resp rx_cmd;
} config;

enum simple_controller_state
{
  INITIAL,
  ADP_ANNOUNCE_RECEIVED,
  RX_CMD_SENT,
  TX_CMD_RECEIVED,
  TX_RESP_SENT
} state;

#if DEBUG_STATE
char state_str[][40] = {
  "INITIAL",
  "ADP_ANNOUNCE_RECEIVED",
  "RX_CMD_SENT",
  "TX_CMD_RECEIVED",
  "TX_RESP_SENT"
};
#endif

static void transition(enum simple_controller_state new_state)
{
#if DEBUG_STATE
  debug_printf("Controller %s -> %s\n", state_str[state], state_str[new_state]);
#endif
  state = new_state;
}

void simple_controller_init(client ethernet_cfg_if i_cfg, client ethernet_rx_if i_rx, const unsigned char src_mac_addr[6],
  unsigned char stream_id[8])
{
  const int stream_local_id = 0;
  ethernet_macaddr_filter_t filter_adp;
  unsigned char *my_guid = config.my_guid.c;
  avb_1722_1_acmp_cmd_resp *rx_cmd = &config.rx_cmd;

  my_guid[0] = src_mac_addr[5];
  my_guid[1] = src_mac_addr[4];
  my_guid[2] = src_mac_addr[3];
  my_guid[3] = 0xfe;
  my_guid[4] = 0xff;
  my_guid[5] = src_mac_addr[2];
  my_guid[6] = src_mac_addr[1];
  my_guid[7] = src_mac_addr[0];

  memcpy(filter_adp.addr, adp_mac, 6);
  i_cfg.add_macaddr_filter(i_rx.get_index(), 0, filter_adp);

  /* setting source MAC for 1722.1 routines here, because we are not
   * calling MAAP init where it would normally be set
   */
  memcpy(my_mac_addr, src_mac_addr, 6);

  rx_cmd->controller_guid = config.my_guid;
  rx_cmd->talker_guid.l = config.my_guid.l;
  rx_cmd->talker_unique_id = 0;
  rx_cmd->listener_unique_id = 0;

  rx_cmd->stream_dest_mac[0] = 0xFF; /* TODO proper address */
  rx_cmd->stream_dest_mac[1] = 0xFF;
  rx_cmd->stream_dest_mac[2] = 0xFF;
  rx_cmd->stream_dest_mac[3] = 0xFF;
  rx_cmd->stream_dest_mac[4] = 0xFF;
  rx_cmd->stream_dest_mac[5] = 0xFF;

  stream_id[0] = (stream_local_id >> 8) & 0xFF;
  stream_id[1] = stream_local_id & 0xFF;
  stream_id[2] = src_mac_addr[5];
  stream_id[3] = src_mac_addr[4];
  stream_id[4] = src_mac_addr[3];
  stream_id[5] = src_mac_addr[2];
  stream_id[6] = src_mac_addr[1];
  stream_id[7] = src_mac_addr[0];

  memcpy(rx_cmd->stream_id.c, stream_id, 8);

  transition(INITIAL);
}

void simple_controller_periodic(client ethernet_tx_if i_tx)
{
  switch (state) {
    case ADP_ANNOUNCE_RECEIVED:
      acmp_send_command(0, ACMP_CMD_CONNECT_RX_COMMAND, &config.rx_cmd, 0, -1, i_tx);
      transition(RX_CMD_SENT);
      break;

    case TX_CMD_RECEIVED:
      acmp_send_response(ACMP_CMD_CONNECT_TX_RESPONSE, &config.tx_resp, ACMP_STATUS_SUCCESS, i_tx);
      transition(TX_RESP_SENT);
      break;
  }
}

extern void store_rcvd_cmd_resp(avb_1722_1_acmp_cmd_resp &store, const avb_1722_1_acmp_packet_t &pkt);

void simple_controller_packet_received(const unsigned char packet_buf[], const ethernet_packet_info_t &packet_info)
{
  const struct ethernet_hdr_t *ethernet_hdr;
  const avb_1722_1_packet_header_t *pkt_1722;
  const avb_1722_1_adp_packet_t *pkt_adp;
  const avb_1722_1_acmp_packet_t *pkt_acmp;
  unsigned subtype;
  int has_qtag;
  int etype;
  int eth_hdr_size;

  ethernet_hdr = (const ethernet_hdr_t*)packet_buf;
  has_qtag = ethernet_hdr->ethertype.data[1] == 0x18;
  eth_hdr_size = has_qtag ? 18 : 14;
  etype = (int)(ethernet_hdr->ethertype.data[0] << 8) + (int)(ethernet_hdr->ethertype.data[1]);

  /* only interested in 1722.1 packets */
  if (etype != AVB_1722_ETHERTYPE)
    return;

  pkt_1722 = (const avb_1722_1_packet_header_t*)&packet_buf[eth_hdr_size];
  subtype = GET_1722_1_SUBTYPE(pkt_1722);

  switch (state) {
    case INITIAL:
      if (subtype == DEFAULT_1722_1_ADP_SUBTYPE) {
        pkt_adp = (const avb_1722_1_adp_packet_t*)&packet_buf[eth_hdr_size];
        get_64(config.listener_guid.c, (const unsigned char*)pkt_adp->entity_guid);
        config.rx_cmd.listener_guid.l = config.listener_guid.l;
        transition(ADP_ANNOUNCE_RECEIVED);
      }
      break;

    case RX_CMD_SENT:
      if (subtype == DEFAULT_1722_1_ACMP_SUBTYPE) {
        pkt_acmp = (const avb_1722_1_acmp_packet_t*)&packet_buf[eth_hdr_size];
        if (GET_1722_1_MSG_TYPE(pkt_1722) == ACMP_CMD_CONNECT_TX_COMMAND) {
          store_rcvd_cmd_resp(config.tx_resp, *pkt_acmp);
          transition(TX_CMD_RECEIVED);
        }
      }
      break;
  }
}
