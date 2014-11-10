#ifndef _mac_custom_filter_h_
#define _mac_custom_filter_h_
#include "ethernet.h"

enum filter_clients {
  MAC_FILTER_1722=0,
  MAC_FILTER_PTP,
  MAC_FILTER_AVB_CONTROL,
  MAC_FILTER_AVB_SRP,
  NUM_FILTER_CLIENTS
};

#define ROUTER_LINK(n) (1 << (NUM_FILTER_CLIENTS+n))

#define HTONS(x) ((x>>8)|(((x&0xff)<<8)))

#define MII_FILTER_FORWARD_TO_OTHER_PORTS (0x80000000)

#if defined(__XC__)

[[distributable]]
void avb_eth_filter(server ethernet_filter_callback_if i_filter);
#endif

#endif


