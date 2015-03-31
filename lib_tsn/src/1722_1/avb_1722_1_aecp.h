#ifndef AVB_1722_1_AECP_H_
#define AVB_1722_1_AECP_H_

#include <xccompat.h>
#include "xc2compat.h"
#include "avb_1722_1.h"
#include "avb_1722_1_aecp_pdu.h"
#include "avb_1722_1_aecp_aem.h"
#include "avb_control_types.h"
#include "avb_api.h"
#include "avb_1722_1_callbacks.h"
#include "avb_flash.h"
#include "spi.h"
#include "ethernet.h"

void avb_1722_1_aecp_aem_init(unsigned int serial_num);
void avb_1722_1_aem_set_grandmaster_id(REFERENCE_PARAM(unsigned char, as_grandmaster_id));
#ifdef __XC__
extern "C" {
#endif
void process_avb_1722_1_aecp_packet(unsigned char src_addr[6],
                                    avb_1722_1_aecp_packet_t *pkt,
                                    int num_packet_bytes,
                                    CLIENT_INTERFACE(ethernet_tx_if, i_eth),
                                    CLIENT_INTERFACE(avb_interface, i_avb_api),
                                    CLIENT_INTERFACE(avb_1722_1_control_callbacks, i_1722_1_entity));
#ifdef __XC__
}
#endif
void avb_1722_1_aecp_aem_periodic(CLIENT_INTERFACE(ethernet_tx_if, i_eth));

void begin_write_upgrade_image(void);

void abort_write_upgrade_image(void);

int avb_write_upgrade_image_page(int address, unsigned char data[FLASH_PAGE_SIZE], REFERENCE_PARAM(unsigned short, status));

#endif /* AVB_1722_1_AECP_H_ */
