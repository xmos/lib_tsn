100Mbit Ethernet AVB endpoint example using I2S master
======================================================

.. appnote:: AN01032

.. version:: 1.0.3

Summary
-------

This application note demonstrates an Ethernet AVB endpoint that streams uncompressed audio
over an Ethernet AVB network with guaranteed Quality of Service, low latency and time synchronization.
It shows how to interface with a high performance audio codec via the I2S library.

The application is configured to provide a single Talker and Listener stream of 8 audio channels
at up to 192kHz sampling rate.

The example also shows plug-and-play multichannel recording and playback with Apple Mac hardware running OS X 10.10.5

Required tools and libraries
............................

.. appdeps::

Required hardware
.................

The application note is designed to run on the following hardware : 
    
    - X200 sliceKIT 1V0 (XK-SK-X200-ST);

    - Ethernet sliceCARD (XA-SK-E100 1V1);

    - Audio-PLL sliceCARD (XA-SK-AUDIO-PLL 1v0).


The described hardware setup is used for example purposes only.  The firmware can be modified to run on any xCORE-200 series device with the required external hardware.

The firmware was interoperability tested with a Early 2011 MacBook Pro running OS X version 10.10.5.

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

