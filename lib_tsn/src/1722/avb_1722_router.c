// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved
#include <xccompat.h>
#include "avb_1722_router.h"
#include "print.h"
#include "debug_print.h"
#include "ethernet.h"

#define DEBUG_1722_ROUTER 0

void avb_1722_enable_stream_forwarding(CLIENT_INTERFACE(ethernet_cfg_if, i_eth),
                                      unsigned int stream_id[2]) {

  if (DEBUG_1722_ROUTER) {
    debug_printf("1722 router: Enabled forwarding for stream %x%x\n", stream_id[0], stream_id[1]);
  }
}

void avb_1722_disable_stream_forwarding(CLIENT_INTERFACE(ethernet_cfg_if, i_eth),
                                       unsigned int stream_id[2]) {
  if (DEBUG_1722_ROUTER) {
    debug_printf("1722 router: Disabled forwarding for stream %x%x\n", stream_id[0], stream_id[1]);
  }
}

void avb_1722_add_stream_mapping(CLIENT_INTERFACE(ethernet_cfg_if, i_eth),
                                unsigned int stream_id[2],
                                int link_num,
                                int avb_hash) {
  if (DEBUG_1722_ROUTER) {
    debug_printf("1722 router: Enabled map for stream %x%x (link_num:%x, hash:%x)\n", stream_id[0], stream_id[1], link_num, avb_hash);
  }
}


void avb_1722_remove_stream_mapping(CLIENT_INTERFACE(ethernet_cfg_if, i_eth),
                                    unsigned int stream_id[2])
{
  if (DEBUG_1722_ROUTER) {
    debug_printf("1722 router: Disabled map for stream %x%x\n", stream_id[0], stream_id[1]);
  }
}

void avb_1722_remove_stream_from_table(CLIENT_INTERFACE(ethernet_cfg_if, i_eth),
                                        unsigned int stream_id[2])
{
  if (DEBUG_1722_ROUTER) {
    debug_printf("1722 router: Removed entry for stream %x%x\n", stream_id[0], stream_id[1]);
  }
}
