Entity Firmware Upgrade (EFU)
=============================

Introduction
------------

The EFU loader is a flash device firmware upgrade mechanism for AVB endpoints.

The firmware upgrade implementation for XMOS AVB devices uses a subset of the
Memory Object Upload mechanism described in Annex D of the 1722.1-2013 standard:

http://standards.ieee.org/findstds/standard/1722.1-2013.html

Supported functionality:

 * Upload of new firmware to AVB device
 * Reboot of device on firmware upgrade via the 1722.1 REBOOT command

xTIMEcomposer v13.0.2 or later is required to generate flash images compatible with
the AVB-DC flash interface.

SPI Flash IC Requirements and Configuration
-------------------------------------------

The current version of the AVB-DC EFU functionality supports boot flashes with the following 
properties only:

 * A page size of 256 bytes
 * Total flash size greater than or equal to the size required to store the boot loader, factory image and maximum sized upgrade image.

Other flash specific configuration parameters may be changed via ``avb_flash_conf.h``:

.. doxygendefine:: FLASH_SECTOR_SIZE
.. doxygendefine:: FLASH_SPI_CMD_ERASE
.. doxygendefine:: FLASH_NUM_PAGES
.. doxygendefine:: FLASH_MAX_UPGRADE_IMAGE_SIZE

Installing the factory image to the device
------------------------------------------

Once the AVB-DC application has been built:

#. Open the XMOS command line tools (Command Prompt) and
   execute the following command:

   ::

       xflash --boot-partition-size 262144 <binary>.xe

#. If multiple XTAG2s are connected, obtain the adapter ID integer by executing:

   :: 

      xrun -l

#. Execute the `xflash` command with the adapter ID flag

   :: 

      xflash --id <id> --boot-partition-size 262144 <binary>.xe

   .. note::

      Ignore the following warning which is informative only: 

      ``Warning: F03098 Factory image and boot loader cannot be write-protected on flash device on node "0"``

This programs the factory default firmware image into the flash device. 

To use the firmware upgrade mechanism you need to build a firmware upgrade
image:

#. Edit the ``aem_entity_strings.h.in`` file and change the ``AVB_1722_1_FIRMWARE_VERSION_STRING`` and 
   add a new ``AVB_1722_1_ADP_MODEL_ID`` to ``avb_conf.h``.

#. Rebuild the application

To generate the firmware upgrade image run the following command:

   ::

       xflash --factory-version 13 --upgrade 1 <binary>.xe -o upgrade_image.bin

You should now have the firmware upgrade file upgrade_image.bin which can be transferred to the 
AVB end station.

Using the avdecc-lib CLI Controller to upgrade firmware
-------------------------------------------------------

#. To program the new firmware, first run ``avdecccmdline`` and select the interface number that represents 
   the Ethernet interface that the AVB network is connected to:

   ::

       Enter the interface number (1-7): 1

#. Use the ``list`` command to view all AVB end stations on the network:

   ::

       $ list
       
       End Station | Name         | Entity ID          | Firmware Version | MAC
       ---------------------------------------------------------------------------------
       C         0 | AVB 4in/4out | 0x002297fffe005279 |       1.0.3beta0 | 002297005279

#. Select the end station that you wish to upgrade using the ``select`` command with the integer ID shown in the ``End Station``
   column of the ``list`` output and two additional zeroes indicating the Entity and Configuration indices:

   ::

       $ select 0 0 0

#. Begin the firmware upgrade process using the ``upgrade`` command with the full path of the ``upgrade_image.bin``
   file:

   ::

       $ upgrade /path/to/upgrade_image.bin
       Erasing image...
       Succesfully erased.
       Successfully upgraded image.
       Do you want to reboot the device? [y/n]: y

#. The device should now reboot and re-enumerate with an upgraded Firmware Version string. Test this using the ``list`` command:

   ::

       $ list
       
       End Station | Name         | Entity ID          | Firmware Version | MAC
       ---------------------------------------------------------------------------------
       C         0 | AVB 4in/4out | 0x002297fffe005279 |            1.1.0 | 002297005279
