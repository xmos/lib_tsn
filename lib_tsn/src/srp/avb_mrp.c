// Copyright (c) 2011-2017, XMOS Ltd, All rights reserved
#include <xs1.h>
#include "avb_mrp.h"
#include "avb_srp.h"
#include "avb_mvrp.h"
#include "avb_mrp_pdu.h"
#include "avb_mvrp_pdu.h"
#include "avb_srp_pdu.h"
#include "misc_timer.h"
#include "ethernet.h"
#include "ethernet_wrappers.h"
#include <string.h>
#include <print.h>
#include "debug_print.h"
#include "avb_mrp_debug_strings.h"


/** \file avb_mrp.c
 *  \brief the core of the MRP protocols
 */

#define MAX_MRP_MSG_SIZE (sizeof(mrp_msg_header) + sizeof(srp_talker_first_value) + 1 /* for event vector */ + sizeof(mrp_msg_footer))

// The size of the send buffer
#ifndef MRP_SEND_BUFFER_SIZE
#define MRP_SEND_BUFFER_SIZE (500)
#endif

//! Lengths of the first values for each attribute type
static int first_value_lengths[MRP_NUM_ATTRIBUTE_TYPES] = FIRST_VALUE_LENGTHS;

//!@{
//! \name MAC addresses for the various protocols
unsigned char mvrp_dest_mac[6] = AVB_MVRP_MACADDR;
unsigned char srp_dest_mac[6] = AVB_SRP_MACADDR;
//!@}

//! Buffer for constructing MRPDUs.  Note: It doesn't necessarily have to be this big,
//! we could always make it shorter and just send more packets.
static char send_buf[MRP_SEND_BUFFER_SIZE];

//! Array of attribute control structures
static mrp_attribute_state attrs[MRP_MAX_ATTRS];

//! when sorting the attributes, this points to the head of the list.  attributes
//! need to be sorted so that they can be merged into vectors in the MRP messages
static mrp_attribute_state *first_attr = &attrs[0];

//! The end of the under-construction MRP packet
static char *send_ptr= &send_buf[0] + sizeof(mrp_ethernet_hdr) + sizeof(mrp_header);

//! The ethertype of the packet under construction - we could probably eliminate this
//! since the information is in the packet anyway
static int current_etype = 0;

//!@{
//! \name Timers for the MRP state machines
static avb_timer periodic_timer[MRP_NUM_PORTS];
static avb_timer joinTimer[MRP_NUM_PORTS];
static avb_timer msrp_leaveall_timer[MRP_NUM_PORTS];
static avb_timer mvrp_leaveall_timer[MRP_NUM_PORTS];
static int msrp_leaveall_active[MRP_NUM_PORTS];
static int mvrp_leaveall_active[MRP_NUM_PORTS];
//!@}

static unsigned i_eth;

void mrp_store_ethernet_interface(CLIENT_INTERFACE(ethernet_tx_if, i)) {
  i_eth = i;
}


void debug_print_applicant_state_change(mrp_attribute_state *st, mrp_event event, int new)
{
  if ((st)->attribute_type == MSRP_TALKER_ADVERTISE || (st)->attribute_type == MSRP_LISTENER || (st)->attribute_type == MSRP_TALKER_FAILED) {
      avb_sink_info_t *sink_info = (avb_sink_info_t *) st->attribute_info;
      int stream_id[2] = {0, 0};

      if (sink_info != NULL) {
        stream_id[0] = sink_info->reservation.stream_id[0];
        stream_id[1] = sink_info->reservation.stream_id[1];
      }

    debug_printf("AP: %s %x:%d:%d:%d\t %s: %s -> %s \n", debug_attribute_type[(st)->attribute_type], stream_id[1], st->port_num, st->here, st->propagated, debug_mrp_event[(event)], debug_mrp_applicant_state[(st)->applicant_state], debug_mrp_applicant_state[new]);
  }
}

void debug_print_registrar_state_change(mrp_attribute_state *st, mrp_event event, int new)
{
  if ((st)->attribute_type == MSRP_TALKER_ADVERTISE || (st)->attribute_type == MSRP_LISTENER) {
    avb_sink_info_t *sink_info = (avb_sink_info_t *) st->attribute_info;
    int stream_id[2] = {0, 0};

    if (sink_info != NULL) {
      stream_id[0] = sink_info->reservation.stream_id[0];
      stream_id[1] = sink_info->reservation.stream_id[1];
    }
    debug_printf("RG: %s %x:%d:%d:%d\t %s: %s -> %s \n", debug_attribute_type[(st)->attribute_type], stream_id[1], st->port_num, st->here, st->propagated, debug_mrp_event[(event)], debug_mrp_registrar_state[(st)->registrar_state], debug_mrp_registrar_state[new]);
  }
}

void debug_print_tx_event(mrp_attribute_state *st, mrp_attribute_event event)
{
  if ((st)->attribute_type == MSRP_TALKER_ADVERTISE || (st)->attribute_type == MSRP_LISTENER) {
    avb_sink_info_t *sink_info = (avb_sink_info_t *) st->attribute_info;
    int stream_id[2] = {0, 0};

    if (sink_info != NULL) {
      stream_id[0] = sink_info->reservation.stream_id[0];
      stream_id[1] = sink_info->reservation.stream_id[1];
    }
    debug_printf("TX: %s %x:%d:%d:%d\t %s \n", debug_attribute_type[(st)->attribute_type], stream_id[1], st->port_num, st->here, st->propagated, debug_attribute_event[(event)]);
  }
}

static void configure_send_buffer(unsigned char* addr, short etype) {
  mrp_ethernet_hdr* hdr = (mrp_ethernet_hdr *) &send_buf[0];
  memcpy(&hdr->dest_addr, addr, 6);
  hdr->ethertype[0] = (etype >> 8);
  hdr->ethertype[1] = etype & 0xff;
  current_etype = etype;
}


unsigned attribute_list_length(mrp_msg_header* hdr)
{
    return (hdr->AttributeListLength[0]<<8) + hdr->AttributeListLength[1];
}

// some MRP based applications do not have attribute list length
// fields.  we build the packets with these fields present (simpler
// to do) then strip them afterwards.  MVRP and MMRP are two
// protocols that do not contain these fields.
static void strip_attribute_list_length_fields()
{
  if (current_etype != AVB_SRP_ETHERTYPE) {
    char *msg = &send_buf[0]+sizeof(mrp_ethernet_hdr)+sizeof(mrp_header);
    char *end = send_ptr;
    while (msg < end && (msg[0]!=0 || msg[1]!=0)) {
      mrp_msg_header* hdr = (mrp_msg_header*)msg;
      char* next = (char*)(hdr+1) + attribute_list_length(hdr);

      for (char* c=(char*)hdr->AttributeListLength; c<end-2; ++c) *c = *(c+2);

      end -= 2;
      msg = next - 2;
    }
    send_ptr = end;
  }
}

