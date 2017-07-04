.. include:: ../../../README.rst

Typical Resource Usage
......................

 .. resusage::

  * - configuration: Standalone gPTP server
    - target: XCORE-200-EXPLORER
    - globals: on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER;
    - locals: ethernet_cfg_if i_cfg[1]; ethernet_rx_if i_rx[1]; ethernet_tx_if i_tx[1];
              streaming chan c_rx; streaming chan c_tx; streaming chan c_rgmii_cfg; chan gptp[1]
    - fn: on tile[1]: rgmii_ethernet_mac(i_rx, 1, i_tx, 1, c_rx, c_tx,c_rgmii_cfg, rgmii_ports, 1);
          on tile[1]: rgmii_ethernet_mac_config(i_cfg, 1, c_rgmii_cfg);
          on tile[0]: ptp_server(i_rx[0], i_tx[0], i_cfg[0], gptp, 1, PTP_GRANDMASTER_CAPABLE);
    - pins: 0
    - ports: 0
    - clocks: 0

  * - configuration: Combined gPTP and media clock server
    - target: XCORE-200-EXPLORER
    - globals: on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER; on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1A };
    - locals: ethernet_cfg_if i_cfg[1]; ethernet_rx_if i_rx[1]; ethernet_tx_if i_tx[1];
              streaming chan c_rx; streaming chan c_tx; streaming chan c_rgmii_cfg; chan c_ptp[1];
              interface media_clock_if i_mc_ctl; chan c_buf_ctl[1]
    - fn: on tile[1]: rgmii_ethernet_mac(i_rx, 1, i_tx, 1, c_rx, c_tx,c_rgmii_cfg, rgmii_ports, 1);
          on tile[1]: rgmii_ethernet_mac_config(i_cfg, 1, c_rgmii_cfg);
          on tile[0]: gptp_media_clock_server(i_mc_ctl, null, c_buf_ctl, 1, p_fs, i_rx[0], i_tx[0], i_cfg[0], c_ptp, 1, PTP_GRANDMASTER_CAPABLE);
    - pins: 1
    - ports: 1 (1-bit)
    - clocks: 0

  * - configuration: 1722 Talker (1 stream, 8 channels, 48kHz)
    - target: XCORE-200-EXPLORER
    - globals: on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER; on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1A };
    - locals: ethernet_cfg_if i_cfg[1]; ethernet_rx_if i_rx[1]; ethernet_tx_if i_tx[1];
              streaming chan c_rx; streaming chan c_tx; streaming chan c_rgmii_cfg; chan c_ptp[1]; chan c_talker;
              interface media_clock_if i_mc_ctl; chan c_buf_ctl[1]; interface push_if i_audio_in_push; interface pull_if i_audio_in_pull
    - fn: on tile[1]: rgmii_ethernet_mac(i_rx, 1, i_tx, 1, c_rx, c_tx,c_rgmii_cfg, rgmii_ports, 1);
          on tile[1]: rgmii_ethernet_mac_config(i_cfg, 1, c_rgmii_cfg);
          on tile[0]: [[distribute]] audio_input_sample_buffer(i_audio_in_push, i_audio_in_pull);
          on tile[0]: avb_1722_talker(c_ptp[0], c_tx, c_talker, 1, i_audio_in_pull);
    - pins: 0
    - ports: 0
    - clocks: 0

  * - configuration: 1722 Listener (1 stream, 8 channels, 48kHz)
    - target: XCORE-200-EXPLORER
    - globals: on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER; on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1A };
    - locals: ethernet_cfg_if i_cfg[1]; ethernet_rx_if i_rx[1]; ethernet_tx_if i_tx[1];
              streaming chan c_rx; streaming chan c_tx; streaming chan c_rgmii_cfg; chan c_listener;
              chan c_buf_ctl[1]; interface push_if i_audio_out_push; interface pull_if i_audio_out_pull
    - fn: on tile[1]: rgmii_ethernet_mac(i_rx, 1, i_tx, 1, c_rx, c_tx,c_rgmii_cfg, rgmii_ports, 1);
          on tile[1]: rgmii_ethernet_mac_config(i_cfg, 1, c_rgmii_cfg);
          on tile[0]: [[distribute]] audio_output_sample_buffer(i_audio_out_push, i_audio_out_pull);
          on tile[0]: avb_1722_listener(c_rx, c_buf_ctl[0], null, c_listener, 1, i_audio_out_push);
    - pins: 0
    - ports: 0
    - clocks: 0

  * - configuration: 1722.1 and MAAP protocol stack
    - target: XCORE-200-EXPLORER
    - globals: on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER; on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1A };
    - locals: ethernet_cfg_if i_cfg[1]; ethernet_rx_if i_rx[1]; ethernet_tx_if i_tx[1];
              streaming chan c_rx; streaming chan c_tx; streaming chan c_rgmii_cfg; chan c_ptp; interface avb_interface i_avb; interface avb_1722_1_control_callbacks i_17221
    - fn: on tile[1]: rgmii_ethernet_mac(i_rx, 1, i_tx, 1, c_rx, c_tx,c_rgmii_cfg, rgmii_ports, 1);
          on tile[1]: rgmii_ethernet_mac_config(i_cfg, 1, c_rgmii_cfg);
          on tile[0]: avb_1722_1_maap_task(null, i_avb, i_17221, null, i_rx[0], i_tx[0], i_cfg[0], c_ptp);
    - pins: 0
    - ports: 0
    - clocks: 0
    - cores: 0/1

  * - configuration: Stream Reservation Protocol stack
    - target: XCORE-200-EXPLORER
    - globals: on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER; on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1A };
    - locals: ethernet_cfg_if i_cfg[1]; ethernet_rx_if i_rx[1]; ethernet_tx_if i_tx[1];
              streaming chan c_rx; streaming chan c_tx; streaming chan c_rgmii_cfg; chan c_ptp; interface avb_interface i_avb; interface srp_interface i_srp
    - fn: on tile[1]: rgmii_ethernet_mac(i_rx, 1, i_tx, 1, c_rx, c_tx,c_rgmii_cfg, rgmii_ports, 1);
          on tile[1]: rgmii_ethernet_mac_config(i_cfg, 1, c_rgmii_cfg);
          on tile[0]: avb_srp_task(i_avb, i_srp, i_rx[0], i_tx[0], i_cfg[0]);
    - pins: 0
    - ports: 0
    - clocks: 0
    - cores: 0/1

