// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#ifndef __AVB_1722_1_AECP_CONTROLS_H__
#define __AVB_1722_1_AECP_CONTROLS_H__

#include "avb_1722_1_aecp_pdu.h"
#include "xc2compat.h"
#include "avb.h"
#include "avb_1722_1_callbacks.h"

unsafe void set_current_fields_in_descriptor(unsigned char *unsafe descriptor,
                                            unsigned int desc_size_bytes,
                                            unsigned int read_type, unsigned int read_id,
                                            CLIENT_INTERFACE(avb_interface, i_avb_api),
                                            CLIENT_INTERFACE(avb_1722_1_control_callbacks, i_1722_1_entity));

unsafe unsigned short process_aem_cmd_getset_control(avb_1722_1_aecp_packet_t *unsafe pkt,
                                                     REFERENCE_PARAM(unsigned char, status),
                                                     unsigned short command_type,
                                                     CLIENT_INTERFACE(avb_1722_1_control_callbacks, i_1722_1_entity));

unsafe void process_aem_cmd_getset_signal_selector(avb_1722_1_aecp_packet_t *unsafe pkt,
                                                   REFERENCE_PARAM(unsigned char, status),
                                                   unsigned short command_type,
                                                   CLIENT_INTERFACE(avb_1722_1_control_callbacks, i_1722_1_entity));

unsafe void process_aem_cmd_getset_stream_info(avb_1722_1_aecp_packet_t *unsafe pkt,
                                          REFERENCE_PARAM(unsigned char, status),
                                          unsigned short command_type,
                                          CLIENT_INTERFACE(avb_interface, i_avb));

unsafe void process_aem_cmd_getset_stream_format(avb_1722_1_aecp_packet_t *unsafe pkt,
                                          REFERENCE_PARAM(unsigned char, status),
                                          unsigned short command_type,
                                          CLIENT_INTERFACE(avb_interface, i_avb));

unsafe void process_aem_cmd_getset_sampling_rate(avb_1722_1_aecp_packet_t *unsafe pkt,
                                          REFERENCE_PARAM(unsigned char, status),
                                          unsigned short command_type,
                                          CLIENT_INTERFACE(avb_interface, i_avb));

unsafe void process_aem_cmd_getset_clock_source(avb_1722_1_aecp_packet_t *unsafe pkt,
                                         REFERENCE_PARAM(unsigned char, status),
                                         unsigned short command_type,
                                         CLIENT_INTERFACE(avb_interface, i_avb));

unsafe void process_aem_cmd_startstop_streaming(avb_1722_1_aecp_packet_t *unsafe pkt,
                                         REFERENCE_PARAM(unsigned char, status),
                                         unsigned short command_type,
                                         CLIENT_INTERFACE(avb_interface, i_avb));

unsafe void process_aem_cmd_get_counters(avb_1722_1_aecp_packet_t *unsafe pkt,
                                         REFERENCE_PARAM(unsigned char, status),
                                         CLIENT_INTERFACE(avb_interface, i_avb));

#endif
