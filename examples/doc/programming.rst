Programming guide
+++++++++++++++++

Getting started 
===============

Obtaining the latest firmware
-----------------------------

#. Log into xmos.com and access `My XMOS` |submenu| `Reference Designs`
#. Request access to the `AVB Endpoint Software` by clicking the `Request Access` link under `AVB Audio Endpoint`. An email will be sent to your registered email address when access is granted.
#. A `Download` link will appear where the `Request Access` link previously appeared. Click and download the firmware zip.


Installing xTIMEcomposer Tools Suite
------------------------------------

The AVB-LC software requires xTIMEcomposer version 13.0.2 or greater. It can be downloaded at the following URL
http://www.xmos.com/support/xtools


Importing and building the firmware
-----------------------------------

To import and build the firmware, open xTIMEcomposer Studio and
follow these steps:

#. Choose `File` |submenu| `Import`.

#. Choose `General` |submenu| `Existing Projects into Workspace` and
   click **Next**.

#. Click **Browse** next to **`Select archive file`** and select
   the firmware .zip file downloaded in section 1.

#. Make sure that all projects are ticked in the
   `Projects` list.
 
#. Click **Finish**.

#. Select the ``app_avb_lc_demo`` project in the Project Explorer and click the **Build** icon in the main toolbar.

Installing the application onto flash memory
--------------------------------------------

#. Connect the xTAG-2 debug adapter (XA-SK-XTAG2) to the first AVB endpoint board. 
#. Plug the xTAG-2 into your development system via USB.
#. Plug in the 5V power adapter and connect it to the AVB endpoint board.
#. In xTIMEcomposer, right-click on the binary within the *app_avb_lc_demo/bin* folder of the project.
#. Choose `Flash As` |submenu| `Flash Configurations`.
#. Double click `xCORE Application` in the left panel.
#. Choose `hardware` in `Device options` and select the relevant xTAG-2 adapter.
#. Click on **Apply** if configuration has changed.
#. Click on **Flash**. Once completed, reset the AVB endpoint board using the reset button.
#. Repeat steps 1 through 8 for the second endpoint.

Using the Command Line Tools
----------------------------

#. Open the XMOS command line tools (Command Prompt) and
   execute the following command:


   ::

       xrun --xscope <binary>.xe

#. If multiple xTAG-2s are connected, obtain the adapter ID integer by executing:

   :: 

      xrun -l

#. Execute the `xrun` command with the adapter ID flag

   :: 

      xrun --id <id> --xscope <binary>.xe



Installing the application onto flash via Command Line
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Connect the xTAG-2 debug adapter to the relevant development
   board, then plug the xTAG-2 into your PC or Mac.

Using Command Line Tools
------------------------


#. Open the XMOS command line tools (Command Prompt) and
   execute the following command:

   ::

       xflash <binary>.xe

#. If multiple xTAG-2s are connected, obtain the adapter ID integer by executing:

   :: 

      xrun -l

#. Execute the `xflash` command with the adapter ID flag

   :: 

      xflash --id <id> <binary>.xe

Source code structure
=====================

Directory Structure
-------------------

The source code is split into several top-level directories which are
presented as separate projects in xTIMEcomposer Studio. These are split into
modules and applications.

Applications build into a single
executable using the source code from the modules. The modules used by
an application are specified using the ``USED_MODULES`` variable in
the application Makefile. For more details on this module structure
please see the XMOS build system document *Using XMOS Makefiles (X6348)*.

The AVB-LC source package contains a simple demonstration application `app_avb_lc_demo`.

Core AVB modules are presented in the sc_avb repository. Some support modules originate in other repositories:

.. list-table:: 
 :header-rows: 1

 * - Directory
   - Description
   - Repository
 * - module_ethernet
   - Ethernet MAC
   - sc_ethernet
 * - module_ethernet_board_support
   - Hardware specific board configuration for Ethernet MAC
   - sc_ethernet
 * - module_ethernet_smi
   - SMI interface for reading/writing registers to the Ethernet PHY
   - sc_ethernet
 * - module_otp_board_info
   - Interface for reading serial number and MAC addresses from OTP memory
   - sc_otp
 * - module_i2c_simple
   - Two wire configuration protocol code.
   - sc_i2c
 * - module_random
   - Random number generator
   - sc_util
 * - module_logging
   - Debug print library
   - sc_util
 * - module_slicekit_support
   - sliceKIT core board support
   - sc_slicekit_support

The following modules in sc_avb contain the core AVB code and are needed by
every application:

.. list-table:: 
 :header-rows: 1

 * - Directory
   - Description
 * - module_avb
   - Main AVB code for control and configuration.
 * - module_avb_1722
   - IEEE 1722 transport (listener and talker functionality).
 * - module_avb_1722_1
   - IEEE 1722.1 AVB control protocol.
 * - module_avb_1722_maap
   - IEEE 1722 MAAP - Multicast address allocation code.
 * - module_avb_audio
   - Code for media FIFOs and audio hardware interfaces (I2S).
 * - module_avb_flash
   - Flash access for firmware upgrade
 * - module_avb_media_clock
   - Media clock server code for clock recovery.
 * - module_avb_srp
   - 802.1Qat stream reservation (SRP/MRP/MVRP) code.
 * - module_avb_util
   - General utility functions used by all modules.
 * - module_gptp
   - 802.1AS Precision Time Protocol code.
     

Key Files
---------

.. list-table::
 :header-rows: 1

 * - File
   - Description
 * - ``avb_api.h``
   - Header file containing declarations for the core AVB control API.
 * - ``avb_1722_1_app_hooks.h``
   - Header file containing declarations for hooks into 1722.1  
 * - ``ethernet_rx_client.h`` 
   - Header file for clients that require direct access to the ethernet MAC
     (RX). 
 * - ``ethernet_tx_client.h``
   - Header file for clients that require direct access to the ethernet MAC
     (TX). 
 * - ``gptp.h``
   - Header file for access to the PTP server.
 * - ``audio_i2s.h``
   - Header file containing the I2S audio component.