See the Ethernet MAC and I2S/TDM library documentation for their typical resource usage.

Related application notes
.........................

The following application notes use this library:

  * AN00202 - XMOS Gigabit Ethernet AVB I2S demo app note
  * AN00203 - XMOS Gigabit Ethernet AVB TDM demo app note

Ethernet AVB standards
----------------------

Ethernet AVB consists of a collection of different standards that together allow audio, video and time sensitive control data to be streamed over Ethernet. The standards provide synchronized, uninterrupted streaming with multiple talkers and listeners on a switched network infrastructure.

.. index:: ptp, 802.1as

802.1AS
.......

*802.1AS* defines a Precision Timing Protocol based on the *IEEE 1558v2* protocol. It allows every device connected to the network to share a common global clock. The protocol allows devices to have a synchronized view of this clock to within microseconds of each other, aiding media stream clock recovery to phase align audio clocks.

The `IEEE 802.1AS-2011 standard document`_ is available to download free of charge via the IEEE Get Program.

.. _`IEEE 802.1AS-2011 standard document`: http://standards.ieee.org/getieee802/download/802.1AS-2011.pdf

802.1Qav
........

*802.1Qav* defines a standard for buffering and forwarding of traffic through the network using particular flow control algorithms. It gives predictable latency control on media streams flowing through the network.

The XMOS AVB solution implements the requirements for endpoints defined by *802.1Qav*. This is done by traffic flow control in the transmit arbiter of the Ethernet MAC component.

The 802.1Qav specification is available as a section in the `IEEE 802.1Q-2011 standard document`_  and is available to download free of charge via the IEEE Get Program.

.. _`IEEE 802.1Q-2011 standard document`: http://standards.ieee.org/getieee802/download/802.1Q-2011.pdf

802.1Qat
........

*802.1Qat* defines a stream reservation protocol that provides end-to-end reservation of bandwidth across an AVB network.

