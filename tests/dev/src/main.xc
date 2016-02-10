// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <platform.h>
#include "xassert.h"
#include "debug_print.h"
#include "otp_board_info.h"
#include "smi.h"
#include "ethernet.h"
#include "gptp.h"
#include "simple_talker.h"

port p_eth_rxclk  = PORT_ETH_RXCLK;
port p_eth_rxd    = PORT_ETH_RXD;
port p_eth_txd    = PORT_ETH_TXD;
port p_eth_rxdv   = PORT_ETH_RXDV;
port p_eth_txen   = PORT_ETH_TXEN;
port p_eth_txclk  = PORT_ETH_TXCLK;
port p_eth_rxerr  = PORT_ETH_RXER;
port p_eth_rst    = PORT_ETH_RSTN;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

port p_smi_mdio   = PORT_ETH_MDIO;
port p_smi_mdc    = PORT_ETH_MDC;

otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

#define ETHERNET_BUFFER_ALIGNMENT 2

enum eth_clients {
  ETH_TO_PTP,
  NUM_ETH_CLIENTS
};

enum cfg_clients {
  CFG_TO_PTP,
  CFG_TO_PHY_DRIVER,
  MAC_CFG_TO_APP,
  NUM_CFG_CLIENTS
};

enum ptp_clients {
  PTP_TO_APP,
  NUM_PTP_CHANS
};

[[combinable]]
void lan8710a_phy_driver(client interface smi_if smi,
  client interface ethernet_cfg_if eth, out port rstn)
{
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  ethernet_speed_t link_speed = LINK_100_MBPS_FULL_DUPLEX;
  const int link_poll_period_ms = 1000;
  const int phy_address = 0x0;
  timer tmr;
  int t;
  tmr :> t;

  rstn <: 1;

  while (smi_phy_is_powered_down(smi, phy_address))
    {}

  smi_configure(smi, phy_address, LINK_100_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);

  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      ethernet_link_state_t new_state = smi_get_link_state(smi, phy_address);
      // Read LAN8710A status register bit 2 to get the current link speed
      if ((new_state == ETHERNET_LINK_UP) &&
         ((smi.read_reg(phy_address, 0x1F) >> 2) & 1)) {
        link_speed = LINK_10_MBPS_FULL_DUPLEX;
      }
      else {
        link_speed = LINK_100_MBPS_FULL_DUPLEX;
      }
      if (new_state != link_state) {
        link_state = new_state;
        eth.set_link_state(0, new_state, link_speed);
      }
      t += link_poll_period_ms * XS1_TIMER_KHZ;
      break;
    }
  }
}

#define PTP_DEFAULT_GM_CAPABLE_PRIORITY1 250
#define PRIORITY_CHANGE_DELAY_TICKS 1000000000
#define TIMEINFO_UPDATE_INTERVAL_TICKS 100000000
#define AUDIO_PACKET_RATE_HZ 48000