// this forces the sending of the current PDU.  this happens when
// that PDU has had all of the attributes that it is going to get,
// or when adding an attribute has filled the PDU up.
static void force_send(CLIENT_INTERFACE(ethernet_if, i_eth), int ifnum)
{
  char *buf = &send_buf[0];
  char *ptr = send_ptr;

  // Strip out attribute length fields for MMRP and MVRP
  strip_attribute_list_length_fields();

  if (ptr != buf+sizeof(mrp_ethernet_hdr)+sizeof(mrp_header)) {

  // Check that the buffer is long enough for a valid ethernet packet
    char *end = ptr + 4;
    if (end < buf + 64) end = buf + 64;

    // Pad with zero if necessary
    for (char *p = ptr;p<end;p++) *p = 0;

    // Transmit
    eth_send_packet(i_eth, buf, end - buf, ifnum);
  }
  send_ptr = buf+sizeof(mrp_ethernet_hdr)+sizeof(mrp_header);
  return;
}

// this considers whether the send a PDU after an attribute has been
// added, but does not if other attributes could potentially be added
// to it.
static void send(CLIENT_INTERFACE(ethernet_if, i_eth), int ifnum)
{
  // Send only when the buffer is full
  if (send_buf + MRP_SEND_BUFFER_SIZE < send_ptr + MAX_MRP_MSG_SIZE + sizeof(mrp_footer)) {
    force_send(i_eth, ifnum);
  }
}


static unsigned int makeTxEvent(mrp_event e, mrp_attribute_state *st, int leave_all)
{
  int firstEvent = 0;

  switch (st->applicant_state)
    {
    case MRP_VP:
    case MRP_AA:
    case MRP_AP:
    case MRP_QA:
    case MRP_QP:
      // sJ
#ifdef MRP_FULL_PARTICIPANT
      if (leave_all && st->applicant_state == MRP_VP) {
        switch (st->registrar_state)
          {
          case MRP_IN:
            mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_IN, firstEvent);
            break;
          default:
            mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_MT, firstEvent);
          break;
          }
      }
      else if (leave_all || st->applicant_state != MRP_QP) {
        switch (st->registrar_state)
          {
          case MRP_IN:
            mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_JOININ, firstEvent);
            break;
          default:
            mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_JOINMT, firstEvent);
            break;
          }
      }
#else
      mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_JOININ, firstEvent);
#endif
      break;
    case MRP_VN:
    case MRP_AN:
      //sN
      mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_NEW, firstEvent);
      break;
    case MRP_LA:
      //sL
      mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_LV, firstEvent);
      break;
#ifdef MRP_FULL_PARTICIPANT
    case MRP_LO:
      //s
      switch (st->registrar_state)
        {
        case MRP_IN:
          mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_IN, firstEvent);
          break;
        default:
          mrp_change_event_state(st, MRP_ATTRIBUTE_EVENT_MT, firstEvent);
          break;
        }
      break;
#endif
    }
  return firstEvent;
}


int static decode_attr_type(int etype, int atype) {
  switch (etype)
    {
    case AVB_SRP_ETHERTYPE:
      switch (atype)
        {
        case AVB_SRP_ATTRIBUTE_TYPE_TALKER_ADVERTISE:
          return MSRP_TALKER_ADVERTISE;
        case AVB_SRP_ATTRIBUTE_TYPE_TALKER_FAILED:
          return MSRP_TALKER_FAILED;
        case AVB_SRP_ATTRIBUTE_TYPE_LISTENER:
          return MSRP_LISTENER;
        case AVB_SRP_ATTRIBUTE_TYPE_DOMAIN:
          return MSRP_DOMAIN_VECTOR;
        }
      break;
    case AVB_MVRP_ETHERTYPE:
      switch (atype)
        {
        case AVB_MVRP_VID_VECTOR_ATTRIBUTE_TYPE:
          return MVRP_VID_VECTOR;
        }
      break;
  }
  return -1;
}


static int encode_attr_type(mrp_attribute_type attr)
{
  switch (attr) {
  case MSRP_TALKER_ADVERTISE:
    return AVB_SRP_ATTRIBUTE_TYPE_TALKER_ADVERTISE;
    break;
  case MSRP_TALKER_FAILED:
    return AVB_SRP_ATTRIBUTE_TYPE_TALKER_FAILED;
    break;
  case MSRP_LISTENER:
    return AVB_SRP_ATTRIBUTE_TYPE_LISTENER;
    break;
  case MSRP_DOMAIN_VECTOR:
    return AVB_SRP_ATTRIBUTE_TYPE_DOMAIN;
    break;
  case MMRP_MAC_VECTOR:
    return AVB_MMRP_MAC_VECTOR_ATTRIBUTE_TYPE;
    break;
  case MVRP_VID_VECTOR:
    return AVB_MVRP_VID_VECTOR_ATTRIBUTE_TYPE;
    break;
  default:
    return 0;
  }
}

static int has_fourpacked_events(mrp_attribute_type attr) {
  return (attr == MSRP_LISTENER) ? 1 : 0;
}

static int encode_three_packed(int event, int i, int vector)
{

  for (int j=0;j<(2-i);j++)
    event *= 6;
  return (vector + event);
}

void mrp_encode_three_packed_event(char *buf,
                                   int event,
                                   mrp_attribute_type attr)
{
  mrp_msg_header *hdr = (mrp_msg_header *) buf;
  mrp_vector_header *vector_hdr = (mrp_vector_header *) (buf + sizeof(mrp_msg_header));
  int num_values = vector_hdr->NumberOfValuesLow;
  int first_value_length =  first_value_lengths[attr];
  char *vector = buf + sizeof(mrp_msg_header) + sizeof(mrp_vector_header) + first_value_length + num_values/3;
  int shift_required = (num_values % 3 == 0);
  unsigned attr_list_length = attribute_list_length(hdr);


  if (shift_required) {
    char *endmark;
    if (send_ptr - vector > 0)
      memmove(vector+1, vector, send_ptr - vector);
    send_ptr++;
    *vector = 0;
    attr_list_length++;
    hton_16(hdr->AttributeListLength, attr_list_length);
    endmark = buf + sizeof(mrp_msg_header) + attr_list_length - 2;
    *endmark = 0;
    *(endmark+1) = 0;
  }

  *vector = encode_three_packed(event, num_values % 3, *vector);
  return;
}


static int encode_four_packed(int event, int i, int vector)
{

  for (int j=0;j<(3-i);j++)
    event *= 4;
  return (vector + event);
}

void mrp_encode_four_packed_event(char *buf,
                                  int event,
                                  mrp_attribute_type attr)
{
  mrp_msg_header *hdr = (mrp_msg_header *) buf;
  mrp_vector_header *vector_hdr = (mrp_vector_header *) (buf + sizeof(mrp_msg_header));
  int num_values = vector_hdr->NumberOfValuesLow;
  int first_value_length =  first_value_lengths[attr];
  char *vector = buf + sizeof(mrp_msg_header) + sizeof(mrp_vector_header) + first_value_length + (num_values+3)/3 + num_values/4 ;
  int shift_required = (num_values % 4 == 0);
  unsigned attr_list_length = attribute_list_length(hdr);



  if (shift_required)  {
    char *endmark;
    if (send_ptr - vector > 0)
      memmove(vector+1, vector, send_ptr - vector);
    *vector = 0;
    attr_list_length++;
    send_ptr++;
    hton_16(hdr->AttributeListLength, attr_list_length);
    endmark = buf + sizeof(mrp_msg_header) + attr_list_length - 2;
    *endmark = 0;
    *(endmark+1) = 0;
  }

  *vector = encode_four_packed(event, num_values % 4, *vector);
  return;
}