The 802.1Qat specification is available as a section in the `IEEE 802.1Q-2011 standard document`_.

IEC 61883-6
...........

*IEC 61883-6* defines an audio data format that is contained in *IEEE 1722* streams. The XMOS AVB solution uses *IEC 61883-6* to convey audio sample streams.

The `IEC 61883-6:2005 standard document`_ is available for purchase from the IEC website.

.. _`IEC 61883-6:2005 standard document`: http://webstore.iec.ch/webstore/webstore.nsf/ArtNum_PK/46793


IEEE 1722
.........

*IEEE 1722* defines an encapsulation protocol to transport audio streams over Ethernet. It is complementary to the AVB standards and in particular allows timestamping of a stream based on the *802.1AS* global clock.

The XMOS AVB solution handles both transmission and receipt of audio streams using *IEEE 1722*. In addition it can use the *802.1AS* timestamps to accurately recover the audio master clock from an input stream.

The `IEEE 1722-2011 standard document`_ is available for purchase from the IEEE website.

.. _`IEEE 1722-2011 standard document`: http://standards.ieee.org/findstds/standard/1722-2011.html

IEEE 1722.1
...........

*IEEE 1722.1* is a system control protocol, used for device discovery, connection management and enumeration and control of parameters exposed by the AVB endpoints.

The `IEEE 1722.1-2013 standard document`_ is available for purchase from the IEEE website.

.. _`IEEE 1722.1-2013 standard document`: http://standards.ieee.org/findstds/standard/1722.1-2013.html

|newpage|

Usage
-----

An AVB/TSN audio endpoint consists of five main interacting components:

  * The Ethernet MAC
  * The Precision Timing Protocol (PTP) engine
  * Audio streaming components
  * The media clock server
  * Configuration and other application components

  The following diagram shows the top level structure of an AVB endpoint implemented on the xCORE architecture.

.. only:: latex

  .. image:: images/avb_architecture.pdf
     :align: center


Ethernet MAC
............

The XMOS Ethernet MAC library provides the necessary standards-compliant AVB support for an endpoint.

If 10/100 Mb/s support is required only, the 10/100 Mb/s real-time Ethernet MAC should be used. Gigabit Ethernet is supported
via the 10/100/1000 Mb/s real-time Ethernet MAC and will fallback to 10/100 Mb/s operation on 10/100 networks.

For full usage and API documentation, see the `Ethernet MAC library user guide`_.

.. _`Ethernet MAC library user guide`: https://www.xmos.com/published/lib_ethernet-userguide?version=latest

Precision Timing Protocol
.........................

The Precision Timing Protocol (PTP) enables a system with a
notion of global time on a network. The TSN library implements the *IEEE
802.1AS* protocol. It allows synchronization of the
presentation and playback rate of media streams across a network.

The PTP server requires a single logical core to run and connects to the Ethernet MAC. The library interprets PTP packets from the Ethernet MAC and maintains a notion of global time. The maintenance of global time requires no application interaction with the library.

The PTP library can be configured at runtime to be a potential *PTP grandmaster* or a *PTP slave* only. If the library is configured as a grandmaster, it supplies a clock source to the network. If the network has several grandmasters, the potential grandmasters negotiate between themselves to select a single grandmaster. Once a single grandmaster is selected, all units on the network synchronize a global time from this source and the other grandmasters stop providing timing information. Depending on the intermediate network, this synchronization can be to sub-microsecond level resolution.

Client tasks connect to the timing component via xCORE channels. The relationship between the local reference counter and global time is maintained across this channel, allowing a client to timestamp with a local timer very accurately and then convert it to global time, giving highly accurate global timestamps.

Client tasks can communicate with the server using the API described
in Section :ref:`sec_ptp_api`.

 * The PTP system in the endpoint is self-configuring, it runs
   automatically and gives each endpoint an accurate notion of a global clock.
 * The global clock is *not* the same as the audio word clock, although it can be used to derive it. An audio stream may be at a rate that is independent of the
   PTP clock but will contain timestamps that use the global PTP clock
   domain as a reference.

Audio components
................

AVB streams, channels, talkers and listeners
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Audio is transported in streams of data, where each stream may have multiple
channels. Endpoints producing streams are called *Talkers* and
those receiving them are called *Listeners*. Each stream on the
network has a unique 64-bit stream ID.

