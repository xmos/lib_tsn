.. _sec_avb_api:

AVB API
=======
   
General Control Functions
-------------------------

.. doxygenfunction:: avb_get_control_packet

.. doxygenfunction:: avb_process_srp_control_packet

.. doxygenfunction:: avb_process_1722_control_packet


Multicast Address Allocation Commands
-------------------------------------

.. doxygenfunction:: avb_1722_maap_request_addresses

.. doxygenfunction:: avb_1722_maap_rerequest_addresses

.. doxygenfunction:: avb_1722_maap_relinquish_addresses

MAAP Application Hooks
----------------------

.. doxygenfunction:: avb_talker_on_source_address_reserved

AVB Control API
---------------

.. doxygenenum:: device_media_clock_type_t
.. doxygenenum:: device_media_clock_state_t

.. doxygeninterface:: avb_interface

1722.1 Controller Commands
--------------------------

.. doxygenfunction:: avb_1722_1_controller_connect
.. doxygenfunction:: avb_1722_1_controller_disconnect
.. doxygenfunction:: avb_1722_1_controller_disconnect_all_listeners
.. doxygenfunction:: avb_1722_1_controller_disconnect_talker

1722.1 Discovery Commands
-------------------------

.. doxygenfunction:: avb_1722_1_adp_announce
.. doxygenfunction:: avb_1722_1_adp_depart
.. doxygenfunction:: avb_1722_1_adp_discover
.. doxygenfunction:: avb_1722_1_adp_discover_all
.. doxygenfunction:: avb_1722_1_entity_database_flush

1722.1 Application Hooks
------------------------

These hooks are called on events that can be acted upon by the application. They can be overridden by
user defined hooks of the same name to perform custom functionality not present in the core stack.

.. doxygenstruct:: avb_1722_1_entity_record

.. doxygenfunction:: avb_entity_on_new_entity_available
.. doxygenfunction:: avb_talker_on_listener_connect
.. doxygenfunction:: avb_talker_on_listener_disconnect
.. doxygenfunction:: avb_listener_on_talker_connect
.. doxygenfunction:: avb_listener_on_talker_disconnect
