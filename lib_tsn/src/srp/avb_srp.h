// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef _avb_srp_h_
#define _avb_srp_h_
#include <xccompat.h>
#include "xc2compat.h"
#include "avb_srp_pdu.h"
#include "avb_1722_talker.h"
#include "avb_mrp.h"
#include "avb.h"
#include "ethernet.h"

#define AVB_SRP_ETHERTYPE (0x22ea)

#define AVB_SRP_MACADDR { 0x01, 0x80, 0xc2, 0x00, 0x00, 0xe }

typedef struct avb_stream_entry
{
  avb_srp_info_t reservation;
  char listener_present;
  char talker_present;
  char bw_reserved[MRP_NUM_PORTS]; // While the bw_reserved flag is set/not set we do not add/subtract Qav credit
  char reservation_failed;
} avb_stream_entry;

void avb_match_and_join_leave(mrp_attribute_state *unsafe attr, int join);

avb_stream_entry *unsafe srp_add_reservation_entry_stream_id_only(unsigned int stream_id[2]);

int avb_srp_match_stream_id(unsigned streamId[2], avb_srp_info_t **stream);

int avb_add_detected_stream(srp_talker_first_value *fv,
                            unsigned streamId[2],
                             int addr_offset,
                             avb_srp_info_t **stream);


typedef struct srp_stream_state {
  union {
    mrp_attribute_state talker;
    mrp_attribute_state listener;
  } u;
} srp_stream_state;


#ifdef __XC__
extern "C" {
#endif
short avb_srp_create_and_join_talker_advertise_attrs(avb_srp_info_t *reservation);
#ifdef __XC__
}
#endif
void avb_srp_leave_talker_attrs(unsigned int stream_id[2]);
void avb_srp_leave_listener_attrs(unsigned int stream_id[2]);
short avb_srp_join_listener_attrs(unsigned int stream_id[2], short vlan_id);

int srp_cleanup_reservation_entry(mrp_event event, mrp_attribute_state *st);

/* The following functions are called from avb_mrp.c */
mrp_attribute_state *unsafe avb_srp_process_new_attribute_from_packet(int attribute_type,
                                  char *fv,
                                  int num,
                                  int port_num);

int avb_srp_compare_talker_attributes(mrp_attribute_state *a,
                                      mrp_attribute_state *b);

int avb_srp_compare_listener_attributes(mrp_attribute_state *a,
                                        mrp_attribute_state *b);

int avb_srp_encode_message(char *buf,
                          mrp_attribute_state *st,
                          int vector);

int avb_srp_match_talker_advertise(mrp_attribute_state *attr,
                                   char *msg,
                                   int i,
                                   int leave_all,
                                   int failed);

int avb_srp_match_listener(mrp_attribute_state *attr,
                           char *msg,
                           int i,
                           int four_packed_event);

int avb_srp_match_domain(mrp_attribute_state *attr,
                         char *msg,
                         int i);

void avb_srp_map_leave(mrp_attribute_state *attr);

//!@{
//! \name Indications from the MRP state machine
void avb_srp_listener_join_ind(CLIENT_INTERFACE(avb_interface, avb), mrp_attribute_state *attr, int new, int four_packed_event);
void avb_srp_listener_leave_ind(CLIENT_INTERFACE(avb_interface, avb), mrp_attribute_state *attr, int four_packed_event);

void avb_srp_talker_join_ind(mrp_attribute_state *attr, int new);
void avb_srp_talker_leave_ind(mrp_attribute_state *attr);

void avb_srp_domain_join_ind(CLIENT_INTERFACE(avb_interface, avb), mrp_attribute_state *attr, int new);
void avb_srp_domain_leave_ind(CLIENT_INTERFACE(avb_interface, avb), mrp_attribute_state *attr);
//!@}

void srp_domain_init(void);
void srp_domain_join(void);

void srp_store_ethernet_interface(CLIENT_INTERFACE(ethernet_tx_if, i));


#endif // _avb_srp_h_