A single endpoint can be a Talker, a Listener or both. In general each
endpoint will have a number of *sinks* with the capacity to receive
a number of incoming streams and a number of *sources* with the
capacity to transmit a number of streams.

Routing is done using layer 2 Ethernet MAC addresses. The destination MAC address is a
multicast address so that several Listeners may receive it. In addition,
AVB switches can reserve an end-to-end path with guaranteed bandwidth
for a stream. This is done by the Talker endpoint advertising the
stream to the switches and the Listener(s) registering to receive it. If
sufficient bandwidth is not available, this registration will fail.

Streams carry their own *presentation time*, the time
that samples are due to be output, allowing multiple Listeners that
receive the same stream to output in sync.

 * Streams are encoded using the IEEE 1722 AVB transport protocol.
 * All channels in a stream must be synchronized to
   the same sample clock.
 * All the channels in a stream must come from the same Talker.
 * Routing of audio streams uses Ethernet layer 2 routing based on a multicast destination MAC address
 * Routing of channels is done at the stream level. All channels within a
   stream must be routed to the same place. However, a stream can be
   multicast to several Listeners, each of which picks out different
   channels.
 * A single endpoint can be both a Talker and Listener.
 * Information such as stream ID and destination MAC address of a Talker stream should be communicated to Listeners via 1722.1.
   (see Section :ref:`sec_config`).


Internal routing and audio buffering
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. only:: latex

 .. image:: images/internal_routing.pdf
   :align: center

As described in the previous section, an IEEE 1722 audio stream may
consist of many channels. These channels need to be routed to
particular audio I/Os on the endpoint. To achieve maximum flexibility
the XMOS design uses intermediate audio buffering to route
audio.

The above figure shows the breakdown of 1722 streams
into local FIFOs. The figure shows four points where
transitions to and from audio FIFOs occur. For audio being received by
an endpoint:

  #. When a 1722 stream is received, its channels are mapped to output
     audio FIFOs. This mapping can be configured
     dynamically so that it can be changed at runtime by the configuration component.
  #. The digital hardware interface maps audio FIFOs to audio
     outputs. This mapping is fixed and is configured statically in the
     software.

For audio being transmitted by an endpoint:

  #. The digital hardware interface maps digital audio inputs to a double buffer.

  #. Several channels from this buffer can be combined into a 1722 stream. This
     mapping is dynamic.

The configuration of the mappings is handled through the API described in :ref:`sec_avb_api`.

The audio buffering uses shared memory to move data between tasks, thus the
filling and emptying of the buffers must be on the same tile.


Talker units
~~~~~~~~~~~~

A Talker unit consists of one logical core which creates *IEEE 1722* packets and passes the audio samples onto the MAC. Audio
samples are passed to this component via a double buffer.  The Talker task copies a full buffer of samples into a 1722 packet while a different task implementing the audio hardware interface writes to a second buffer. Once the second buffer is full, the buffers are swapped.

Sample timestamps are converted to the time domain of the global clock provided by the PTP library, and a fixed offset is added to the timestamps to provide the *presentation time* of the samples (*i.e* the time at which the sample should be played by a Listener).

The instantiating of
Talker units is performed via the API described in Section
:ref:`sec_component_api`. Once the Talker unit starts, it registers
with the main control task and is controlled via the main AVB API
described in Section :ref:`sec_avb_api`.

Listener units
~~~~~~~~~~~~~~

.. only:: latex

 .. image:: images/listener-crop.pdf
   :width: 70%
   :align: center

.. only:: html

 .. image:: images/listener-crop.png
   :align: center


A Listener unit takes *IEEE 1722* packets from the MAC
and converts them into a sample stream to be fed into a media FIFO.
Each audio Listener component can listen to several *IEEE 1722*
streams.

A system may have several Listener units. The instantiating of
Listener units is performed via the API described in Section
:ref:`sec_component_api`. Once the Listener unit starts, it registers
with the main control task and is controlled via the main AVB API
described in Section :ref:`sec_avb_api`.

Audio hardware interfaces
~~~~~~~~~~~~~~~~~~~~~~~~~

