#include <xccompat.h>
#include <print.h>
#include "debug_print.h"
#include "avb.h"
#include "avb_conf.h"
#include "avb_1722_common.h"
#include "avb_1722_maap.h"
#include "avb_1722_maap_protocol.h"
#include "avb_1722_1_adp.h"
#include "avb_1722_1_acmp.h"
#include "avb_control_types.h"

void avb_talker_on_source_address_reserved_default(client interface avb_interface avb, int source_num, unsigned char mac_addr[6])
{
  // Do some debug print
  debug_printf("MAAP reserved Talker stream #%d address: %x:%x:%x:%x:%x:%x\n", source_num,
                            mac_addr[0],
                            mac_addr[1],
                            mac_addr[2],
                            mac_addr[3],
                            mac_addr[4],
                            mac_addr[5]);

  avb.set_source_dest(source_num, mac_addr, 6);

  /* NOTE: acmp_talker_init() must be called BEFORE talker_set_mac_address() otherwise it will zero
   * what was just set */
  avb_1722_1_acmp_talker_init();
  avb_1722_1_talker_set_mac_address(source_num, mac_addr);
  avb_1722_1_adp_announce();
}
