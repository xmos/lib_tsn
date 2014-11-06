#include "avb.h"
#include "avb_1722_1_common.h"
#include "avb_1722_1_aecp.h"
#include <string.h>
#include <print.h>
#include "debug_print.h"
#include "xccompat.h"
#include "avb_flash.h"

#define FLASH_SIZE (FLASH_NUM_PAGES * FLASH_PAGE_SIZE)
#define NUM_SECTORS (FLASH_SIZE / FLASH_SPI_SECTOR_SIZE)

static unsigned write_address = 0;
static unsigned write_offset = -1;

static unsigned int sortbits(unsigned int bits)
{
  return( byterev(bitrev(bits)) );
}

static int fl_get_sector_address(int sectorNum)
{
  return FLASH_SPI_SECTOR_SIZE * sectorNum;
}

/**
 * Returns the number of the first sector starting at or after the specified
 * address.
 * \return The number of sector or -1 if there is no such sector.
 */
static int fl_get_sector_at_or_after(unsigned address)
{
  unsigned sector;
  for (sector = 0; sector < NUM_SECTORS; sector++) {
    if (fl_get_sector_address(sector) >= address)
      return sector;
  }
  return -1;
}

static int fl_get_next_boot_image(client interface spi_interface i_spi, fl_boot_image_info* boot_image_info)
{
  unsigned tmpbuf[7];
  unsigned last_address = boot_image_info->startAddress+boot_image_info->size;
  unsigned sector_num = fl_get_sector_at_or_after(last_address);
  if (sector_num < 0)
    return 1;
  while (sector_num < NUM_SECTORS) {
    unsigned sector_address = fl_get_sector_address(sector_num);
    spi_flash_read(i_spi, sector_address, (unsigned char*)tmpbuf, 7 * sizeof(int));
    if (sortbits(tmpbuf[0]) == IMAGE_TAG_13) {
      boot_image_info->startAddress = sector_address;
      boot_image_info->size         = sortbits(tmpbuf[IMAGE_LENGTH_OFFSET_13]);
      boot_image_info->version      = sortbits(tmpbuf[IMAGE_VERSION_OFFSET_13]);
      boot_image_info->factory      = 0;
      return 0;
    }
    sector_num++;
  }
  return 1;
}

static int get_factory_image(client interface spi_interface i_spi, fl_boot_image_info* boot_image_info)
{
  unsigned tmpbuf[9];
  spi_flash_read(i_spi, 0, (unsigned char*)tmpbuf, 4);
  unsigned start_addr = (sortbits(tmpbuf[0])+2)<<2; /* Normal case. */
  spi_flash_read(i_spi, start_addr, (unsigned char*)tmpbuf, (6 + 3) * sizeof(int));
  unsigned *header = tmpbuf;
  if (sortbits(tmpbuf[0]) != IMAGE_TAG_13) {
    return 1;
  }
  boot_image_info->startAddress = start_addr;
  boot_image_info->size         = sortbits(header[IMAGE_LENGTH_OFFSET_13]);  /* Size is to next sector start. */
  boot_image_info->version      = sortbits(header[IMAGE_VERSION_OFFSET_13]);
  boot_image_info->factory      = 1;
  return 0;
}

static void write_and_update_address(client interface spi_interface i_spi, unsigned char data[FLASH_PAGE_SIZE]) {
    debug_printf("Wrote offset %d at %x \n", write_offset, write_address);
    spi_flash_write_small(i_spi, write_address, data, FLASH_PAGE_SIZE);
    write_address += FLASH_PAGE_SIZE;
    write_offset += FLASH_PAGE_SIZE;
}

static void erase_sectors(client interface spi_interface i_spi, unsigned int image_size) {
    unsigned int sector_address = write_address;
    do {
      spi_flash_erase(i_spi, sector_address, FLASH_SPI_SECTOR_SIZE);
      debug_printf("Erased sector %x\n", sector_address);
      sector_address += FLASH_SPI_SECTOR_SIZE;
    } while(sector_address < write_address + image_size);
}

int avb_erase_upgrade_image(client interface spi_interface i_spi)
{
  fl_boot_image_info image;
  int factory = get_factory_image(i_spi, &image);

  if (factory) {
    debug_printf("No factory image!\n");
    return 1;
  } else {
    if (fl_get_next_boot_image(i_spi, &image) != 0) {
      // No upgrade image exists in flash
      debug_printf("No upgrade\n");
      unsigned sectorNum = fl_get_sector_at_or_after(image.startAddress + image.size);
      write_address = fl_get_sector_address(sectorNum);

      erase_sectors(i_spi, FLASH_MAX_UPGRADE_IMAGE_SIZE);
    }
    else {
      // Replace the upgrade image
      debug_printf("Upgrade exists\n");
      write_address = image.startAddress;

      erase_sectors(i_spi, image.size);
    }
  }

  write_offset = 0;
  return 0;
}

int avb_write_upgrade_image_page(client interface spi_interface i_spi, int address, unsigned char data[FLASH_PAGE_SIZE]) {

  if (address == write_offset && write_offset <= FLASH_MAX_UPGRADE_IMAGE_SIZE) {
    write_and_update_address(i_spi, data);

    return 0;
  }

  return 1;
}
