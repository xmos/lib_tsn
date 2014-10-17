
sw_avb_lc
............

:Latest release: 6.0.6beta0
:Maintainer: ajwlucas
:Description: AVB-LC specific application software


Key Features
============

* 1722 Talker and Listener (simultaneous) support
* 1722 MAAP support for Talkers
* 802.1Q MRP, MVRP, SRP protocols
* gPTP server and protocol
* Audio interface for I2S
* Media clock recovery and interface to PLL clock source
* Support for 1722.1 AVDECC: ADP, AECP (AEM) and ACMP

Firmware Overview
=================

This firmware is a reference endpoint implementation of Audio Video Bridging protocols for XMOS silicon. It includes a PTP time
server to provide a stable wallclock reference and clock recovery to synchronise listener audio to talker audio
codecs. The Stream Reservation Protocol is used to reserve bandwidth through 802.1 network infrastructure.

Known Issues
============

* Building will generate invalid warning messages that can be ignored:
    * *WARNING: Include file .build/generated/module_avb_1722_1/aem_descriptors.h missing*
    * *audio_i2s.h:187: warning: cannot unroll loop due to unknown loop iteration count*

Support
=======

The HEAD of this repository is a work in progress. It may or may not compile from time to time, and modules, code and features may be incomplete. For a stable, supported release please see the reference designs section at www.xmos.com.

Required software (dependencies)
================================

  * sc_avb (https://github.com/xcore/sc_avb.git)
  * sc_ethernet (https://github.com/xcore/sc_ethernet.git)
  * sc_i2c (https://github.com/xcore/sc_i2c.git)
  * sc_slicekit_support (git@github.com:xcore/sc_slicekit_support)
  * sc_otp (https://github.com/xcore/sc_otp.git)
  * sc_util (git://github.com/xcore/sc_util)