// Send an empty leave all message
// This may be merged later with a redeclaration if we have
// declaration for this attribute
static void create_empty_msg(mrp_attribute_type attr, int leave_all) {
  mrp_msg_header *hdr = (mrp_msg_header *) send_ptr;
  mrp_vector_header *vector_hdr = (mrp_vector_header *) (send_ptr + sizeof(mrp_msg_header));
  int hdr_length = sizeof(mrp_msg_header);
  int vector_length = 0;
  int first_value_length =  first_value_lengths[attr];
  int attr_list_length = first_value_length + sizeof(mrp_vector_header)  + vector_length + sizeof(mrp_footer);
  int msg_length = hdr_length + attr_list_length;

  // clear message
  memset((char *)hdr, 0, msg_length);

  // Set the relevant fields
  hdr->AttributeType = encode_attr_type(attr);
  hdr->AttributeLength = first_value_length;
  hton_16(hdr->AttributeListLength, attr_list_length);

  vector_hdr->LeaveAllEventNumberOfValuesHigh = leave_all << 5;
  vector_hdr->NumberOfValuesLow = 0;

  send_ptr += msg_length;
}


static int encode_msg(char *msg, mrp_attribute_state* st, int vector, unsigned int port_num)
{
  switch (st->attribute_type)
  {
    case MSRP_TALKER_ADVERTISE:
    case MSRP_TALKER_FAILED:
    case MSRP_LISTENER:
    case MSRP_DOMAIN_VECTOR:
      return avb_srp_encode_message(msg, st, vector);
      break;
    case MVRP_VID_VECTOR:
      return avb_mvrp_merge_message(msg, st, vector);
      break;
  }

  return 0;
}

static void doTx(mrp_attribute_state *st,
                 int vector,
                 unsigned int port_num)
{
  int merged = 0;
  char *msg = &send_buf[0]+sizeof(mrp_ethernet_hdr)+sizeof(mrp_header);
  char *end = send_ptr;

  while (!merged &&
         msg < end &&
         (*msg != 0 || *(msg+1) != 0)) {
    mrp_msg_header *hdr = (mrp_msg_header *) &msg[0];

    merged = encode_msg(msg, st, vector, port_num);

    msg = msg + sizeof(mrp_msg_header) + attribute_list_length(hdr);
  }

  int port_to_transmit = st->port_num;

  if (!merged) {
    if (port_num == port_to_transmit)
    {
      create_empty_msg(st->attribute_type, 0);
      (void) encode_msg(msg, st, vector, port_num);
    }
  }

  if (MRP_DEBUG_ATTR_EGRESS)
  {
    if ((st)->attribute_type == MSRP_TALKER_ADVERTISE || (st)->attribute_type == MSRP_LISTENER) {
      avb_sink_info_t *sink_info = (avb_sink_info_t *) st->attribute_info;
      int stream_id[2] = {0, 0};

      if (sink_info != NULL) {
        stream_id[0] = sink_info->reservation.stream_id[0];
        stream_id[1] = sink_info->reservation.stream_id[1];
      }
      debug_printf("TX: %s %s, stream %x:%x\n", debug_attribute_type[(st)->attribute_type], debug_attribute_event[(vector)], stream_id[0], stream_id[1]);
    }
  }
  send(i_eth, port_to_transmit);

  if (st->remove_after_next_tx) {
    mrp_change_applicant_state(st, MRP_EVENT_DUMMY, MRP_UNUSED);
    st->remove_after_next_tx = 0;
  }
}

