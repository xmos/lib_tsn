// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef ETHERNET_WRAPPERS_H_
#define ETHERNET_WRAPPERS_H_

#include <xccompat.h>
#include "ethernet.h"

unsafe void eth_send_packet(CLIENT_INTERFACE(ethernet_tx_if, i), char *unsafe packet, unsigned n,
                          unsigned dst_port);

#endif /* ETHERNET_WRAPPERS_H_ */
