.. _avb_quickstart:

AVB Endpoint Quick Start Guide
==============================

This guide is intended for customers who have purchased the Low-Cost AVB Audio Endpoint Kit (XK-AVB-LC-SYS).
It applies to version 6 of the reference design firmware.

Obtaining the latest firmware
-----------------------------

#. Log into xmos.com and access `My XMOS` |submenu| `Reference Designs`
#. Request access to the `AVB Endpoint Software` by clicking the `Request Access` link under `AVB Audio Endpoint`. An email will be sent to your registered email address when access is granted.
#. A `Download` link will appear where the `Request Access` link previously appeared. Click and download the firmware zip.


Installing xTIMEcomposer Studio
-------------------------------

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

Setting up the hardware
-----------------------

.. only:: latex

  .. image:: images/board.pdf
     :align: center

Refer to the above figure for board controls and connectors.

#. Connect the two development boards into an AVB capable Ethernet switch via the provided Ethernet cables
#. Set the audio input connection jumpers for either RCA input or 3.5 mm jack input.
#. On the first development board, connect the output of a line-level audio source to the audio input connector.
#. On the second development board, connect an audio playback device to the audio output connector.
#. If not already powered, connect the power supplies to the input power jacks of the boards and power them on.
#. A third party 1722.1 Controller application can then be used to connect and disconnect streams between the endpoints.

   See https://github.com/audioscience/avdecc-lib for an example command line 1722.1 controller application and library.

.. note:: 
    Note: The audio output from the board is line level. If using headphones, an external headphone amplifier may be required.

Next Steps
----------

Access more support collatoral from :menuitem:`xmos.com, Support, Reference designs, AVB audio endpoint`.

Including 

    * AVB Endpoint Design Guide
    * Design files for XR-AVB-LC-BRD board