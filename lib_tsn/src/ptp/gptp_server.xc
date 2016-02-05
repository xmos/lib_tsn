// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <xs1.h>
#include "gptp.h"
#include "gptp_internal.h"
#include "gptp_config.h"
#include "ethernet.h"
#include "debug_print.h"

/* These functions are the workhorse functions for the actual protocol.
   They are implemented in gptp.c  */
void ptp_init(client interface ethernet_cfg_if, client interface ethernet_rx_if, enum ptp_server_type stype, chanend c);
void ptp_reset(int port_num);
void ptp_recv(client interface ethernet_tx_if, unsigned char buf[], unsigned ts, unsigned src_port, unsigned len);
void ptp_periodic(client interface ethernet_tx_if, unsigned);
void ptp_get_reference_ptp_ts_mod_64(unsigned &hi, unsigned &lo);
void ptp_current_grandmaster(char grandmaster[8]);
ptp_port_role_t ptp_current_state(void);

#define MAX_PTP_MESG_LENGTH (100 + (PTP_MAXIMUM_PATH_TRACE_TLV*8))

#define PTP_PERIODIC_TIME (10000)  // 0.1 milliseconds

#pragma select handler
void receive_ptp_cmd(chanend c, unsigned int &cmd)
{
  cmd = inuchar(c);
  return;
}

extern unsigned ptp_reference_local_ts;
extern ptp_timestamp ptp_reference_ptp_ts;
extern signed int g_ptp_adjust;
extern signed int g_inv_ptp_adjust;
extern signed ptp_adjust_master;
extern u8_t ptp_priority1;
extern u8_t ptp_priority2;

void ptp_server_init(client interface ethernet_cfg_if i_eth_cfg,
                     client interface ethernet_rx_if i_eth_rx,
                     chanend c,
                     enum ptp_server_type server_type,
                     timer ptp_timer,
                     int &ptp_timeout)
{
  ptp_timer :> ptp_timeout;

  ptp_init(i_eth_cfg, i_eth_rx, server_type, c);

}

void ptp_recv_and_process_packet(client interface ethernet_rx_if i_eth_rx,
                                 client interface ethernet_tx_if i_eth_tx)
{
  unsigned char buf[MAX_PTP_MESG_LENGTH];

  ethernet_packet_info_t packet_info;
  i_eth_rx.get_packet(packet_info, buf, MAX_PTP_MESG_LENGTH);

  if (packet_info.type == ETH_IF_STATUS) {
    if (buf[0] == ETHERNET_LINK_UP) {
      ptp_reset(packet_info.src_ifnum);
    }
  }
  else if (packet_info.type == ETH_DATA) {
    ptp_recv(i_eth_tx, buf, packet_info.timestamp, packet_info.src_ifnum, packet_info.len);
  }
}

static void ptp_give_requested_time_info(chanend c, timer ptp_timer)
{
  int thiscore_now;
  unsigned tile_id = get_local_tile_id();
  master {
    ptp_timer :> thiscore_now;
    c <: thiscore_now;
    c <: ptp_reference_local_ts;
    c <: ptp_reference_ptp_ts;
    c <: g_ptp_adjust;
    c <: g_inv_ptp_adjust;
    c <: tile_id;
  }
}
void ptp_get_local_time_info_mod64(ptp_time_info_mod64 &info)
{
  unsigned int hi, lo;
  ptp_get_reference_ptp_ts_mod_64(hi,lo);
  info.local_ts = ptp_reference_local_ts;
  info.ptp_ts_hi = hi;
  info.ptp_ts_lo = lo;
  info.ptp_adjust = g_ptp_adjust;
  info.inv_ptp_adjust = g_inv_ptp_adjust;
}

#pragma select handler
void ptp_process_client_request(chanend c, timer ptp_timer)
{
  unsigned char cmd;
  unsigned thiscore_now;
  unsigned tile_id = get_local_tile_id();

  cmd = inuchar(c);
  (void) inuchar(c);
  (void) inuchar(c);
  (void) inct(c);
  switch (cmd)
  {
    case PTP_GET_TIME_INFO:
      ptp_give_requested_time_info(c, ptp_timer);
      break;
    case PTP_GET_TIME_INFO_MOD64: {
      unsigned int hi, lo;
      ptp_get_reference_ptp_ts_mod_64(hi,lo);
      master {
      c :> int;
      ptp_timer :> thiscore_now;
      c <: thiscore_now;
      c <: ptp_reference_local_ts;
      c <: hi;
      c <: lo;
      c <: g_ptp_adjust;
      c <: g_inv_ptp_adjust;
      c <: tile_id;
      }
      break;
    }
    case PTP_GET_GRANDMASTER: {
      char grandmaster[8];
      ptp_current_grandmaster(grandmaster);
      master
      {
        for(int i = 0; i < 8; i++)
        {
          c <: grandmaster[i];
        }
      }
      break;
    }
    case PTP_GET_STATE: {
      ptp_port_role_t ptp_state = ptp_current_state();
      master
      {
        c <: ptp_state;
      }
      break;
    }
    case PTP_GET_PDELAY: {
      master
      {
        c <: 0;
      }
      break;
    }
    case PTP_SET_PRIORITY: {
      master
      {
        c :> ptp_priority1;
        c :> ptp_priority2;
      }
      debug_printf("PTP set priority %d/%d\n", ptp_priority1, ptp_priority2);
      break;
    }
    case PTP_SET_MASTER_RATE: {
      master
      {
        c :> ptp_adjust_master;
      }
      debug_printf("PTP set master rate %d\n", ptp_adjust_master);
      break;
    }
    case PTP_RESET_PORT: {
      int port_num;
      master
      {
        c :> port_num;
      }
      debug_printf("PTP reset port %d\n", port_num);
      ptp_reset(port_num);
      break;
    }
  }
}


void ptp_server(client interface ethernet_rx_if i_eth_rx,
                client interface ethernet_tx_if i_eth_tx,
                client interface ethernet_cfg_if i_eth_cfg,
                chanend ptp_clients[], int num_clients,
                enum ptp_server_type server_type)
{
  timer ptp_timer;
  int ptp_timeout;
  ptp_server_init(i_eth_cfg, i_eth_rx, ptp_clients[0], server_type, ptp_timer, ptp_timeout);

  while (1) {
    select
      {
        do_ptp_server(i_eth_rx, i_eth_tx, ptp_clients, num_clients, ptp_timer, ptp_timeout);
      }
  }
}