The audio hardware interface components drive external audio hardware, pull
sample out of audio buffers and push samples into audio buffers.

Different interfaces may interact in different ways; some
directly push and pull from the audio buffers, whereas some for
performance reasons require samples to be provided over an XC
channel.

Media clocks
............

A media clock controls the rate at which information is passed to an
external audio device. For example, an audio word clock that
governs the rate at which samples should be passed to an audio CODEC.

A media clock can be synchronized to one of two sources:

 * An incoming clock signal on a port.
 * The word clock of a remote endpoint, derived from an incoming *IEEE 1722* audio stream.

A hardware interface can be tied to a particular media
clock, allowing the audio output from the XMOS device to be
synchronized with other devices on the network.

All media clocks are maintained by the media clock server
component. This component maintains
the current state of all the media clocks in the system. It then
periodically updates other components with clock change information to
keep the system synchronized. The set of media clocks is determined by
an array passed to the server at startup.

The media clock server component also receives information from the
audio Listener component to track timing information of incoming
*IEEE 1722* streams. It then sends control information back to
ensure the listening component honors the presentation time of the
incoming stream.

Multiple media clocks require multiple hardware PLLs or sample rate conversion.

Driving an external clock generator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A high quality, low jitter master clock is often required to drive an audio CODEC and must be synchronized with an AVB media clock.
The xCORE architecture cannot provide the necessary quality of clock directly but can provide a
lower frequency input source for a frequency synthesizer chip or external
PLL chip.
The frequency synthesizer chip must be able to generate a high
frequency clock based on a lower frequency signal, such as the Cirrus Logic CS2100-CP. The
recommended configuration is as in the block diagram below:

.. only:: latex

 .. image:: images/ratectl.pdf
   :width: 70%
   :align: center

The xCORE device provides control to the frequency synthesizer and the
frequency synthesizer provides the audio master clock to the CODEC and xCORE device. The
sample bit and word clocks are then provided to the CODEC by
the xCORE device.

.. _sec_config:

Device Discovery, Connection Management and Control
...................................................

The control task
~~~~~~~~~~~~~~~~

In addition to components described in previous sections, an AVB
endpoint application requires a task to control and configure the
system. This control task varies across applications but the protocol to provide device discovery, connection management and control services has been standardized by the IEEE in 1722.1.

1722.1
~~~~~~

The 1722.1 standard defines four independent steps that can be used to connect end stations that use 1722 streams to transport media across a LAN. The steps are:

a) Discovery
b) Enumeration
c) Connection Management
d) Control

These steps can be used together to form a system of end stations that interoperate with each other in a standards compliant way. The application that will use these individual steps is called a *Controller* and is the third member in the Talker, Listener and Controller device relationship.

A Controller may exist within a Talker, a Listener, or exist remotely within the network in a separate endpoint or general purpose computer.

The Controller can use the individual steps to find, connect and control entities on the network but it may choose to not use all of the steps if the Controller already knows some of the information (e.g. hard coded values assigned by user/hardware switch or values from previous session establishment) that can be gained in using the steps. The only required step is connection management because this is the step that establishes the bandwidth usage and reservations across the AVB network.

The four steps are broken down as follows:

 * Discovery is the process of finding AVB endpoints on the LAN that have services that are useful to the other
   AVB endpoints on the network. The discovery process also covers the termination of the publication of those
   services on the network.
 * Enumeration is the process of the collection of information from the AVB endpoint that could help an
   1722.1 Controller to use the capabilities of the AVB endpoint. This information can be used for connection
   management.
 * Connection management is the process of connecting or disconnecting one or more streams between two or more
   AVB endpoint.
 * Control is the process of adjusting a parameter on the endpoint from another endpoint. There are a number of standard
   types of controls used in media devices like volume control, mute control and so on. A framework of basic
   commands allows the control process to be extended by the endpoint.

   The XMOS endpoint provides full support for Talker and Listener 1722.1 services. It is expected that Controller software will be available on the network for handling connection management and control.

1722.1 Descriptors
~~~~~~~~~~~~~~~~~~

The XMOS AVB reference design provides an AVDECC Entity Model (AEM) consisting of descriptors to describe the internal components
of the Entity. For a complete overview of AEM, see section 7 of the 1722.1 specification.