static void mrp_update_state(mrp_event e, mrp_attribute_state *st, int four_packed_event, unsigned int port_num)
{
#ifdef MRP_FULL_PARTICIPANT
  // Registrar state machine
  switch (e)
    {
    case MRP_EVENT_BEGIN:
      mrp_change_registrar_state(st, e, MRP_MT);
      break;
    case MRP_EVENT_RECEIVE_NEW:
      if (st->registrar_state == MRP_LV) {
        stop_avb_timer(&st->leaveTimer);
      }
      mrp_change_registrar_state(st, e, MRP_IN);
      st->pending_indications |= PENDING_JOIN_NEW;
      st->four_vector_parameter = four_packed_event;
      break;
    case MRP_EVENT_RECEIVE_JOININ:
    case MRP_EVENT_RECEIVE_JOINMT:
      if (st->registrar_state == MRP_LV) {
        stop_avb_timer(&st->leaveTimer);
      }
      if (st->registrar_state == MRP_MT ||
          ((st->four_vector_parameter == AVB_SRP_FOUR_PACKED_EVENT_ASKING_FAILED) &&
            (four_packed_event == AVB_SRP_FOUR_PACKED_EVENT_READY))) {
          st->pending_indications |= PENDING_JOIN;
          st->four_vector_parameter = four_packed_event;
      }
      mrp_change_registrar_state(st, e, MRP_IN);
      break;
    case MRP_EVENT_RECEIVE_LEAVE:
    case MRP_EVENT_RECEIVE_LEAVE_ALL:
    case MRP_EVENT_TX_LEAVE_ALL:
    case MRP_EVENT_REDECLARE:
      if (e == MRP_EVENT_RECEIVE_LEAVE_ALL) {
        if (st->attribute_type == MVRP_VID_VECTOR) {
          start_avb_timer(&mvrp_leaveall_timer[port_num], MRP_LEAVEALL_TIMER_PERIOD_CENTISECONDS / MRP_LEAVEALL_TIMER_MULTIPLIER);
          mvrp_leaveall_active[port_num] = 0;
        } else {
          start_avb_timer(&msrp_leaveall_timer[port_num], MRP_LEAVEALL_TIMER_PERIOD_CENTISECONDS / MRP_LEAVEALL_TIMER_MULTIPLIER);
          msrp_leaveall_active[port_num] = 0;
        }
      }
      if (st->registrar_state == MRP_IN) {
        start_avb_timer(&st->leaveTimer, MRP_LEAVETIMER_PERIOD_CENTISECONDS);
        mrp_change_registrar_state(st, e, MRP_LV);
      }
      break;
    case MRP_EVENT_LEAVETIMER:
    case MRP_EVENT_FLUSH:
      if (st->registrar_state == MRP_LV) {
        // Lv
        st->pending_indications |= PENDING_LEAVE;
        st->four_vector_parameter = four_packed_event;
      }
      mrp_change_registrar_state(st, e, MRP_MT);
      break;
    default:
      break;
    }
#endif

  // Applicant state machine
  switch (e)
    {
    case MRP_EVENT_BEGIN:
      mrp_change_applicant_state(st, e, MRP_VO);
      break;
    case MRP_EVENT_NEW:
      mrp_change_applicant_state(st, e, MRP_VN);
      break;
    case MRP_EVENT_JOIN:
      switch (st->applicant_state)
        {
        case MRP_VO:
#ifdef MRP_FULL_PARTICIPANT
        case MRP_LO:
#endif
          mrp_change_applicant_state(st, e, MRP_VP);
          break;
        case MRP_LA:
          mrp_change_applicant_state(st, e, MRP_AA);
          break;
        case MRP_AO:
          mrp_change_applicant_state(st, e, MRP_AP);
          break;
        case MRP_QO:
          mrp_change_applicant_state(st, e, MRP_QP);
          break;
        }
      break;
    case MRP_EVENT_LV:
      switch (st->applicant_state)
        {
        case MRP_QP:
          mrp_change_applicant_state(st, e, MRP_QO);
          break;
        case MRP_AP:
          mrp_change_applicant_state(st, e, MRP_AO);
          break;
        case MRP_VP:
          mrp_change_applicant_state(st, e, MRP_VO);
          break;
        case MRP_VN:
        case MRP_AN:
        case MRP_AA:
        case MRP_QA:
          mrp_change_applicant_state(st, e, MRP_LA);
          break;
        }
      break;
    case MRP_EVENT_RECEIVE_JOININ:
      switch (st->applicant_state)
        {
        case MRP_AA:
          mrp_change_applicant_state(st, e, MRP_QA);
          break;
        case MRP_AO:
          mrp_change_applicant_state(st, e, MRP_QO);
          break;
        case MRP_AP:
          mrp_change_applicant_state(st, e, MRP_QP);
          break;
        }
    case MRP_EVENT_RECEIVE_IN:
      switch (st->applicant_state)
      {
      case MRP_AA:
        mrp_change_applicant_state(st, e, MRP_QA);
        break;
      }
    case MRP_EVENT_RECEIVE_JOINMT:
    case MRP_EVENT_RECEIVE_MT:
      switch (st->applicant_state)
        {
        case MRP_QA:
          mrp_change_applicant_state(st, e, MRP_AA);
          break;
        case MRP_QO:
          mrp_change_applicant_state(st, e, MRP_AO);
          break;
        case MRP_QP:
          mrp_change_applicant_state(st, e, MRP_AP);
          break;
#ifdef MRP_FULL_PARTICIPANT
        case MRP_LO:
          mrp_change_applicant_state(st, e, MRP_VO);
          break;
#endif
        }
      break;
    case MRP_EVENT_RECEIVE_LEAVE:
    case MRP_EVENT_RECEIVE_LEAVE_ALL:
    case MRP_EVENT_REDECLARE:
      switch (st->applicant_state)
        {
        case MRP_VO:
        case MRP_AO:
        case MRP_QO:
#ifdef MRP_FULL_PARTICIPANT
          mrp_change_applicant_state(st, e, MRP_LO);
#else
          mrp_change_applicant_state(st, e, MRP_VO);
#endif
          break;
        case MRP_AN:
          mrp_change_applicant_state(st, e, MRP_VN);
          break;
        case MRP_AA:
        case MRP_QA:
        case MRP_AP:
        case MRP_QP:
          mrp_change_applicant_state(st, e, MRP_VP);
          break;
        }
      break;
    case MRP_EVENT_PERIODIC:
      switch (st->applicant_state)
        {
        case MRP_QA:
          mrp_change_applicant_state(st, e, MRP_AA);
          break;
        case MRP_QP:
          mrp_change_applicant_state(st, e, MRP_AP);
          break;
        }
      break;
    case MRP_EVENT_TX:
      switch (st->applicant_state)
        {
        case MRP_VP:
        case MRP_VN:
        case MRP_AN:
        case MRP_AA:
        case MRP_LA:
        case MRP_AP:
#ifdef MRP_FULL_PARTICIPANT
        case MRP_LO:
#endif
          {
          int vector = makeTxEvent(e, st, 0);
          doTx(st, vector, port_num);
          break;
          }
        }
      switch (st->applicant_state)
        {
        case MRP_VP:
          mrp_change_applicant_state(st, e, MRP_AA);
          break;
        case MRP_VN:
          mrp_change_applicant_state(st, e, MRP_AN);
          break;
        case MRP_AN:
          if (st->registrar_state != MRP_IN) {
            mrp_change_applicant_state(st, e, MRP_AA);
            break;
          }
        case MRP_AA:
        case MRP_AP:
          mrp_change_applicant_state(st, e, MRP_QA);
          break;
        case MRP_LA:
#ifdef MRP_FULL_PARTICIPANT
        case MRP_LO:
#endif
          mrp_change_applicant_state(st, e, MRP_VO);
          break;
        }
      break;
#ifdef MRP_FULL_PARTICIPANT
    case MRP_EVENT_TX_LEAVE_ALL: {
      switch (st->applicant_state)
        {
        case MRP_VP:
        case MRP_VN:
        case MRP_AN:
        case MRP_AA:
        case MRP_LA:
        case MRP_QA:
        case MRP_AP:
        case MRP_QP:
          {
          int vector = makeTxEvent(e, st, 1);
          doTx(st, vector, port_num);
        }
        }
      switch (st->applicant_state)
        {
        case MRP_VO:
        case MRP_LA:
        case MRP_AO:
        case MRP_QO:
          mrp_change_applicant_state(st, e, MRP_LO);
          break;
        case MRP_VN:
          mrp_change_applicant_state(st, e, MRP_AN);
          break;
        case MRP_AN:
        case MRP_AA:
        case MRP_AP:
        case MRP_QP:
          mrp_change_applicant_state(st, e, MRP_QA);
          break;
        }
      }
      break;
#endif
    default:
      break;
    }
}

void mrp_debug_dump_attrs(void)
{
#if 0
  debug_printf("port_num | type                   | disabled | here | propagated | stream_id\n"
                "---------+------------------------+----------+------+------------+----------\n");
  for (int i=0;i<MRP_MAX_ATTRS;i++) {

    if (attrs[i].applicant_state != MRP_UNUSED) {
      avb_sink_info_t *sink_info = (avb_sink_info_t *) attrs[i].attribute_info;
      int stream_id[2] = {0, 0};
      char attr_string[24];

      if (sink_info != NULL) {
        stream_id[0] = sink_info->reservation.stream_id[0];
        stream_id[1] = sink_info->reservation.stream_id[1];
      }

      memset(attr_string, 0x20, 24);
      attr_string[23] = '\0';
      strncpy(attr_string, debug_attribute_type[attrs[i].attribute_type],strlen(debug_attribute_type[attrs[i].attribute_type]));

      debug_printf("%d        | %s| %d        | %d    | %d          | %x:%x\n",
        attrs[i].port_num, attr_string, attrs[i].applicant_state == MRP_DISABLED, attrs[i].here, attrs[i].propagated, stream_id[0], stream_id[1]);

    }
  }
#endif
}

void mrp_attribute_init(mrp_attribute_state *st,
                        mrp_attribute_type t,
                        unsigned int port_num,
                        unsigned int here,
                        void *info)
{
  memset(st, sizeof(mrp_attribute_state), 0);
  st->attribute_type = t;
  st->attribute_info = info;
  st->port_num = port_num;
  st->propagated = 0;
  st->here = here;
  return;
}

