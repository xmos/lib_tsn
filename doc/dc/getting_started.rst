Getting Started 
================

Obtaining the latest firmware
-----------------------------

#. Log into xmos.com and access `My XMOS` |submenu| `Reference Designs`
#. Request access to the `XMOS AVB-DC Software Release` by clicking the `Request Access` link under `AVB DAISY-CHAIN KIT`. An email will be sent to your registered email address when access is granted.
#. A `Download` link will appear where the `Request Access` link previously appeared. Click and download the firmware zip.


Installing xTIMEcomposer Tools Suite
------------------------------------

The AVB-DC software requires xTIMEcomposer version 13.0.2 or greater. It can be downloaded at the following URL
https://www.xmos.com/en/support/downloads/xtimecomposer


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

#. Select the ``app_daisy_chain`` project in the Project Explorer and click the **Build** icon in the main toolbar.

Installing the application onto flash memory
--------------------------------------------

#. Connect the xTAG-2 debug adapter (XA-SK-XTAG2) to the first sliceKIT core board. 
#. Connect the xTAG-2 to the debug adapter.
#. Plug the xTAG-2 into your development system via USB.
#. Plug in the 12V power adapter and connect it to the sliceKIT core board.
#. In xTIMEcomposer, right-click on the binary within the *app_daisy_chain/bin* folder of the project.
#. Choose `Flash As` |submenu| `Flash Configurations`.
#. Double click `xCORE Application` in the left panel.
#. Choose `hardware` in `Device options` and select the relevant xTAG-2 adapter.
#. Click on **Apply** if configuration has changed.
#. Click on **Flash**. Once completed, disconnect the power from the sliceKIT core board.
#. Repeat steps 1 through 8 for the second sliceKIT.

Using the Command Line Tools
----------------------------

#. Open the XMOS command line tools (Command Prompt) and
   execute the following command:


   ::

       xrun --xscope <binary>.xe

#. If multiple XTAG2s are connected, obtain the adapter ID integer by executing:

   :: 

      xrun -l

#. Execute the `xrun` command with the adapter ID flag

   :: 

      xrun --id <id> --xscope <binary>.xe



Installing the application onto flash via Command Line
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Connect the XTAG-2 debug adapter to the relevant development
   board, then plug the XTAG-2 into your PC or Mac.

Using Command Line Tools
------------------------


#. Open the XMOS command line tools (Command Prompt) and
   execute the following command:

   ::

       xflash <binary>.xe

#. If multiple XTAG2s are connected, obtain the adapter ID integer by executing:

   :: 

      xrun -l

#. Execute the `xflash` command with the adapter ID flag

   :: 

      xflash --id <id> <binary>.xe

