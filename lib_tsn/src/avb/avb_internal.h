// Copyright (c) 2011-2017, XMOS Ltd, All rights reserved
#ifndef _avb_internal_h_
#define _avb_internal_h_

#include <xccompat.h>
#include <quadflashlib.h>
#include "xc2compat.h"
#include "avb.h"
#include "avb_1722_1_callbacks.h"
#include "media_clock_internal.h"
#include "ethernet.h"

#ifndef MAX_AVB_CONTROL_PACKET_SIZE
#define MAX_AVB_CONTROL_PACKET_SIZE (1518)
#endif

#ifdef __XC__
/** Process an AVB 1722 control packet.

   This function processes a 1722 ethernet packet with the control data bit set

   This function should always be called on the buffer filled by
   avb_get_control_packet().

   \param buf     the incoming message buffer
   \param nbytes  the length (in bytes) of the incoming buffer
   \param c_tx    chanend connected to the ethernet mac (TX)
   \param i_avb   client interface of type avb_interface into avb_manager()
   \param i_1722_1_entity client interface of type avb_1722_1_control_callbacks
   \param i_spi  client interface of type spi_interface into avb_srp_task()
 **/
void avb_process_1722_control_packet(unsigned int buf[],
                                    unsigned nbytes,
                                    eth_packet_type_t packet_type,
                                    client interface ethernet_tx_if i_eth,
                                    client interface avb_interface i_avb,
                                    client interface avb_1722_1_control_callbacks i_1722_1_entity);

/** Process an AVB SRP control packet.

   This function processes an 802.1Qat ethernet packet

   This function should always be called on the buffer filled by
   avb_get_control_packet().

   \param i_avb   client interface of type avb_interface into avb_manager()
   \param buf the incoming message buffer
   \param len the length (in bytes) of the incoming buffer
   \param c_tx           chanend connected to the ethernet mac (TX)
   \param port_num the id of the Ethernet interface the packet was received

 **/
void avb_process_srp_control_packet(client interface avb_interface i_avb,
                               unsigned int buf[], unsigned len,
                               eth_packet_type_t packet_type,
                               client interface ethernet_tx_if i_eth,
                               unsigned int port_num);
#endif

/**
 *   \brief Set the volume multipliers for the audio channels
 *
 *   The number of channels in the array should be equal to the number
 *   of channels set in the set_avb_source_map function call.
 *
 *   This function adjusts the stream channels while the stream is
 *   active, and therefore cannot be called while the stream is
 *   inactive.
 *
 *   \param sink_num the stream number to apply the change to
 *   \param volumes a set of volume values in 2.30 signed fixed point linear format
 *   \param count the number of channels to set
 *
 */
void set_avb_source_volumes(unsigned sink_num, int volumes[], int count);

int set_avb_source_port(unsigned source_num,
                        int srcport);

int avb_register_listener_streams(chanend listener_ctl,
                                   int num_streams);

void avb_register_talker_streams(chanend listener_ctl,
                                 int num_streams,
                                 unsigned char mac_addr[6]);

/** Utility function to get the index of a source stream based on its
 * pointer.  This is used by SRP, which stores a pointer to the stream
 * structure rather than an index.
 */
unsigned avb_get_source_stream_index_from_pointer(avb_source_info_t *unsafe p);

/** Utility function to get the index of a sink stream based on its
 * pointer.  This is used by SRP, which stores a pointer to the stream
 * structure rather than an index.
 */
unsigned avb_get_sink_stream_index_from_pointer(avb_sink_info_t *unsafe p);

unsigned avb_get_source_stream_index_from_stream_id(unsigned int stream_id[2]);
unsigned avb_get_sink_stream_index_from_stream_id(unsigned int stream_id[2]);

#endif // _avb_internal_h_
