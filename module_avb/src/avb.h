#ifndef _avb_h_
#define _avb_h_

#include <xccompat.h>
#include "xc2compat.h"
#include "avb_api.h"
#include "avb_srp_interface.h"
#include "avb_1722_1_callbacks.h"
#include "spi.h"
#include "media_clock_server.h"

#ifndef MAX_AVB_CONTROL_PACKET_SIZE
#define MAX_AVB_CONTROL_PACKET_SIZE (1518)
#endif

void avb_init_srp_only(chanend c_mac_rx, chanend c_mac_tx);


/** Start any AVB protocol state machines.
 *
 *  This call starts any AVB protocol state machines running. It should be
 *  called after the ethernet link goes up.
 **/
void avb_start(void);

/** Perform AVB periodic processing.
 *
 *  This function performs AVB periodic processing. It should be called
 *  from the main control thread at least once each ms.
 *
 **/
#ifdef __XC__
void avb_periodic(chanend c_mac_tx, unsigned int time_now);

[[combinable]]
void avb_manager(server interface avb_interface i_avb[num_avb_clients], unsigned num_avb_clients,
                 client interface srp_interface i_srp,
                 chanend c_media_ctl[],
                 chanend (&?c_listener_ctl)[],
                 chanend (&?c_talker_ctl)[],
                 chanend c_mac_tx,
                 client interface media_clock_if ?i_media_clock_ctl,
                 chanend c_ptp);

void avb_process_1722_control_packet(unsigned int buf0[],
                                    unsigned nbytes,
                                    chanend c_tx,
                                    client interface avb_interface i_avb,
                                    client interface avb_1722_1_control_callbacks i_1722_1_entity,
                                    client interface spi_interface i_spi);
#endif

/** Receives an 802.1Qat SRP packet or an IEEE P1722 MAAP packet.
 *
 *  This function receives an AVB control packet from the ethernet MAC.
 *  It is selectable so can be used in a select statement as a case.
 *
 *  \param c_rx     chanend connected to the ethernet component
 *  \param buf      buffer to retrieve the packet into; buffer
 *                  must have length at least ``MAX_AVB_CONTROL_PACKET_SZIE``
 *                  bytes
 *  \param nbytes   a reference parameter that is filled with the length
 *                  of the received packet
 **/
#ifdef __XC__
#pragma select handler
#endif
void avb_get_control_packet(chanend c_rx,
                            unsigned int buf[],
                            REFERENCE_PARAM(unsigned int, nbytes),
                            REFERENCE_PARAM(unsigned int, port_num));

/** Process an AVB control packet.

   This function processes an ethernet packet and if it is a 802.1Qat or
   IEEE 1722 MAAP packet will handle it.

   This function should always be called on the buffer filled by
   avb_get_control_packet().

   \param buf the incoming message buffer
   \param len the length (in bytes) of the incoming buffer
   \param c_tx           chanend connected to the ethernet mac (TX)
   \param port_num the id of the Ethernet interface the packet was received

 **/
#ifdef __XC__
void avb_process_control_packet(client interface avb_interface i_avb,
                               unsigned int buf[], unsigned len,
                               chanend c_tx,
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

#endif // _avb_h_