void mrp_mad_begin(mrp_attribute_state *st)
{
#ifdef MRP_FULL_PARTICIPANT
  init_avb_timer(&st->leaveTimer, 1);
#endif
  mrp_update_state(MRP_EVENT_BEGIN, st, 0, st->port_num);
}

void mrp_mad_join(mrp_attribute_state *st, int new)
{
#if MRP_DEBUG_STATE_CHANGE
  if (st->attribute_type == MSRP_LISTENER) debug_printf("Listener MAD_Join\n");
  else if (st->attribute_type == MSRP_TALKER_ADVERTISE) debug_printf("Talker MAD_Join\n");


  if (st->attribute_type == MSRP_LISTENER || st->attribute_type == MSRP_TALKER_ADVERTISE) {
    avb_sink_info_t *sink_info = (avb_sink_info_t *) st->attribute_info;
    int stream_id[2] = {0, 0};

    if (sink_info != NULL) {
      stream_id[0] = sink_info->reservation.stream_id[0];
      stream_id[1] = sink_info->reservation.stream_id[1];
    }
    debug_printf(" %x:%x, Port:%d, Here:%d, propagated:%d\n", stream_id[0], stream_id[1], st->port_num, st->here, st->propagated);
  }
#endif

  st->remove_after_next_tx = 0;

  if (new) {
    mrp_update_state(MRP_EVENT_NEW, st, 0, st->port_num);
  } else {
    mrp_update_state(MRP_EVENT_JOIN, st, 0, st->port_num);
  }
}

void mrp_mad_leave(mrp_attribute_state *st)
{
  if (st->attribute_type == MSRP_LISTENER) debug_printf("Listener MAD_Leave\n");
  else if (st->attribute_type == MSRP_TALKER_ADVERTISE) debug_printf("Talker MAD_Leave\n");
  mrp_update_state(MRP_EVENT_LV, st, 0, st->port_num);
}

void mrp_init(char *macaddr)
{
  for (int i=0;i<6;i++) {
    mrp_ethernet_hdr *hdr = (mrp_ethernet_hdr *) &send_buf[0];
    hdr->src_addr[i] = macaddr[i];
  }

  for (int i=0;i<MRP_MAX_ATTRS;i++) {
    attrs[i].applicant_state = MRP_UNUSED;
    if (i != MRP_MAX_ATTRS-1)
      attrs[i].next = &attrs[i+1];
    else
      attrs[i].next = NULL;
  }
  first_attr = &attrs[0];

  for (int i=0; i < MRP_NUM_PORTS; i++)
  {
    init_avb_timer(&periodic_timer[i], MRP_PERIODIC_TIMER_MULTIPLIER);
    start_avb_timer(&periodic_timer[i], MRP_PERIODIC_TIMER_PERIOD_CENTISECONDS / MRP_PERIODIC_TIMER_MULTIPLIER);

    init_avb_timer(&joinTimer[i], 1);
    start_avb_timer(&joinTimer[i], MRP_JOINTIMER_PERIOD_CENTISECONDS);


  #ifdef MRP_FULL_PARTICIPANT
    init_avb_timer(&msrp_leaveall_timer[i], MRP_LEAVEALL_TIMER_MULTIPLIER);
    start_avb_timer(&msrp_leaveall_timer[i], MRP_LEAVEALL_TIMER_PERIOD_CENTISECONDS / MRP_LEAVEALL_TIMER_MULTIPLIER);
    init_avb_timer(&mvrp_leaveall_timer[i], MRP_LEAVEALL_TIMER_MULTIPLIER);
    start_avb_timer(&mvrp_leaveall_timer[i], MRP_LEAVEALL_TIMER_PERIOD_CENTISECONDS / MRP_LEAVEALL_TIMER_MULTIPLIER);
    msrp_leaveall_active[i] = 0;
    mvrp_leaveall_active[i] = 0;
  #endif
  }

}

static int compare_attr(mrp_attribute_state *a,
                        mrp_attribute_state *b)
{
  if (a->applicant_state == MRP_UNUSED) {
    if (b->applicant_state == MRP_UNUSED)
      return (a < b);
    else
      return 0;
  }
  else if (b->applicant_state == MRP_UNUSED) {
    return 1;
  }


  if (a->applicant_state == MRP_DISABLED) {
    if (b->applicant_state == MRP_DISABLED)
      return (a < b);
    else
      return 0;
  }
  else if (b->applicant_state == MRP_DISABLED) {
    return 1;
  }


  if (a->attribute_type != b->attribute_type)
    return (a->attribute_type < b->attribute_type);

  switch (a->attribute_type)
    {
    case MSRP_TALKER_ADVERTISE:
      return avb_srp_compare_talker_attributes(a,b);
      break;
    case MSRP_LISTENER:
      return avb_srp_compare_listener_attributes(a,b);
      break;
    default:
      break;
    }
  return (a<b);
}

mrp_attribute_state *mrp_get_attr(void)
{
  for (int i=0;i<MRP_MAX_ATTRS;i++) {
    if (attrs[i].applicant_state == MRP_UNUSED) {
      attrs[i].applicant_state = MRP_DISABLED;
      return &attrs[i];
    }
  }
  return NULL;
}

static void sort_attrs()
{
  mrp_attribute_state *to_insert=NULL;
  mrp_attribute_state *attr=NULL;
  mrp_attribute_state *prev=NULL;

  // This sorting algorithm is designed to work best for lists
  // we already expect to be sorted (which is generally the case here)

  // Get items to insert back in
  attr = first_attr;
  while (attr != NULL) {
    mrp_attribute_state *next = attr->next;
    if (next != NULL) {
      if (!compare_attr(attr, next)) {
        if (prev)
          prev->next = next;
        else
          first_attr = next;

        attr->next = to_insert;
        to_insert = attr;
      }
      else
        prev = attr;
    }
    attr = next;
  }

  // Inser them back in
  attr = to_insert;
  while (attr != NULL) {
    mrp_attribute_state *next = attr->next;
    mrp_attribute_state *ins = first_attr;

    if (compare_attr(attr, ins)) {
      attr->next = ins;
      first_attr = attr;
    }
    else {
      while (ins != NULL) {
        mrp_attribute_state *ins_next = ins->next;
        if (ins_next == NULL ||
            (compare_attr(ins, attr) && compare_attr(attr, ins_next))) {
          attr->next = ins->next;
          ins->next = attr;
          ins_next = NULL;
        }
        ins = ins_next;
      }
    }
    attr = next;
  }


}

static void global_event(mrp_event e, unsigned int port_num) {
  mrp_attribute_state *attr = first_attr;

  while (attr != NULL) {
    if (attr->applicant_state != MRP_DISABLED &&
        attr->applicant_state != MRP_UNUSED &&
        attr->port_num == port_num) {

      if (e != MRP_EVENT_PERIODIC || attr->attribute_type == MVRP_VID_VECTOR)
      {
        mrp_update_state(e, attr, 0, port_num);
      }
    }
    attr = attr->next;
  }

}

