.. _sec_component_api:

Component tasks and functions
=============================

The following functions provide components that can be combined in the
top-level main. For details on the Ethernet component, see
the `Ethernet Component Guide
<http://github.xcore.com/sc_ethernet/index.html>`_.

Core Components
~~~~~~~~~~~~~~~

.. doxygenfunction:: avb_manager

.. doxygenstruct:: avb_srp_info_t

.. doxygeninterface:: srp_interface

.. doxygenfunction:: avb_srp_task

.. doxygenenum:: avb_1722_1_aecp_aem_status_code

.. doxygeninterface:: avb_1722_1_control_callbacks

.. doxygenfunction:: avb_1722_1_task

.. doxygenstruct:: fl_spi_ports

.. doxygeninterface:: spi_interface

.. doxygenfunction:: spi_task

.. doxygenfunction:: ptp_server

.. doxygenfunction:: media_clock_server

.. doxygenfunction:: avb_1722_listener

.. doxygenfunction:: avb_1722_talker

Audio Components
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


