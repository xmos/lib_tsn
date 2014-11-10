#include "avb_conf.h"
#include "avb_mac_filter.h"
#include "avb_conf.h"
#include "avb_srp.h"
#include "avb_mvrp.h"
#include "avb_1722_common.h"
#include "avb_1722_router_table.h"

#pragma unsafe arrays
[[distributable]]
void avb_eth_filter(server ethernet_filter_callback_if i_filter)
{
  while (1) {
    select {
    case i_filter.do_filter(char * buf, unsigned len) ->
                  {unsigned result, unsigned user_data}:
    {
      unsigned short etype = ((unsigned short) buf[12] << 8) + buf[13];
      int qhdr = (etype == 0x0081);
      result = 0;

      if (qhdr) {
        // has a 802.1q tag - read etype from next word
        etype = ((unsigned short) buf[16] << 8) + buf[17];
      }

      switch (etype) {
        case 0x88f7:
          result = 1 << MAC_FILTER_PTP;
          break;
        case AVB_SRP_ETHERTYPE:
        case AVB_MVRP_ETHERTYPE:
          result = 1 << MAC_FILTER_AVB_SRP;
          break;
        case AVB_1722_ETHERTYPE:
          {
            int cd_flag;
            if (qhdr) {
              cd_flag = (buf[18] >> 7) & 1;
            }
            else {
              cd_flag = (buf[14] >> 7) & 1;
            }
            if (cd_flag)
            {
              result = 1 << MAC_FILTER_AVB_CONTROL;
    #if NUM_ETHERNET_MASTER_PORTS == 2
              if ((buf[0] & 0x1) || // Broadcast
              (buf[0] != mac[0] || buf[1] != mac[1])) // Not unicast
              {
                result |= MII_FILTER_FORWARD_TO_OTHER_PORTS;
              }
    #endif
            }
            else {
              // route the 1722 streams
              unsigned id0, id1;
              int link, hash, f0rward;
              int lookup;
              if (qhdr) {
                id0 = (buf[7] << 16 | buf[5]>>16);
                id1 = buf[6];
              }
              else {
                id0 = (buf[6] << 16 | buf[4]>>16);
                id1 = buf[5];
              }
    #pragma xta endpoint "hp_1722_lookup"
              lookup =
                avb_1722_router_table_lookup(id0,
                                             id1,
                                             link,
                                             hash,
                                             f0rward);

              if (lookup) {
                if (link != -1)
                {
                  result = ROUTER_LINK(link);
                }
                else
                {
                  result = 0;
                }
                user_data = hash;
    #if NUM_ETHERNET_MASTER_PORTS == 2
                if (f0rward)
                {
                  result |= MII_FILTER_FORWARD_TO_OTHER_PORTS;
                }
    #endif
              }

            }
          }
          break;
        default:
    #if NUM_ETHERNET_MASTER_PORTS == 2
          if ((buf[0] & 0x1) || // Broadcast
              (buf[0] != mac[0] || buf[1] != mac[1])) // Not unicast
          {
            result |= MII_FILTER_FORWARD_TO_OTHER_PORTS;
          }
    #endif
          break;
      }
    break;
    }
    }
  }
}

