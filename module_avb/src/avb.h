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

#ifdef __XC__

/** Core AVB API management task that can be combined with other AVB tasks such as SRP or 1722.1

 * \param i_avb[]           array of avb_interface server interfaces connected to clients of avb_manager
 * \param num_avb_clients   number of client interface connections to the server and the number of elements of i_avb[]
 * \param i_srp            client interface of type srp_interface into an srp_task() task
 * \param c_media_ctl[]     array of chanends connected to components that register/control media FIFOs
 * \param c_listener_ctl[]  array of chanends connected to components that register/control IEEE 1722 sinks
 * \param c_talker_ctl[]    array of chanends connected to components that register/control IEEE 1722 sources
 * \param c_mac_tx          chanend connection to the Ethernet TX server
 * \param i_media_clock_ctl client interface of type media_clock_if connected to the media clock server
 * \param c_ptp             chanend connection to the PTP server
 */
[[combinable]]
void avb_manager(server interface avb_interface i_avb[num_avb_clients], unsigned num_avb_clients,
                 client interface srp_interface i_srp,
                 chanend c_media_ctl[],
                 chanend (&?c_listener_ctl)[],
                 chanend (&?c_talker_ctl)[],
                 chanend c_mac_tx,
                 client interface media_clock_if ?i_media_clock_ctl,
                 chanend c_ptp);
#endif

/** Receives an 802.1Qat SRP packet or an IEEE 1722 control packet.
 *
 *  This function receives an AVB control packet from the ethernet MAC.
 *  It is selectable so can be used in a select statement as a case.
 *
 *  \param c_rx     chanend connected to the ethernet component
 *  \param buf      buffer to retrieve the packet into; buffer
 *                  must have length at least ``MAX_AVB_CONTROL_PACKET_SIZE``
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
                                    chanend c_tx,
                                    client interface avb_interface i_avb,
                                    client interface avb_1722_1_control_callbacks i_1722_1_entity,
                                    client interface spi_interface i_spi);

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