static void attribute_type_event(mrp_attribute_type atype, mrp_event e, unsigned int port_num) {
  mrp_attribute_state *attr = first_attr;

  while (attr != NULL) {
    if (attr->applicant_state != MRP_DISABLED &&
        attr->applicant_state != MRP_UNUSED &&
        attr->attribute_type == atype &&
        attr->port_num == port_num) {

          mrp_update_state(e, attr, 0, port_num);
        }
    attr = attr->next;
  }
}

static void send_join_indication(CLIENT_INTERFACE(avb_interface, avb), mrp_attribute_state *st, int new, int four_packed_event)
{
  switch (st->attribute_type)
  {
  case MSRP_TALKER_ADVERTISE:
    avb_srp_talker_join_ind(st, new);
    break;
  case MSRP_TALKER_FAILED:
    break;
  case MSRP_LISTENER:
    avb_srp_listener_join_ind(avb, st, new, four_packed_event);
    break;
  case MSRP_DOMAIN_VECTOR:
    avb_srp_domain_join_ind(avb, st, new);
    break;
  case MVRP_VID_VECTOR:
    avb_mvrp_vid_vector_join_ind(st, new);
    break;
  }
}

static void send_leave_indication(CLIENT_INTERFACE(avb_interface, avb), mrp_attribute_state *st, int four_packed_event)
{
  switch (st->attribute_type)
  {
  case MSRP_TALKER_ADVERTISE:
    avb_srp_talker_leave_ind(st);
    break;
  case MSRP_TALKER_FAILED:
    break;
  case MSRP_LISTENER:
    avb_srp_listener_leave_ind(avb, st, four_packed_event);
    break;
  case MSRP_DOMAIN_VECTOR:
    avb_srp_domain_leave_ind(avb, st);
    break;
  case MVRP_VID_VECTOR:
    avb_mvrp_vid_vector_leave_ind(st);
    break;
  }
}

static void msrp_types_event(mrp_event e, unsigned int port_num) {
  attribute_type_event(MSRP_TALKER_ADVERTISE, e, port_num);
  attribute_type_event(MSRP_TALKER_FAILED, e, port_num);
  attribute_type_event(MSRP_LISTENER, e, port_num);
  attribute_type_event(MSRP_DOMAIN_VECTOR, e, port_num);
}

extern unsigned int srp_domain_boundary_port[MRP_NUM_PORTS];

void mrp_periodic(CLIENT_INTERFACE(avb_interface, avb))
{
  for (int i=0; i < MRP_NUM_PORTS; i++)
  {
    if (avb_timer_expired(&periodic_timer[i]))
    {
      global_event(MRP_EVENT_PERIODIC, i);
      start_avb_timer(&periodic_timer[i], MRP_PERIODIC_TIMER_PERIOD_CENTISECONDS / MRP_PERIODIC_TIMER_MULTIPLIER);
    }

  #ifdef MRP_FULL_PARTICIPANT
    int msrp_leaveall_timer_expired = avb_timer_expired(&msrp_leaveall_timer[i]);
    if (msrp_leaveall_timer_expired) {
      msrp_types_event(MRP_EVENT_RECEIVE_LEAVE_ALL, i);

      msrp_leaveall_active[i] = 1;
      start_avb_timer(&msrp_leaveall_timer[i], MRP_LEAVEALL_TIMER_PERIOD_CENTISECONDS / MRP_LEAVEALL_TIMER_MULTIPLIER);
    }

    int mvrp_leaveall_timer_expired = avb_timer_expired(&mvrp_leaveall_timer[i]);
    if (mvrp_leaveall_timer_expired) {
      attribute_type_event(MVRP_VID_VECTOR, MRP_EVENT_RECEIVE_LEAVE_ALL, i);
      mvrp_leaveall_active[i] = 1;
      start_avb_timer(&mvrp_leaveall_timer[i], MRP_LEAVEALL_TIMER_PERIOD_CENTISECONDS / MRP_LEAVEALL_TIMER_MULTIPLIER);
    }
  #endif

    if (avb_timer_expired(&joinTimer[i]))
    {
      start_avb_timer(&joinTimer[i], MRP_JOINTIMER_PERIOD_CENTISECONDS);
      sort_attrs();

      mrp_event tx_event = mvrp_leaveall_active[i] ? MRP_EVENT_TX_LEAVE_ALL : MRP_EVENT_TX;
      configure_send_buffer(mvrp_dest_mac, AVB_MVRP_ETHERTYPE);
      if (mvrp_leaveall_active[i])
      {
        create_empty_msg(MVRP_VID_VECTOR, 1); send(i_eth, i);
        mvrp_leaveall_active[i] = 0;
      }
      attribute_type_event(MVRP_VID_VECTOR, tx_event, i);
      force_send(i_eth, i);

      tx_event = msrp_leaveall_active[i] ? MRP_EVENT_TX_LEAVE_ALL : MRP_EVENT_TX;

      configure_send_buffer(srp_dest_mac, AVB_SRP_ETHERTYPE);
      if (msrp_leaveall_active[i])
      {
        create_empty_msg(MSRP_TALKER_ADVERTISE, 1);  send(i_eth, i);
        create_empty_msg(MSRP_TALKER_FAILED, 1);  send(i_eth, i);
        create_empty_msg(MSRP_LISTENER, 1);  send(i_eth, i);
        create_empty_msg(MSRP_DOMAIN_VECTOR, 1);  send(i_eth, i);
        msrp_leaveall_active[i] = 0;
      }
      msrp_types_event(tx_event, i);
      force_send(i_eth, i);
    }

    for (int j=0;j<MRP_MAX_ATTRS;j++)
    {
      if (attrs[j].applicant_state == MRP_UNUSED) continue;
      if (attrs[j].port_num != i) continue;

      if (attrs[j].pending_indications != 0)
      {
        if ((attrs[j].pending_indications & PENDING_JOIN_NEW) != 0)
        {
          send_join_indication(avb, &attrs[j], 1, attrs[j].four_vector_parameter);
        }
        if ((attrs[j].pending_indications & PENDING_JOIN) != 0)
        {
          send_join_indication(avb, &attrs[j], 0, attrs[j].four_vector_parameter);
        }
        if ((attrs[j].pending_indications & PENDING_LEAVE) != 0)
        {
          send_leave_indication(avb, &attrs[j], attrs[j].four_vector_parameter);
        }
        attrs[j].pending_indications = 0;
      }

      avb_srp_info_t *reservation = (avb_srp_info_t *) attrs[j].attribute_info;

      // mrp_mad_join() is supposed to handle DECLARATIONS that an XMOS talker has made. 
      // Unfortunately it runs this code for registrations as well and the join will turn 
      // the registration into a declaration. That is bad behavior and can result in 
      // listener only devices declaring themselves as talkers.      
      // the work around is to make sure that mrp_mad_join() is only called for attributes 
      // that are declaring.
      if (attrs[j].applicant_state == MRP_VP ||
          attrs[j].applicant_state == MRP_VN ||
          attrs[j].applicant_state == MRP_AN ||
          attrs[j].applicant_state == MRP_AA |
          attrs[j].applicant_state == MRP_QA ||
          attrs[j].applicant_state == MRP_LA ||
          attrs[j].applicant_state == MRP_AP)
      {
        if ((attrs[j].attribute_type == MSRP_TALKER_ADVERTISE) && srp_domain_boundary_port[i]) 
        {
          debug_printf("Talker Advertise -> Failed for stream %x%x\n", reservation->stream_id[0], reservation->stream_id[1]);
          attrs[j].attribute_type = MSRP_TALKER_FAILED;
          
          if (reservation) 
          {
            avb_stream_entry *stream_info = attrs[j].attribute_info;
            stream_info->talker_present = 0;
            reservation->failure_code = 8;
            for (int i=0; i < 8; i++) 
            {
              mrp_ethernet_hdr *hdr = (mrp_ethernet_hdr *) &send_buf[0];
              if (i < 2) 
              {
                reservation->failure_bridge_id[i] = 0;
              } 
              else 
              {
                reservation->failure_bridge_id[i] = hdr->src_addr[i];
              }
            }
          }
          if (attrs[j].here)
            mrp_mad_join(&attrs[j], 1);
        }
        else if ((attrs[j].attribute_type == MSRP_TALKER_FAILED) &&
                  !srp_domain_boundary_port[i] &&
                  reservation && reservation->failure_code == 8
                ) 
        {
          attrs[j].attribute_type = MSRP_TALKER_ADVERTISE;
          avb_stream_entry *stream_info = attrs[j].attribute_info;
          stream_info->talker_present = 1;
          debug_printf("Talker Failed -> Advertise for stream %x%x\n", reservation->stream_id[0], reservation->stream_id[1]);
          if (attrs[j].here)
            mrp_mad_join(&attrs[j], 1);
        }
      }      

  #ifdef MRP_FULL_PARTICIPANT
      if (avb_timer_expired(&attrs[j].leaveTimer))
      {
        mrp_update_state(MRP_EVENT_LEAVETIMER, &attrs[j], 0, i);
      }
  #endif
    }
  }
  return;
}


