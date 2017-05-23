// Copyright (c) 2015-2017, XMOS Ltd, All rights reserved
#ifndef __ptp_internal_h__
#define __ptp_internal_h__

#include "nettypes.h"

#define PTP_ADJUST_PREC 30

enum ptp_cmd_t {
  PTP_GET_TIME_INFO,
  PTP_GET_TIME_INFO_MOD64,
  PTP_GET_GRANDMASTER,
  PTP_GET_STATE,
  PTP_GET_PDELAY
};

typedef enum ptp_port_role_t {
  PTP_MASTER,
  PTP_UNCERTAIN,
  PTP_SLAVE,
  PTP_DISABLED
} ptp_port_role_t;

typedef struct ptp_path_delay_t {
  int valid;
  unsigned int pdelay;
  unsigned int lost_responses;
  unsigned int exchanges;
  unsigned int multiple_resp_count;
  unsigned int last_multiple_resp_seq_id;
  n80_t rcvd_source_identity;
} ptp_path_delay_t;

typedef struct ptp_port_info_t {
  int asCapable;
  ptp_port_role_t role_state;
  ptp_path_delay_t delay_info;
} ptp_port_info_t;

// Synchronous PTP client functions
// --------------------------------

ptp_port_role_t ptp_get_state(chanend ptp_server);


/** Retrieve time information from the PTP server
 *
 *  This function gets an up-to-date structure of type `ptp_time_info` to use
 *  to convert local time to PTP time.
 *
 *  \param ptp_server chanend connected to the ptp_server
 *  \param info       structure to be filled with time information
 *
 **/
void ptp_get_propagation_delay(chanend ptp_server, unsigned *pdelay);


void ptp_get_current_grandmaster(chanend ptp_server, unsigned char grandmaster[8]);


/** Initialize the inline ptp server.
 *
 *  \param i_eth_rx       interface connected to the ethernet server (receive)
 *  \param i_eth_tx       interface connected to the ethernet server (transmit)
 *  \param server_type The type of the server (``PTP_GRANDMASTER_CAPABLE``
 *                     or ``PTP_SLAVE_ONLY``)
 *
 *  This function initializes the PTP server when you want to use it inline
 *  combined with other event handling functions (i.e. share the resource in
 *  the ptp thread).
 *  It needs to be called in conjunction with do_ptp_server().
 *  Here is an example usage::
 *
 *     ptp_server_init(c_rx, c_tx, PTP_GRANDMASTER_CAPABLE);
 *     while (1) {
 *         select {
 *             do_ptp_server(c_tx, c_tx, ptp_client, num_clients);
 *             // Add your own cases here
 *         }
 *
 *     }
 *
 *  \sa do_ptp_server
 **/
void ptp_server_init(CLIENT_INTERFACE(ethernet_cfg_if, i_eth_cfg),
                     CLIENT_INTERFACE(ethernet_rx_if, i_eth_rx),
                     chanend c,
                     enum ptp_server_type server_type,
                     timer ptp_timer,
                     REFERENCE_PARAM(int, ptp_timeout));


#ifdef __XC__
void ptp_recv_and_process_packet(client interface ethernet_rx_if i_eth_rx, client interface ethernet_tx_if i_eth_tx);
#endif
#ifdef __XC__
#pragma select handler
#endif
void ptp_process_client_request(chanend c, timer ptp_timer);
void ptp_periodic(CLIENT_INTERFACE(ethernet_tx_if, i_eth), unsigned);
#define PTP_PERIODIC_TIME (10000)  // 0.tfp1 milliseconds





#define do_ptp_server(i_eth_rx, i_eth_tx, client, num_clients, ptp_timer, ptp_timeout)      \
  case i_eth_rx.packet_ready(): \
       ptp_recv_and_process_packet(i_eth_rx, i_eth_tx); \
       break;                     \
 case (int i=0;i<num_clients;i++) ptp_process_client_request(client[i], ptp_timer): \
       break; \
  case ptp_timer when timerafter(ptp_timeout) :> void: \
       ptp_periodic(i_eth_tx, ptp_timeout); \
       ptp_timeout += PTP_PERIODIC_TIME; \
       break

void ptp_get_local_time_info_mod64(REFERENCE_PARAM(ptp_time_info_mod64,info));

void ptp_output_test_clock(chanend ptp_link,
                           port test_clock_port,
                           int period);

#endif // __ptp_internal_h__
