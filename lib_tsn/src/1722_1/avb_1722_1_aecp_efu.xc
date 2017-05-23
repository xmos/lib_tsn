// Copyright (c) 2013-2017, XMOS Ltd, All rights reserved
#include "avb.h"
#include "avb_1722_1_common.h"
#include "avb_1722_1_aecp.h"
#include <string.h>
#include <print.h>
#include "debug_print.h"
#include "xccompat.h"

static unsigned write_offset = -1;

void begin_write_upgrade_image(void) {
  write_offset = 0;
}

void abort_write_upgrade_image(void) {
  write_offset = -1;
}

int avb_write_upgrade_image_page(int address, unsigned char data[FLASH_PAGE_SIZE], unsigned short &status) {
#if AVB_1722_1_FIRMWARE_UPGRADE_ENABLED
  if (address == write_offset) {
    if (fl_writeImagePage(data) != 0) {
      debug_printf("Failed to write page at address %d\n", address);
      status = AECP_AA_STATUS_ADDRESS_INVALID;
      return 1;
    }
    debug_printf("Wrote offset %d\n", write_offset);
    write_offset += FLASH_PAGE_SIZE;

    return 0;
  }
#endif
  status = AECP_AA_STATUS_ADDRESS_INVALID;
  return 1;
}