An AEM descriptor is a fixed field structure followed by variable length data which describes an object in the AEM
Entity model. The maximum length of a descriptor is 508 octets.

All descriptors share two common fields which are used to uniquely identify a descriptor by a type and an index.
AEM defines a number of descriptors for specific parts of the Entity model. The descriptor types that XMOS currently provide in the
reference design are listed in the table below.

Editing descriptors
~~~~~~~~~~~~~~~~~~~

The descriptors are declared in the a header configuration file named
``aem_descriptors.h.in`` within the ``src/`` directory of the application.
The XMOS Reference column in the table refers to the array names of the descriptors in this file.

This file is post-processed by a script in the build stage to expand strings to 64 octet padded with zeros.

.. list-table::
 :header-rows: 1
 :widths: 11 20 15

 * - Name
   - Description
   - XMOS Reference
 * - ENTITY
   - This is the top level descriptor defining the Entity.
   - ``desc_entity``
 * - CONFIGURATION
   - This is the descriptor defining a configuration of the Entity.
   - ``desc_configuration_0``
 * - AUDIO_UNIT
   - This is the descriptor defining an audio unit.
   - ``desc_audio_unit_0``
 * - STREAM_INPUT
   - This is the descriptor defining an input stream to the Entity.
   - ``desc_stream_input_0``
 * - STREAM_OUTPUT
   - This is the descriptor defining an output stream from the Entity.
   - ``desc_stream_output_0``
 * - JACK_INPUT
   - This is the descriptor defining an input jack on the Entity.
   - ``desc_jack_input_0``
 * - JACK_OUTPUT
   - This is the descriptor defining an output jack on the Entity.
   - ``desc_jack_output_0``
 * - AVB_INTERFACE
   - This is the descriptor defining an AVB interface.
   - ``desc_avb_interface_0``
 * - CLOCK_SOURCE
   - This is the descriptor describing a clock source.
   - ``desc_clock_source_0..1``
 * - LOCALE
   - This is the descriptor defining a locale.
   - ``desc_locale_0``
 * - STRINGS
   - This is the descriptor defining localized strings.
   - ``desc_strings_0``
 * - STREAM_PORT_INPUT
   - This is the descriptor defining an input stream port on a unit.
   - ``desc_stream_port_input_0``
 * - STREAM_PORT_OUTPUT
   - This is the descriptor defining an output stream port on a unit.
   - ``desc_stream_port_output_0``
 * - EXTERNAL_PORT_INPUT
   - This is the descriptor defining an input external port on a unit.
   - ``desc_external_input_port_0``
 * - EXTERNAL_PORT_OUTPUT
   - This is the descriptor defining an output external port on a unit.
   - ``desc_external_output_port_0``
 * - AUDIO_CLUSTER
   - This is the descriptor defining a cluster of channels within an audio stream.
   - ``desc_audio_cluster_0..N``
 * - AUDIO_MAP
   - This is the descriptor defining the mapping between the channels of an audio stream and the channels of the audio port.
   - ``desc_audio_map_0..N``
 * - CLOCK_DOMAIN
   - This is the descriptor describing a clock domain.
   - ``desc_clock_domain_0``


Adding and removing descriptors
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Descriptors are indexed by a descriptor list named ``aem_descriptor_list`` in the ``aem_descriptors.h.in`` file.

The format for this list is as follows:

+---------------------------------+
| Descriptor type                 |
+---------------------------------+
|Number of descriptors of type (N)|
+---------------------------------+
| Size of descriptor 0 (bytes)    |
+---------------------------------+
| Address of descriptor 0         |
+---------------------------------+
|``...``                          |
+---------------------------------+
| Size of descriptor N (bytes)    |
+---------------------------------+
| Address of descriptor N         |
+---------------------------------+

For example:

``AEM_ENTITY_TYPE``, ``1``, ``sizeof(desc_entity)``, ``(unsigned)desc_entity``

|newpage|

Operation
---------

Sources and Sinks in the AVB Manager task
.........................................

Sources transition between disabled, potential and enabled states:

     | ``AVB_SOURCE_STATE_DISABLED``
     | ``AVB_SOURCE_STATE_POTENTIAL``
     | ``AVB_SOURCE_STATE_ENABLED``

