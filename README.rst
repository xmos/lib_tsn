:orphan:

################################################
lib_tsn: Time Sensitive Networking Library
################################################

:version: 8.0.0
:description: Time sensitive networking components for Ethernet AVB audio and media transport
:scope: General Use
:category: Networking
:keywords: AVB, TSN, 1722, gPTP, AVDECC, MRP, audio
:devices: xcore-200

Summary
-------

This library provides components for creating time sensitive
networking and media transport applications.
In particular, it supports the various standards for
Ethernet AVB (Audio Video Bridging).

Features
--------

* 1722 61883-6 audio Talker and Listener (simultaneous) support
* 1722 MAAP support for Talkers
* 802.1Q MRP, MVRP, MSRP protocols
* gPTP server and protocol
* Media clock recovery and interface to PLL clock source
* Support for 1722.1 AVDECC: ADP, AECP (AEM) and ACMP

Known issues
------------

None recorded for this version.

Development repo
----------------

https://github.com/xmos/lib_tsn

Required tools
--------------

* XTC Tools 15.3.1
* CMake 3.21 or later
* Python 3 (AEM descriptor generation in the example applications)

Required libraries (dependencies)
---------------------------------

* lib_ethernet 4.1.0
* lib_i2c 6.4.0
* lib_logging 3.4.0
* lib_xassert 4.3.2
* lib_otpinfo 2.2.1
* lib_random 1.2.0

The example applications additionally require lib_i2s 5.1.0.
They run on the AN02054 QF60B board: XCORE.AI with two RMII PHYs, of which PHY 0 is used.

Related application notes
-------------------------

* AN00202: 100 Mbit AVB endpoint example using stereo I2S (``examples/AN00202_gige_avb_i2s_demo``)
* AN00203: 100 Mbit AVB endpoint example using stereo I2S (``examples/AN00203_gige_avb_tdm_demo``)
* AN01032: 100 Mbit AVB endpoint example using I2S (``examples/AN01032_100Mbit_avb_i2s_demo``)

Support
-------

Report issues and questions through the GitHub issue tracker of the
development repository: https://github.com/xmos/lib_tsn/issues
