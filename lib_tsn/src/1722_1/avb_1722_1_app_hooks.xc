#include <xccompat.h>
#include <print.h>
#include "debug_print.h"
#include "avb.h"
#include "avb_conf.h"
#include "avb_1722_common.h"
#include "avb_control_types.h"
#include "avb_1722_1_common.h"
#include "avb_1722_1_protocol.h"
#include "avb_1722_1_acmp.h"
#include "avb_1722_1_adp.h"
#include "avb_1722_1_app_hooks.h"

/*** ADP ***/
void avb_entity_on_new_entity_available_default(client interface avb_interface avb, const_guid_ref_t my_guid, avb_1722_1_entity_record *entity, client interface ethernet_if i_eth)
{
  // Do nothing in the core stack
}

/*** ACMP ***/

/* The controller has indicated that a listener is connecting to this talker stream */
void avb_talker_on_listener_connect_default(client interface avb_interface avb, int source_num, const_guid_ref_t listener_guid)
{
  unsigned stream_id[2];
  enum avb_source_state_t state;
  avb.get_source_state(source_num, state);
  avb.get_source_id(source_num, stream_id);

  debug_printf("CONNECTING Talker stream #%d (%x%x) -> Listener %x:%x:%x:%x:%x:%x:%x:%x\n", source_num, stream_id[0], stream_id[1],
                                                                                              listener_guid.c[7],
                                                                                              listener_guid.c[6],
                                                                                              listener_guid.c[5],
                                                                                              listener_guid.c[4],
                                                                                              listener_guid.c[3],
                                                                                              listener_guid.c[2],
                                                                                              listener_guid.c[1],
                                                                                              listener_guid.c[0]);

  // If this is the first listener to connect to this talker stream, we do a stream registration
  // to reserve the necessary bandwidth on the network
  if (state == AVB_SOURCE_STATE_DISABLED)
  {
    avb_1722_1_talker_set_stream_id(source_num, stream_id);

    avb.set_source_state(source_num, AVB_SOURCE_STATE_POTENTIAL);
  }
}

/* The controller has indicated that a listener has returned an error on connection attempt */
void avb_talker_on_listener_connect_failed_default(client interface avb_interface avb, const_guid_ref_t my_guid, int source_num,
        const_guid_ref_t listener_guid, avb_1722_1_acmp_status_t status, client interface ethernet_if i_eth)
{
}

/* The controller has indicated to connect this listener sink to a talker stream */
avb_1722_1_acmp_status_t avb_listener_on_talker_connect_default(client interface avb_interface avb,
                                                                int sink_num,
                                                                const_guid_ref_t talker_guid,
                                                                unsigned char dest_addr[6],
                                                                unsigned int stream_id[2],
                                                                unsigned short vlan_id,
                                                                const_guid_ref_t my_guid)
{
  const int channels_per_stream = AVB_NUM_MEDIA_OUTPUTS/AVB_NUM_SINKS;
  int map[AVB_NUM_MEDIA_OUTPUTS/AVB_NUM_SINKS];
  for (int i = 0; i < channels_per_stream; i++) map[i] = sink_num ? sink_num*channels_per_stream+i  : sink_num+i;

  debug_printf("CONNECTING Listener sink #%d -> Talker stream %x%x, DA: %x:%x:%x:%x:%x:%x\n", sink_num, stream_id[0], stream_id[1],
                                                                                              dest_addr[0], dest_addr[1], dest_addr[2],
                                                                                              dest_addr[3], dest_addr[4], dest_addr[5]);

  unsigned current_stream_id[2];
  avb.get_sink_id(sink_num, current_stream_id);

  if ((current_stream_id[0] != stream_id[0]) || (current_stream_id[1] != stream_id[1])) {
    avb.set_sink_state(sink_num, AVB_SINK_STATE_DISABLED);
  }

  avb.set_sink_sync(sink_num, 0);
  avb.set_sink_channels(sink_num, channels_per_stream);
  avb.set_sink_map(sink_num, map, channels_per_stream);
  avb.set_sink_id(sink_num, stream_id);
  avb.set_sink_addr(sink_num, dest_addr, 6);
  avb.set_sink_vlan(sink_num, vlan_id);

  avb.set_sink_state(sink_num, AVB_SINK_STATE_POTENTIAL);
  return ACMP_STATUS_SUCCESS;
}

/* The controller has indicated to disconnect this listener sink from a talker stream */
void avb_listener_on_talker_disconnect_default(client interface avb_interface avb,
                                               int sink_num,
                                               const_guid_ref_t talker_guid,
                                               unsigned char dest_addr[6],
                                               unsigned int stream_id[2],
                                               const_guid_ref_t my_guid)
{
  debug_printf("DISCONNECTING Listener sink #%d -> Talker stream %x%x, DA: %x:%x:%x:%x:%x:%x\n", sink_num, stream_id[0], stream_id[1],
                                                                                              dest_addr[0], dest_addr[1], dest_addr[2],
                                                                                              dest_addr[3], dest_addr[4], dest_addr[5]);

  avb.set_sink_state(sink_num, AVB_SINK_STATE_DISABLED);
}

void avb_talker_on_listener_disconnect_default(client interface avb_interface avb,
                                               int source_num,
                                               const_guid_ref_t listener_guid,
                                               int connection_count)
{
  unsigned stream_id[2];
  enum avb_source_state_t state;
  avb.get_source_state(source_num, state);
  avb.get_source_id(source_num, stream_id);

  debug_printf("DISCONNECTING Talker stream #%d (%x%x) -> Listener %x:%x:%x:%x:%x:%x:%x:%x\n", source_num, stream_id[0], stream_id[1],
                                                                                              listener_guid.c[7],
                                                                                              listener_guid.c[6],
                                                                                              listener_guid.c[5],
                                                                                              listener_guid.c[4],
                                                                                              listener_guid.c[3],
                                                                                              listener_guid.c[2],
                                                                                              listener_guid.c[1],
                                                                                              listener_guid.c[0]);

  if ((state > AVB_SOURCE_STATE_DISABLED) && (connection_count == 0))
  {
    avb.set_source_state(source_num, AVB_SOURCE_STATE_DISABLED);
    avb.set_source_vlan(source_num, 0);
  }
}
