API Reference
=============

.. _sec_defines_api:

Configuration defines
---------------------

Demo and hardware specific
~~~~~~~~~~~~~~~~~~~~~~~~~~

Demo parameters and hardware port definitions are set in a header configuration file named ``app_config.h`` within the ``src/`` directory
of the application.

.. doxygendefine:: AVB_DEMO_ENABLE_TALKER
.. doxygendefine:: AVB_DEMO_ENABLE_LISTENER
.. doxygendefine:: AVB_DEMO_NUM_CHANNELS

Core AVB parameters
~~~~~~~~~~~~~~~~~~~
  
Each application using the AVB modules must include a header configuration file named
``avb_conf.h`` within the ``src/`` directory of the application and this file must set the #defines in the following two sections.

See the demo application for a realistic example.

.. note:: 

  Defaults for these #defines are assigned in their absence, but may cause compilation failure or unpredictable/erroneous behaviour.

Ethernet
~~~~~~~~
See the Ethernet documentation for detailed information on its parameters:

https://www.xmos.com/published/xmos-layer-2-ethernet-mac-component?version=latest

Audio subsystem
~~~~~~~~~~~~~~~

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
~~~~~~

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
.. _sec_component_api:

Component tasks and functions
-----------------------------

The following functions provide components that can be combined in the
top-level main. For details on the Ethernet component, see
the `Ethernet Component Guide
<http://github.xcore.com/sc_ethernet/index.html>`_.

Core components
~~~~~~~~~~~~~~~

.. doxygenfunction:: avb_manager

.. doxygenstruct:: avb_srp_info_t

.. doxygeninterface:: srp_interface

.. doxygenfunction:: avb_srp_task

.. doxygenenum:: avb_1722_1_aecp_aem_status_code

.. doxygeninterface:: avb_1722_1_control_callbacks

.. doxygenfunction:: avb_1722_1_maap_task

.. doxygenstruct:: fl_spi_ports

.. doxygeninterface:: spi_interface

.. doxygenfunction:: spi_task

.. doxygenfunction:: ptp_server

.. doxygenfunction:: media_clock_server

.. doxygenfunction:: avb_1722_listener

.. doxygenfunction:: avb_1722_talker

Audio components
~~~~~~~~~~~~~~~~

The following types are used by the AVB audio components:

.. doxygentypedef:: media_output_fifo_t

.. doxygentypedef:: media_output_fifo_data_t

.. doxygentypedef:: media_input_fifo_t

.. doxygentypedef:: media_input_fifo_data_t

The following functions implement AVB audio components:

.. doxygenfunction:: init_media_input_fifos

.. doxygenfunction:: init_media_output_fifos

.. doxygenfunction:: i2s_master

.. doxygenfunction:: media_output_fifo_to_xc_channel

.. doxygenfunction:: media_output_fifo_to_xc_channel_split_lr


.. _sec_avb_api:

AVB API
-------
   
General control functions
~~~~~~~~~~~~~~~~~~~~~~~~~

.. doxygenfunction:: avb_get_control_packet

.. doxygenfunction:: avb_process_srp_control_packet

.. doxygenfunction:: avb_process_1722_control_packet


Multicast Address Allocation commands
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. doxygenfunction:: avb_1722_maap_request_addresses

.. doxygenfunction:: avb_1722_maap_rerequest_addresses

.. doxygenfunction:: avb_1722_maap_relinquish_addresses

MAAP application hooks
~~~~~~~~~~~~~~~~~~~~~~

.. doxygenfunction:: avb_talker_on_source_address_reserved

AVB Control API
~~~~~~~~~~~~~~~

.. doxygenenum:: device_media_clock_type_t
.. doxygenenum:: device_media_clock_state_t

.. doxygeninterface:: avb_interface

1722.1 Controller commands
~~~~~~~~~~~~~~~~~~~~~~~~~~

.. doxygenfunction:: avb_1722_1_controller_connect
.. doxygenfunction:: avb_1722_1_controller_disconnect
.. doxygenfunction:: avb_1722_1_controller_disconnect_all_listeners
.. doxygenfunction:: avb_1722_1_controller_disconnect_talker

1722.1 Discovery commands
~~~~~~~~~~~~~~~~~~~~~~~~~

.. doxygenfunction:: avb_1722_1_adp_announce
.. doxygenfunction:: avb_1722_1_adp_depart
.. doxygenfunction:: avb_1722_1_adp_discover
.. doxygenfunction:: avb_1722_1_adp_discover_all
.. doxygenfunction:: avb_1722_1_entity_database_flush

1722.1 application hooks
~~~~~~~~~~~~~~~~~~~~~~~~

These hooks are called on events that can be acted upon by the application. They can be overridden by
user defined hooks of the same name to perform custom functionality not present in the core stack.

.. doxygenstruct:: avb_1722_1_entity_record

.. doxygenfunction:: avb_entity_on_new_entity_available
.. doxygenfunction:: avb_talker_on_listener_connect
.. doxygenfunction:: avb_talker_on_listener_disconnect
.. doxygenfunction:: avb_listener_on_talker_connect
.. doxygenfunction:: avb_listener_on_talker_disconnect


.. _sec_1722_1_aem:

1722.1 descriptors
------------------

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

.. _sec_ptp_api:

PTP client API
--------------

The PTP client API can be used if you want extra information about the PTP
time domain. An application does not need to directly use this to
control the AVB endpoint since the talker, listener and media clock
server units communicate with the PTP server directly.


Time data structures
~~~~~~~~~~~~~~~~~~~~

.. doxygenstruct:: ptp_timestamp

Getting PTP time information
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. doxygentypedef:: ptp_time_info
.. doxygentypedef:: ptp_time_info_mod64

.. doxygenfunction:: ptp_get_time_info
.. doxygenfunction:: ptp_get_time_info_mod64

.. doxygenfunction:: ptp_request_time_info
.. doxygenfunction:: ptp_request_time_info_mod64

.. doxygenfunction:: ptp_get_requested_time_info
.. doxygenfunction:: ptp_get_requested_time_info_mod64

Converting timestamps
~~~~~~~~~~~~~~~~~~~~~

.. doxygenfunction:: local_timestamp_to_ptp

.. doxygenfunction:: local_timestamp_to_ptp_mod32

.. doxygenfunction:: ptp_timestamp_to_local


