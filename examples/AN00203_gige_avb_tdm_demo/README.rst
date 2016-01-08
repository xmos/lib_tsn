Gigabit Ethernet AVB endpoint example using TDM master
======================================================

.. appnote:: AN00203

.. version:: 1.0.3

Summary
-------

This application note demonstrates a Gigabit Ethernet AVB endpoint that streams uncompressed audio
over an Ethernet AVB network with guaranteed Quality of Service, low latency and time synchronization.
It shows how to interface with a high performance audio codec via the I2S/TDM library.

The application is configured to provide four Talker and Listener streams of 8 audio channels each,
at 48 kHz sampling rate.

The example also shows plug-and-play multichannel recording and playback with Apple Mac hardware running OS X 10.10.

Required tools and libraries
............................

.. appdeps::

Required hardware
.................

The application note is designed to run on the XMOS xCORE-200 Multichannel Audio platform version 2.

There is no dependency on this hardware and the firmware can be modified to run on any xCORE XE/XEF
series device with the required external hardware.

The firmware was interoperability tested with a Late 2013 MacBook Pro running OS X version 10.10.3.

Prerequisites
.............

  - This document assumes familiarity with the XMOS xCORE architecture, the IEEE AVB/TSN standards,
    the XMOS tool chain and the xC language. Documentation related to these aspects which are
    not specific to this application note are linked to in the references appendix.
  - For descriptions of XMOS related terms found in this document please see the XMOS Glossary [#]_.

  - The example uses various libraries, full details of the functionality
    of a library can be found in its user guide [#]_.

  .. [#] http://www.xmos.com/published/glossary

  .. [#] http://www.xmos.com/support/libraries