static void mrp_in(int three_packed_event, int four_packed_event, mrp_attribute_state *st, unsigned int port_num)
{
  switch (three_packed_event)
    {
    case MRP_ATTRIBUTE_EVENT_NEW:
      mrp_update_state(MRP_EVENT_RECEIVE_NEW, st, four_packed_event, port_num);
      break;
    case MRP_ATTRIBUTE_EVENT_JOININ:
      mrp_update_state(MRP_EVENT_RECEIVE_JOININ, st, four_packed_event, port_num);
      break;
    case MRP_ATTRIBUTE_EVENT_IN:
      mrp_update_state(MRP_EVENT_RECEIVE_IN, st, four_packed_event, port_num);
      break;
    case MRP_ATTRIBUTE_EVENT_JOINMT:
      mrp_update_state(MRP_EVENT_RECEIVE_JOINMT, st, four_packed_event, port_num);
      break;
    case MRP_ATTRIBUTE_EVENT_MT:
      mrp_update_state(MRP_EVENT_RECEIVE_MT, st, four_packed_event, port_num);
      break;
    case MRP_ATTRIBUTE_EVENT_LV:
      mrp_update_state(MRP_EVENT_RECEIVE_LEAVE, st, four_packed_event, port_num);
      break;
  }
}

int mrp_is_observer(mrp_attribute_state *st)
{
  switch (st->applicant_state)
    {
    case MRP_VO:
    case MRP_AO:
    case MRP_QO:
      return 1;
    default:
      return 0;
    }
}

mrp_attribute_state *mrp_match_type_non_prop_attribute(int attr_type, unsigned stream_id[2], int port_num) {
  for (int j=0;j<MRP_MAX_ATTRS;j++) {
    if (attrs[j].applicant_state == MRP_UNUSED || attrs[j].applicant_state == MRP_DISABLED) {
      continue;
    }
    if (attr_type == attrs[j].attribute_type &&
        !attrs[j].propagated &&
        (port_num == -1 || attrs[j].port_num == port_num))
    {
      avb_srp_info_t *reservation = (avb_srp_info_t *) attrs[j].attribute_info;

      if (reservation == NULL) continue;

      if (reservation->stream_id[0] == stream_id[0] &&
          reservation->stream_id[1] == stream_id[1])
      {
          return &attrs[j];
      }
    }
  }
  return 0;
}


mrp_attribute_state *mrp_match_attr_by_stream_and_type(mrp_attribute_state *attr, int opposite_port, int match_disabled)
{
  for (int j=0;j<MRP_MAX_ATTRS;j++) {
    if (attrs[j].applicant_state == MRP_UNUSED || (!match_disabled && attrs[j].applicant_state == MRP_DISABLED)) {
      continue;
    }
    if ((opposite_port && (attr->port_num != attrs[j].port_num)) ||
        (!opposite_port && (attr->port_num == attrs[j].port_num)))
    {
      if ((attr->attribute_type == attrs[j].attribute_type) ||
          ((attr->attribute_type == MSRP_TALKER_ADVERTISE) && (attrs[j].attribute_type == MSRP_TALKER_FAILED)) ||
          ((attr->attribute_type == MSRP_TALKER_FAILED) && (attrs[j].attribute_type == MSRP_TALKER_ADVERTISE)))
      {
        avb_sink_info_t *sink_info = (avb_sink_info_t *) attr->attribute_info;
        avb_source_info_t *source_info = (avb_source_info_t *) attrs[j].attribute_info;

        if (sink_info == NULL || source_info == NULL) continue;

        if (sink_info->reservation.stream_id[0] == source_info->reservation.stream_id[0] &&
            sink_info->reservation.stream_id[1] == source_info->reservation.stream_id[1])
        {
            return &attrs[j];
        }
      }
    }
  }
  return 0;
}

int mrp_match_multiple_attrs_by_stream_and_type(mrp_attribute_state *attr, int opposite_port)
{
  int matches = 0;

  for (int j=0;j<MRP_MAX_ATTRS;j++) {
    if (attrs[j].applicant_state == MRP_UNUSED || attrs[j].applicant_state == MRP_DISABLED) {
      continue;
    }
    if (attr->attribute_type == attrs[j].attribute_type)
    {
      avb_sink_info_t *sink_info = (avb_sink_info_t *) attr->attribute_info;
      avb_source_info_t *source_info = (avb_source_info_t *) attrs[j].attribute_info;

      if ((opposite_port && (attr->port_num != attrs[j].port_num)) ||
          (!opposite_port && (attr->port_num == attrs[j].port_num))) {

        if (sink_info == NULL || source_info == NULL) continue;

        if (sink_info->reservation.stream_id[0] == source_info->reservation.stream_id[0] &&
            sink_info->reservation.stream_id[1] == source_info->reservation.stream_id[1])
        {
          matches++;
          if (matches == 2)
          {
            return 1;
          }
        }
      }
    }
  }
  return 0;
}


