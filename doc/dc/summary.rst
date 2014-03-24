Summary
=======


The XMOS Audio Video Bridging Daisy Chain endpoint (AVB-DC) is a two-port Ethernet MAC relay implementation 
that provides time-synchronized, low latency streaming services through IEEE 802 networks.

.. only:: latex

 .. image:: ../avb/images/avb_xmos_overview.pdf

.. only:: html

 .. image:: ../avb/images/avb_xmos_overview.png

XMOS AVB-DC Key Features
------------------------

* 2 x 100 Mbit/s full duplex Ethernet interface via MII
* Support for 1722.1 discovery, enumeration, command and control: ADP, AECP (AEM) and ACMP
* Simultaneous 1722 Talker and Listener support for sourcing and sinking audio
* 1722 MAAP support for Talker stream MAC address allocation
* 802.1Q Stream Reservation Protocols for QoS including MSRP and MVRP
* 802.1AS Precision Time Protocol server for synchronization
* I2S audio interface for connection to external codecs and DSPs
* Media clock recovery and interface to a PLL clock source for high quality audio clock reproduction