void test_app(client ethernet_cfg_if i_cfg, chanend c_ptp, streaming chanend c_eth_tx_hp)
{
  timer tmr1, tmr2, tmr3;
  int t_priority_change, t_audio_packet, t_timeinfo_update;
  unsigned char priority_current;
  unsigned char packet_buf[1500 + ETHERNET_BUFFER_ALIGNMENT];
  int packet_size;
  ptp_time_info_mod64 time_info;
  unsigned audio_sample_count;
  unsigned audio_packet_count;
  int pending_timeinfo;
  simple_talker_config_t talker_config;
  unsigned char own_mac_addr[6];

  priority_current = PTP_DEFAULT_GM_CAPABLE_PRIORITY1;
  tmr1 :> t_priority_change;
  t_priority_change += PRIORITY_CHANGE_DELAY_TICKS;

  ptp_set_master_rate(c_ptp, 100000);

  tmr2 :> t_audio_packet;
  /* approximate rate - only integer division */
  t_audio_packet += XS1_TIMER_HZ / AUDIO_PACKET_RATE_HZ;

  i_cfg.get_macaddr(0, own_mac_addr);
  talker_config = simple_talker_init(packet_buf, sizeof(packet_buf), own_mac_addr);
  audio_sample_count = 0;
  audio_packet_count = 0;

  ptp_get_time_info_mod64(c_ptp, time_info);
  pending_timeinfo = 0;

  while (1) {
    select {
      case tmr1 when timerafter(t_priority_change) :> void:
        if (priority_current == PTP_DEFAULT_GM_CAPABLE_PRIORITY1)
          priority_current = 100;
        else
          priority_current = PTP_DEFAULT_GM_CAPABLE_PRIORITY1;

        ptp_set_priority(c_ptp, priority_current, 248);
        ptp_reset_port(c_ptp, 0);
        t_priority_change += PRIORITY_CHANGE_DELAY_TICKS;
        break;

      case tmr2 when timerafter(t_audio_packet) :> void:
        packet_size = simple_talker_create_packet(talker_config, packet_buf, sizeof(packet_buf),
          time_info, t_audio_packet, (audio_sample_count & 0xFFFFFF) << 8);
        if (packet_size > 0) {
          ethernet_send_hp_packet(c_eth_tx_hp, &packet_buf[ETHERNET_BUFFER_ALIGNMENT], packet_size, ETHERNET_ALL_INTERFACES);
          audio_packet_count++;
        }
        t_audio_packet += XS1_TIMER_HZ / AUDIO_PACKET_RATE_HZ;
        audio_sample_count++;
        break;

      case tmr3 when timerafter(t_timeinfo_update) :> void:
        if (!pending_timeinfo) {
          ptp_request_time_info_mod64(c_ptp);
          pending_timeinfo = 1;
        }
        t_timeinfo_update += TIMEINFO_UPDATE_INTERVAL_TICKS;
        break;

      case ptp_get_requested_time_info_mod64(c_ptp, time_info):
        pending_timeinfo = 0;
        break;
    }
  }
}

#define ETH_RX_BUFFER_SIZE_WORDS 1600
#define ETH_TX_BUFFER_SIZE_WORDS 1600

int main(void)
{
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  smi_if i_smi;
  streaming chan c_tx_hp;
  chan c_ptp[NUM_PTP_CHANS];

  par {
    on tile[1]: mii_ethernet_rt_mac(i_cfg, NUM_CFG_CLIENTS,
      i_rx, NUM_ETH_CLIENTS, i_tx, NUM_ETH_CLIENTS,
      NULL, c_tx_hp,
      /* LISTENER: c_rx_hp, NULL, */
      p_eth_rxclk, p_eth_rxerr,
      p_eth_rxd, p_eth_rxdv,
      p_eth_txclk, p_eth_txen, p_eth_txd,
      eth_rxclk, eth_txclk,
      ETH_RX_BUFFER_SIZE_WORDS,
      ETH_TX_BUFFER_SIZE_WORDS,
      ETHERNET_DISABLE_SHAPER);

    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[1]: lan8710a_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER], p_eth_rst);

    on tile[0]: {
        char mac_address[6];
        if (otp_board_info_get_mac(otp_ports, 0, mac_address) == 0)
          fail("no MAC address programmed in OTP");

        /* force PTP slave by using a high MAC address */
        mac_address[3] = 0xFF;

        i_cfg[CFG_TO_PTP].set_macaddr(0, mac_address);
        i_cfg[CFG_TO_PTP].get_macaddr(0, mac_address);
        debug_printf("MAC %x:%x:%x:%x:%x:%x\n",
          mac_address[0], mac_address[1], mac_address[2],
          mac_address[3], mac_address[4], mac_address[5]);

        ptp_server(i_rx[ETH_TO_PTP], i_tx[ETH_TO_PTP], i_cfg[CFG_TO_PTP],
          c_ptp, NUM_PTP_CHANS, PTP_GRANDMASTER_CAPABLE);
    }

    on tile[0]: test_app(i_cfg[MAC_CFG_TO_APP], c_ptp[PTP_TO_APP], c_tx_hp);
  }

  return 0;
}