mrp_attribute_state *mrp_match_attribute_pair_by_stream_id(mrp_attribute_state *attr, int opposite_port, int match_disabled)
{
  for (int j=0;j<MRP_MAX_ATTRS;j++) {
    if (attrs[j].applicant_state == MRP_UNUSED || (!match_disabled && attrs[j].applicant_state == MRP_DISABLED)) {
      continue;
    }
    if ((opposite_port && (attr->port_num != attrs[j].port_num)) ||
        (!opposite_port && (attr->port_num == attrs[j].port_num)))
    {
      if (((attr->attribute_type == MSRP_TALKER_ADVERTISE || attr->attribute_type == MSRP_TALKER_FAILED) &&
            attrs[j].attribute_type == MSRP_LISTENER) ||
          (attr->attribute_type == MSRP_LISTENER &&
          (attrs[j].attribute_type == MSRP_TALKER_ADVERTISE || attrs[j].attribute_type == MSRP_TALKER_FAILED)))
      {
        avb_sink_info_t *sink_info = (avb_sink_info_t *) attr->attribute_info;
        avb_source_info_t *source_info = (avb_source_info_t *) attrs[j].attribute_info;

        if (sink_info == NULL || source_info == NULL) continue;


        if (sink_info->reservation.stream_id[0] == source_info->reservation.stream_id[0] &&
            sink_info->reservation.stream_id[1] == source_info->reservation.stream_id[1])
        {
          return &attrs[j];
        }
      }
    }
  }
  return 0;
}

static int match_attribute_of_same_type(mrp_attribute_type attr_type,
              mrp_attribute_state *attr,
              char *msg,
              int i,
              int three_packed_event,
              int four_packed_event,
              unsigned int port_num,
              int leave_all)
{
  if (attr->applicant_state == MRP_UNUSED ||
      attr->applicant_state == MRP_DISABLED)
    return 0;

  if (attr->port_num != port_num)
    return 0;


  if ((attr->attribute_type <= MSRP_TALKER_FAILED) && (attr_type <= MSRP_TALKER_FAILED)) {
    // Continue, match Talker Advertise and Failed as the same attribute type
  }
  else if (attr->attribute_type != attr_type) {
    return 0;
  }

  switch (attr_type) {
  case MSRP_TALKER_ADVERTISE:
    return avb_srp_match_talker_advertise(attr, msg, i, leave_all, 0);
  case MSRP_TALKER_FAILED:
    return avb_srp_match_talker_advertise(attr, msg, i, leave_all, 1);
  case MSRP_LISTENER:
    return avb_srp_match_listener(attr, msg, i, four_packed_event);
  case MSRP_DOMAIN_VECTOR:
    return avb_srp_match_domain(attr, msg, i);
  case MVRP_VID_VECTOR:
    return avb_mvrp_match_vid_vector(attr, msg, i);
  default:
  return 0;
  }
  return 0;
}


static int decode_threepacked(int vector, int i)
{
  for (int j=0;j<(2-i);j++)
    vector /= 6;
  return (vector % 6);
}

static int decode_fourpacked(int vector, int i)
{
  for (int j=0;j<(3-i);j++)
    vector /= 4;
  return (vector % 4);
}

void avb_mrp_process_packet(unsigned char *buf, int etype, int len, unsigned int port_num)
{
  char *end = (char *) &buf[0] + len;
  char *msg = (char *) &buf[0] + sizeof(mrp_header);
  mrp_header *hdr = (mrp_header *)&buf[0];
  unsigned char protocol_version = hdr->ProtocolVersion;

  while (msg < end && (msg[0]!=0 || msg[1]!=0))
  {
    mrp_msg_header *hdr = (mrp_msg_header *) &msg[0];

    unsigned first_value_len = hdr->AttributeLength;
    int attr_type = decode_attr_type(etype, hdr->AttributeType);
    if (protocol_version == 0) {
      if (attr_type==-1) {
        return;
      }
      if (first_value_lengths[attr_type] != first_value_len) {
        return;
      }
    }

    msg = msg + sizeof(mrp_msg_header);

    // non-SRP headers don't contain the AttributeListLength
    if (etype != AVB_SRP_ETHERTYPE) msg -= 2;

    while (msg < end && (msg[0]!=0 || msg[1]!=0))
    {
      mrp_vector_header *vector_hdr = (mrp_vector_header *) msg;
      char *first_value = msg + sizeof(mrp_vector_header);
      int numvalues =
        ((vector_hdr->LeaveAllEventNumberOfValuesHigh & 0x1f)<<8) +
        (vector_hdr->NumberOfValuesLow);
      int leave_all = (vector_hdr->LeaveAllEventNumberOfValuesHigh & 0xe0)>>5;
      leave_all = (leave_all == 1);
      int threepacked_len = (numvalues+2)/3;
      int fourpacked_len = has_fourpacked_events(attr_type)?(numvalues+3)/4:0;
      int len = sizeof(mrp_vector_header) + first_value_len + threepacked_len + fourpacked_len;

      if ((etype == AVB_SRP_ETHERTYPE) && (len+sizeof(mrp_msg_footer) > attribute_list_length(hdr))) {
        return;
      }

      // Check to see that it isn't asking us to overrun the buffer
      if (msg + len > end) {
        return;
      }

      if (leave_all)
      {
        attribute_type_event(attr_type, MRP_EVENT_RECEIVE_LEAVE_ALL, port_num);
      }

      for (int i=0;i<numvalues;i++)
      {
        int matched_attribute = 0;
        // Get the three packed data out of the vector
        int vector = *(first_value + first_value_len + i/3);
        if (vector > 0xD7) break; // Unused range of the threepacked vector should be rejected before decoding
        int three_packed_event = decode_threepacked(vector, i%3);

        // Get the four packed data out of the vector
        int four_packed_event = has_fourpacked_events(attr_type) ?
          decode_fourpacked(*(first_value + first_value_len + threepacked_len + i/4),i%4) : 0;

        if (MRP_DEBUG_ATTR_INGRESS)
        {
          debug_printf("IN: %s\n", debug_attribute_type[attr_type]);
        }

        // This allows the application state machines to respond to the message
        for (int j=0;j<MRP_MAX_ATTRS;j++)
        {
          // Attempt to match to this endpoint's attributes
          if (match_attribute_of_same_type(attr_type, &attrs[j], first_value, i, three_packed_event, four_packed_event, port_num, leave_all))
          {
            matched_attribute = 1;
            mrp_in(three_packed_event, four_packed_event, &attrs[j], port_num);
          }
        }

        if (MRP_NUM_PORTS == 2) {
          if (!matched_attribute && !leave_all)
          {
              if (attr_type == MSRP_TALKER_ADVERTISE ||
                  attr_type == MSRP_LISTENER)
              {
                if (three_packed_event != MRP_ATTRIBUTE_EVENT_MT)
                {
                  mrp_attribute_state *st = avb_srp_process_new_attribute_from_packet(attr_type, first_value, i, port_num);
                  if (st) {
                    mrp_mad_begin(st);

                    mrp_debug_dump_attrs();

                    mrp_in(three_packed_event, four_packed_event, st, port_num);
                  }
                }
              }
          }
        }

      }
      msg = msg + len;
    }
    msg += 2;
  }

  return;
}