Sinks transition between disabled and potential states:

     | ``AVB_SINK_STATE_DISABLED``
     | ``AVB_SINK_STATE_POTENTIAL``

There is also a sink enabled state controlled by AECP AEM start and stop streaming commands. The AVB manager gives no special meaning to the sink enabled state. It is best used to represent the explicit AECP AEM start and stop.

Source and sink state transitions are interface calls to the AVB Manager task, ``update_source_state`` and ``update_sink_state``.

transitions between disabled and potential, both source and sink, are driven by the ACMP connection sequence. When doing a stream connect from a 1722.1 controller, ``CONNECT_TX_COMMAND`` is what sets source to potential. ``CONNECT_TX_RESPONSE`` is what sets sink to potential. When doing a disconnect from a controller, sink goes first in the ACMP sequence. ``DISCONNECT_RX_COMMAND`` to set sink to disabled and ``DISCONNECT_TX_COMMAND`` to set source to disabled (but disable source only with last listener leaving).

  .. figure:: images/acmp_connection_sequence.png
     :width: 60%
     :align: center

     1722.1 ACMP connection sequence

The above behavior is implemented in callback functions such as ``talker_on_listener_connect`` or ``listener_on_talker_disconnect``. These have default implementations that print console messages that you can use to identify source and sink state transitions. Messages printed when connecting (disabled to potential) and disconnecting (enabled to disabled or potential to disabled) a source look like this::

   CONNECTING Talker stream #0 (229780CB90000) -> Listener 0:22:97:FF:FE:80:7:FF
   DISCONNECTING Talker stream #0 (229780CB90000) -> Listener 0:22:97:FF:FE:80:7:FF

Messages when connecting and disconnecting a sink look like this::

   CONNECTING Listener sink #0 -> Talker stream 2297807FF0000, DA: 91:E0:F0:0:58:AC
   DISCONNECTING Listener sink #0 -> Talker stream FFFFFFFFFFFFFFFF, DA: FF:FF:FF:FF:FF:FF

The FFs are a known issue. 1772.1 task only keeps one most recent ACMP message. By the time the "DISCONNECTING" print comes, DISCONNECT_RX_COMMAND has already been overwritten by DISCONNECT_TX_RESPONSE from talker.

There are no messages printed when a source enters or leaves the enabled state, but the conseqeuent starting and stopping of talker task has a message. This one is a good enough indicator of the source entering a leaving the enabled state::

   Talker stream #0 on
   Talker stream #0 off (disabled)

In addition, based on Listener Ready SRP registration, source transitions between potential and enabled states. A MAD Listener Ready Join indication sets source to enabled and Listener Ready Leave indication sets source to potential.

It is following the source enabled-potential transitions when talker task actually starts or stops sending 1722 packets. For receiving 1722 packets by listener task, sink disabled-potential transitions add or remove a MAC filter for given stream.

Source will transition from enabled to potential on cable disconnection or last listener leaving, because these events invalidate the existing Listener Ready registration. But note that source will skip potential and go from enabled directly to disabled on an ACMP disconnect message.

API
---

All AVB/TSN functions can be accessed via the ``avb.h`` header::

  #include "avb.h"

You will also have to add ``lib_tsn`` to the
``USED_MODULES`` field of your application Makefile.

Audio subsystem defines
.......................

AVB applications using the TSN library must include a header configuration file named
``avb_conf.h`` within the ``src/`` directory of the application and this file must set the following values with #defines.

.. doxygendefine:: AVB_MAX_AUDIO_SAMPLE_RATE

.. doxygendefine:: AVB_NUM_SOURCES
.. doxygendefine:: AVB_NUM_TALKER_UNITS
.. doxygendefine:: AVB_MAX_CHANNELS_PER_TALKER_STREAM
.. doxygendefine:: AVB_NUM_MEDIA_INPUTS

.. doxygendefine:: AVB_NUM_SINKS
.. doxygendefine:: AVB_NUM_LISTENER_UNITS
.. doxygendefine:: AVB_MAX_CHANNELS_PER_LISTENER_STREAM
.. doxygendefine:: AVB_NUM_MEDIA_OUTPUTS

.. doxygendefine:: AVB_NUM_MEDIA_UNITS
.. doxygendefine:: AVB_NUM_MEDIA_CLOCKS

1722.1
......

.. doxygendefine:: AVB_ENABLE_1722_1
.. doxygendefine:: AVB_1722_1_TALKER_ENABLED
.. doxygendefine:: AVB_1722_1_LISTENER_ENABLED
.. doxygendefine:: AVB_1722_1_CONTROLLER_ENABLED

Descriptor specific strings can be modified in a header configuration file named
``aem_entity_strings.h.in`` within the ``src/`` directory. It is post-processed by a script
in the build stage to expand strings to 64 octet padded with zeros.

.. list-table::
 :header-rows: 1
 :widths: 11 15

 * - Define
   - Description
 * - ``AVB_1722_1_ENTITY_NAME_STRING``
   - A string (64 octet max) containing an Entity name
 * - ``AVB_1722_1_FIRMWARE_VERSION_STRING``
   - A string (64 octet max) containing the firmware version of the Entity
 * - ``AVB_1722_1_GROUP_NAME_STRING``
   - A string (64 octet max) containing the group name of the Entity
 * - ``AVB_1722_1_SERIAL_NUMBER_STRING``
   - A string (64 octet max) containing the serial number of the Entity
 * - ``AVB_1722_1_VENDOR_NAME_STRING``
   - A string (64 octet max) containing the vendor name of the Entity
 * - ``AVB_1722_1_MODEL_NAME_STRING``
   - A string (64 octet max) containing the model name of the Entity

1722.1 application hooks
........................

These hooks are called on events that can be acted upon by the application. They can be overridden by
user defined hooks of the same name to perform custom functionality not present in the core stack.

.. doxygenfunction:: avb_talker_on_listener_connect
.. doxygenfunction:: avb_talker_on_listener_disconnect
.. doxygenfunction:: avb_listener_on_talker_connect
.. doxygenfunction:: avb_listener_on_talker_disconnect

.. doxygenenum:: avb_1722_1_aecp_aem_status_code

.. doxygeninterface:: avb_1722_1_control_callbacks

|newpage|

AVB Control API
...............

.. _sec_avb_api:

.. doxygenenum:: avb_stream_format_t
.. doxygenenum:: avb_source_state_t
.. doxygenenum:: avb_sink_state_t
.. doxygenenum:: device_media_clock_type_t
.. doxygenenum:: device_media_clock_state_t

.. doxygeninterface:: avb_interface

|newpage|

Core components
...............

.. _sec_component_api:

.. doxygenfunction:: avb_manager

.. doxygenstruct:: avb_srp_info_t

.. doxygeninterface:: srp_interface

.. doxygenfunction:: avb_srp_task

.. doxygenfunction:: avb_1722_1_maap_task

.. doxygenfunction:: gptp_media_clock_server

.. doxygenfunction:: avb_1722_listener

.. doxygenfunction:: avb_1722_talker

|newpage|

.. _sec_ptp_api:

Creating a gPTP server instance
...............................

All gPTP functions can be accessed via the ``gptp.h`` header::

  #include <gptp.h>

.. doxygenenum:: ptp_server_type

.. doxygenfunction:: ptp_server

Time data structures
....................

.. doxygenstruct:: ptp_timestamp

Getting PTP time information
............................

.. doxygentypedef:: ptp_time_info
.. doxygentypedef:: ptp_time_info_mod64

.. doxygenfunction:: ptp_get_time_info
.. doxygenfunction:: ptp_get_time_info_mod64

.. doxygenfunction:: ptp_request_time_info
.. doxygenfunction:: ptp_request_time_info_mod64

.. doxygenfunction:: ptp_get_requested_time_info
.. doxygenfunction:: ptp_get_requested_time_info_mod64

Converting Timestamps
.....................

.. doxygenfunction:: local_timestamp_to_ptp

.. doxygenfunction:: local_timestamp_to_ptp_mod32

.. doxygenfunction:: ptp_timestamp_to_local

.. doxygenfunction:: ptp_timestamp_offset


|appendix|

Known Issues
------------

There are no known issues with this library.

.. include:: ../../../CHANGELOG.rst
