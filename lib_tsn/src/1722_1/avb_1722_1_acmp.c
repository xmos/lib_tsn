// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved
#include <string.h>
#include <print.h>
#include "quadflashlib.h"
#include "avb_1722_common.h"
#include "avb_1722_1_common.h"
#include "avb_1722_1_acmp.h"
#include "debug_print.h"
#include "avb.h"
#include "misc_timer.h"
#ifdef AVB_1722_1_ENABLE_ASSERTIONS
#include <assert.h>
#endif
#include "avb_1722_1_app_hooks.h"
#include "avb_1722_def.h"
#include "avb_1722_1.h"

/* Inflight command defines */
#define CONTROLLER  0
#define LISTENER    1

#define TRUE 1
#define FALSE 0

enum acmp_controller_state_t acmp_controller_state = ACMP_CONTROLLER_IDLE;
enum acmp_talker_state_t acmp_talker_state = ACMP_TALKER_IDLE;
enum acmp_listener_state_t acmp_listener_state = ACMP_LISTENER_IDLE;

extern unsigned int avb_1722_1_buf[AVB_1722_1_PACKET_SIZE_WORDS];
extern guid_t my_guid;

static const unsigned char avb_1722_1_acmp_dest_addr[6] = AVB_1722_1_ACMP_DEST_MAC;

// ACMP command timeouts (in centiseconds) as defined in Table 7.4 of the specification
static const unsigned int avb_1722_1_acmp_inflight_timeouts[] = {20, 2, 2, 45, 5, 2, 2};

// Stream info lists
avb_1722_1_acmp_listener_stream_info acmp_listener_streams[AVB_1722_1_MAX_LISTENERS];
avb_1722_1_acmp_talker_stream_info acmp_talker_streams[AVB_1722_1_MAX_TALKERS];

// Inflight command lists
avb_1722_1_acmp_inflight_command acmp_controller_inflight_commands[AVB_1722_1_MAX_INFLIGHT_COMMANDS];
avb_1722_1_acmp_inflight_command acmp_listener_inflight_commands[AVB_1722_1_MAX_INFLIGHT_COMMANDS];

static unsigned acmp_centisecond_counter[2];
static avb_timer acmp_inflight_timer[2];

// Controller command
avb_1722_1_acmp_cmd_resp acmp_controller_cmd_resp;

// Talker's rcvdCmdResp
avb_1722_1_acmp_cmd_resp acmp_talker_rcvd_cmd_resp;

// Listener's rcvdCmdResp
avb_1722_1_acmp_cmd_resp acmp_listener_rcvd_cmd_resp;

#if AVB_1722_1_FAST_CONNECT_ENABLED
avb_1722_1_acmp_fast_connect_persist_state fast_connect_info;
#endif

short sequence_id[2];

void acmp_zero_listener_stream_info(int unique_id);

/**
 * Initialises ACMP state machines, data structures and timers.
 *
 * Must be called before any other ACMP function.
 */
void avb_1722_1_acmp_controller_init()
{
    acmp_controller_state = ACMP_CONTROLLER_WAITING;
    memset(acmp_controller_inflight_commands, 0, sizeof(avb_1722_1_acmp_inflight_command) * AVB_1722_1_MAX_INFLIGHT_COMMANDS);

    sequence_id[CONTROLLER] = 0;

    init_avb_timer(&acmp_inflight_timer[CONTROLLER], 10);
    acmp_centisecond_counter[CONTROLLER] = 0;
    start_avb_timer(&acmp_inflight_timer[CONTROLLER], 1);
}

void avb_1722_1_acmp_controller_deinit()
{
    acmp_controller_state = ACMP_CONTROLLER_IDLE;
}

void avb_1722_1_acmp_talker_init()
{
    acmp_talker_state = ACMP_TALKER_WAITING;
}

void avb_1722_1_acmp_listener_init()
{
    int i;
    acmp_listener_state = ACMP_LISTENER_WAITING;
    memset(acmp_listener_inflight_commands, 0, sizeof(avb_1722_1_acmp_inflight_command) * AVB_1722_1_MAX_INFLIGHT_COMMANDS);

    for (i = 0; i < AVB_1722_1_MAX_LISTENERS; i++) acmp_zero_listener_stream_info(i);

    sequence_id[LISTENER] = 0;

    init_avb_timer(&acmp_inflight_timer[LISTENER], 10);
    acmp_centisecond_counter[LISTENER] = 0;
    start_avb_timer(&acmp_inflight_timer[LISTENER], 1);
}

/**
 * Creates a valid ACMP Ethernet packet in avb_1722_1_buf[] from a supplied command structure
 */
void avb_1722_1_create_acmp_packet(avb_1722_1_acmp_cmd_resp *cr, int message_type, int status)
{
    struct ethernet_hdr_t *hdr = (ethernet_hdr_t*) &avb_1722_1_buf[0];
    avb_1722_1_acmp_packet_t *pkt = (avb_1722_1_acmp_packet_t*) (hdr + AVB_1722_1_PACKET_BODY_POINTER_OFFSET);

    avb_1722_1_create_1722_1_header(avb_1722_1_acmp_dest_addr, DEFAULT_1722_1_ACMP_SUBTYPE, message_type, status, AVB_1722_1_ACMP_CD_LENGTH, hdr);

    set_64(pkt->stream_id, cr->stream_id.c);
    set_64(pkt->controller_guid, cr->controller_guid.c);
    set_64(pkt->listener_guid, cr->listener_guid.c);
    set_64(pkt->talker_guid, cr->talker_guid.c);
    hton_16(pkt->talker_unique_id, cr->talker_unique_id);
    hton_16(pkt->listener_unique_id, cr->listener_unique_id);
    hton_16(pkt->connection_count, cr->connection_count);
    hton_16(pkt->sequence_id, cr->sequence_id);
    hton_16(pkt->flags, cr->flags);
    hton_16(pkt->vlan_id, cr->vlan_id);
    memcpy(pkt->dest_mac, cr->stream_dest_mac, 6);
}

void acmp_progress_inflight_timer(int entity_type)
{
    if (avb_timer_expired(&acmp_inflight_timer[entity_type]))
    {
        acmp_centisecond_counter[entity_type]++;
        start_avb_timer(&acmp_inflight_timer[entity_type], 1);
    }
}

/*
 * Returns a pointer to the correct inflight command list for a talker/listener/controller
 */
static avb_1722_1_acmp_inflight_command *acmp_get_inflight_list(int entity_type)
{
    avb_1722_1_acmp_inflight_command *inflight;

#ifdef AVB_1722_1_ENABLE_ASSERTIONS
    assert(entity_type == CONTROLLER || entity_type == LISTENER);
#endif

    switch (entity_type)
    {
        case CONTROLLER: inflight = &acmp_controller_inflight_commands[0]; break;
        case LISTENER: inflight = &acmp_listener_inflight_commands[0]; break;
    }

    return inflight;
}

/*
 * Returns the index into the inflight list for a specific received command's sequence id
 *
 * Returns -1 if the sequence id is not found in the list
 */
static int acmp_get_inflight_from_sequence_id(int entity_type, unsigned short id)
{
    int i;
    avb_1722_1_acmp_inflight_command *inflight = acmp_get_inflight_list(entity_type);

    for (i = 0; i < AVB_1722_1_MAX_INFLIGHT_COMMANDS; ++i)
    {
        if (inflight[i].in_use && (inflight[i].command.sequence_id == id))
        {
            return i;
        }
    }

    return -1;
}

/**
 * Sets the timeout field of an inflight command to the current time plus offset for
 * the particular message type
 */
static void acmp_update_inflight_timeout(int entity_type, avb_1722_1_acmp_inflight_command *inflight, unsigned int message_type)
{
    // Must check the message type is a valid value before doing the timeout array access
    if ((message_type % 2 == 0) && (message_type <= 12))
    {
        inflight->timeout = acmp_centisecond_counter[entity_type] + avb_1722_1_acmp_inflight_timeouts[message_type/2];
    }
    else
    {
        inflight->timeout = 0;
    }
}

void acmp_set_inflight_retry(int entity_type, unsigned int message_type, int inflight_idx)
{
    avb_1722_1_acmp_inflight_command *inflight = acmp_get_inflight_list(entity_type);

    acmp_update_inflight_timeout(entity_type, &inflight[inflight_idx], message_type);

    inflight[inflight_idx].retried = 1;
}

void acmp_add_inflight(int entity_type, unsigned int message_type, unsigned short original_sequence_id)
{
    int i;
    avb_1722_1_acmp_inflight_command *inflight = acmp_get_inflight_list(entity_type);

    for (i = 0; i < AVB_1722_1_MAX_INFLIGHT_COMMANDS; i++)
    {
        if (inflight[i].in_use) continue;

        inflight[i].in_use = 1;
        inflight[i].retried = 0;

        switch (entity_type)
        {
            case CONTROLLER: inflight[i].command = acmp_controller_cmd_resp; break;
            case LISTENER: inflight[i].command = acmp_listener_rcvd_cmd_resp; break;
        }

        inflight[i].command.message_type = message_type;
        inflight[i].original_sequence_id = original_sequence_id;

        acmp_update_inflight_timeout(entity_type, &inflight[i], message_type);

        return;
    }

    // TODO: Return error if inflight command list is full
}

avb_1722_1_acmp_inflight_command *acmp_remove_inflight(int entity_type)
{
    avb_1722_1_acmp_cmd_resp *acmp_command;
    avb_1722_1_acmp_inflight_command *inflight = acmp_get_inflight_list(entity_type);
    int index;
    avb_1722_1_acmp_inflight_command *result = 0;

    switch (entity_type)
    {
        case CONTROLLER: acmp_command = &acmp_controller_cmd_resp; break;
        case LISTENER: acmp_command = &acmp_listener_rcvd_cmd_resp; break;
    }

    index = acmp_get_inflight_from_sequence_id(entity_type, acmp_command->sequence_id);

    if (index >= 0)
    {
        inflight[index].in_use = 0;
        result = &inflight[index];
    }
    else
    {
#ifdef AVB_1722_1_ACMP_DEBUG_INFLIGHT
        debug_printf("ACMP %s: Trying to find entry for seq id: %d but it doesn't exist\n",
                        (CONTROLLER == entity_type) ? "Controller" : "Listener",
                        acmp_command->sequence_id);
#endif
    }

    return result;
}

int acmp_check_inflight_command_timeouts(int entity_type)
{
    int i;
    avb_1722_1_acmp_inflight_command *inflight = acmp_get_inflight_list(entity_type);

    for (i = 0; i < AVB_1722_1_MAX_INFLIGHT_COMMANDS; i++)
    {
        if (inflight[i].in_use)
        {
            if (acmp_centisecond_counter[entity_type] >= inflight[i].timeout) return i;
        }
    }

    return -1;
}

void acmp_set_talker_response(void)
{
    int talker = acmp_talker_rcvd_cmd_resp.talker_unique_id;

    acmp_talker_rcvd_cmd_resp.stream_id = acmp_talker_streams[talker].stream_id;
    memcpy(acmp_talker_rcvd_cmd_resp.stream_dest_mac, acmp_talker_streams[talker].destination_mac, 6);

    acmp_talker_rcvd_cmd_resp.connection_count = acmp_talker_streams[talker].connection_count;
}



void avb_1722_1_controller_connect(const_guid_ref_t talker_guid, const_guid_ref_t listener_guid, int talker_id, int listener_id, CLIENT_INTERFACE(ethernet_if, i_eth))
{
    acmp_controller_connect_disconnect(ACMP_CMD_CONNECT_RX_COMMAND, talker_guid, listener_guid, talker_id, listener_id, i_eth);
}

void avb_1722_1_controller_disconnect(const_guid_ref_t talker_guid, const_guid_ref_t listener_guid, int talker_id, int listener_id, CLIENT_INTERFACE(ethernet_if, i_eth))
{
    acmp_controller_connect_disconnect(ACMP_CMD_DISCONNECT_RX_COMMAND, talker_guid, listener_guid, talker_id, listener_id, i_eth);
}

void avb_1722_1_controller_disconnect_all_listeners(int talker_id, CLIENT_INTERFACE(ethernet_if, i_eth))
{
    if (acmp_talker_streams[talker_id].stream_id.l != 0)
    {
        if (acmp_talker_streams[talker_id].connection_count > 0)
        {
            for (int i = 0; i < AVB_1722_1_MAX_LISTENERS_PER_TALKER; i++)
            {
                if (acmp_talker_streams[talker_id].connected_listeners[i].guid.l != 0)
                {
                    avb_1722_1_controller_disconnect(&my_guid, &acmp_talker_streams[talker_id].connected_listeners[i].guid, talker_id, i, i_eth);
                }
            }
        }
    }
}

void avb_1722_1_controller_disconnect_talker(int listener_id, CLIENT_INTERFACE(ethernet_if, i_eth))
{
    if (acmp_listener_streams[listener_id].stream_id.l != 0)
    {
        if (acmp_listener_streams[listener_id].connected)
        {
            avb_1722_1_controller_disconnect(&acmp_listener_streams[listener_id].talker_guid,
                                             &my_guid,
                                             acmp_listener_streams[listener_id].talker_unique_id,
                                             listener_id,
                                             i_eth);
        }
    }
}

static void store_rcvd_cmd_resp(avb_1722_1_acmp_cmd_resp* store, avb_1722_1_acmp_packet_t* pkt)
{
    get_64(store->stream_id.c, pkt->stream_id);
    get_64(store->controller_guid.c, pkt->controller_guid);
    get_64(store->listener_guid.c, pkt->listener_guid);
    get_64(store->talker_guid.c, pkt->talker_guid);
    store->talker_unique_id = ntoh_16(pkt->talker_unique_id);
    store->listener_unique_id = ntoh_16(pkt->listener_unique_id);
    store->connection_count = ntoh_16(pkt->connection_count);
    store->sequence_id = ntoh_16(pkt->sequence_id);
    store->flags = ntoh_16(pkt->flags);
    store->vlan_id = ntoh_16(pkt->vlan_id);
    memcpy(store->stream_dest_mac, pkt->dest_mac, 6);
    store->message_type = GET_1722_1_MSG_TYPE(&(pkt->header));
    store->status = GET_1722_1_VALID_TIME(&(pkt->header));
}

#if AVB_1722_1_FAST_CONNECT_ENABLED
void acmp_listener_store_fast_connect_info(int unique_id, guid_t *controller_guid, guid_t *talker_guid, unsigned short talker_unique_id)
{
    if (fl_readDataPage(0, (unsigned char *)avb_1722_1_buf) == 0)
    {
        avb_1722_1_acmp_fast_connect_persist_state *info = (avb_1722_1_acmp_fast_connect_persist_state*) &avb_1722_1_buf[0];
        unsigned int bitfield_temp = info->info_present_bitfield;

        if (bitfield_temp == 0xFFFFFFFF)
        {
            debug_printf("First word empty\n");
            bitfield_temp = 0;
        }
        else
        {
            fl_eraseDataSector(0);
        }

        bitfield_temp |= 1 << unique_id;
        info->info_present_bitfield = bitfield_temp;
        memcpy(&info->talkers[unique_id].controller_guid, controller_guid, sizeof(guid_t));
        memcpy(&info->talkers[unique_id].talker_guid, talker_guid, sizeof(guid_t));
        info->talkers[unique_id].talker_unique_id = talker_unique_id;
        info->talkers[unique_id].talker_active = 0;

        fl_writeDataPage(0, (unsigned char *)avb_1722_1_buf);

        unsigned long long tguid = talker_guid->l;
        debug_printf("\nWrote fast connect info for Listener %d connected to Talker %d with GUID 0x%x%x\n"
            , unique_id, talker_unique_id, (unsigned) (tguid >> 32), (unsigned) tguid);
    }
    else {
        debug_printf("Couldn't read from data partition page 0\n");
    }
}

void acmp_listener_erase_fast_connect_info(int unique_id)
{
    if (fl_readDataPage(0, (unsigned char *)avb_1722_1_buf) == 0)
    {
        avb_1722_1_acmp_fast_connect_persist_state *info = (avb_1722_1_acmp_fast_connect_persist_state*) &avb_1722_1_buf[0];
        unsigned int bitfield_temp = info->info_present_bitfield;

        if (bitfield_temp != 0xFFFFFFFF)
        {
            fl_eraseDataSector(0);

            bitfield_temp &= ~(1 << unique_id);
            info->info_present_bitfield = bitfield_temp;
            memset(&info->talkers[unique_id], 0xFF, sizeof(avb_1722_1_acmp_fast_connect_talker_info));

            fl_writeDataPage(0, (unsigned char *)avb_1722_1_buf);

            debug_printf("Erased fast connect for Listener %d\n", unique_id);

        }
    }
}

static int acmp_listener_read_fast_connect_info(unsigned char buffer[256])
{
    if (fl_readDataPage(0, buffer) == 0)
    {
        return 0;
    }
    else {
        return 1;
    }
}

/* Call this function repeatedly to check if the Talker is active that the Listener should connect to
 * When the active Talker is detected send ACMP_CMD_CONNECT_TX_COMMAND to connect the Listener to the streams
 * advertised by the Talker
 * This implements the spec: IEEE 1722 standard page 274:
 * Fast connect mode attempts to re-establish the connection by the AVDECC Listener sending a CONNECT_TX_COMMAND to the AVDECC Talker.
 * This command follows the normal timeout periods and retry for the protocol.
 * However, on a second timeout, since this was not initiated by an AVDECC Controller Entity, the AVDECC Listener does not send a message to the AVDECC Controller.
 * Instead, the AVDECC Listener shall start using ADP discovery to listen for the AVDECC Talker to appear on the network and will retry the connection again at that time."
 */
void acmp_execute_fast_connect(CLIENT_INTERFACE(ethernet_tx_if, i_eth), int ti) {

    if(avb_1722_1_entity_database_find(&fast_connect_info.talkers[ti].talker_guid) != AVB_1722_1_MAX_ENTITIES) {   
       // update tthe acmp_listener_rcvd_cmd_resp
       memcpy(&acmp_listener_rcvd_cmd_resp.controller_guid, &fast_connect_info.talkers[ti].controller_guid, sizeof(guid_t));
       memcpy(&acmp_listener_rcvd_cmd_resp.talker_guid, &fast_connect_info.talkers[ti].talker_guid, sizeof(guid_t));
       memcpy(&acmp_listener_rcvd_cmd_resp.listener_guid, &my_guid, sizeof(guid_t));
       acmp_listener_rcvd_cmd_resp.talker_unique_id = fast_connect_info.talkers[ti].talker_unique_id;
       acmp_listener_rcvd_cmd_resp.listener_unique_id = ti;
       acmp_listener_rcvd_cmd_resp.flags = AVB_1722_1_ACMP_FLAGS_FAST_CONNECT;

       fast_connect_info.talkers[ti].talker_active = 1; // set flag 

       // Talker is active
       unsigned long long tguid = fast_connect_info.talkers[ti].talker_guid.l;
       debug_printf("Fast Connect: Found Talker %d with GUID 0x%x%x\n"
                    ,fast_connect_info.talkers[ti].talker_unique_id, (unsigned) (tguid >> 32), (unsigned) tguid);

       unsigned long long lguid = acmp_listener_rcvd_cmd_resp.listener_guid.l;
       debug_printf("Issuing fast connect for Listener 0x%x%x by sending ACMP_CMD_CONNECT_TX_COMMAND\n", (unsigned) (lguid >> 32), (unsigned) lguid);

       // send command
       acmp_send_command(LISTENER, ACMP_CMD_CONNECT_TX_COMMAND, &acmp_listener_rcvd_cmd_resp, FALSE, -1, i_eth);
        
    } 
}

// Return 1 if fast connect info was found.
int acmp_start_fast_connect(CLIENT_INTERFACE(ethernet_tx_if, i_eth))
{
    unsigned char flash_buf[256];

    debug_printf("Fast Connect: Starting...\n");

    if (acmp_listener_read_fast_connect_info(flash_buf) == 0)
    {
        // update fast_connect_info
        memcpy(&fast_connect_info, flash_buf, sizeof(avb_1722_1_acmp_fast_connect_persist_state));

        if (flash_buf[3] == 0xFF) {
            debug_printf("Fast Connect: ERROR: no valid data in flash\n");
            return 0;
        }

        debug_printf("Fast Connect: Finished reading fast connect information from flash:\n");

        for (int i=0; i < AVB_1722_1_MAX_LISTENERS; i++)
        {
            if ((fast_connect_info.info_present_bitfield >> i) & 1)
            {

                unsigned long long tguid = fast_connect_info.talkers[i].talker_guid.l;
                unsigned long long lguid = my_guid.l;
                debug_printf("  Talker GUID:      0x%x%x\n",(unsigned) (tguid >> 32), (unsigned) tguid);
                debug_printf("  Listener GUID:    0x%x%x\n",(unsigned) (lguid >> 32), (unsigned) lguid);
                debug_printf("  Listener index:   %d\n", i);

                // first excution of 
                acmp_execute_fast_connect(i_eth, i);

                return 1;
            } else {
                debug_printf("  Fast connect info is invalid\n");
                return 0;
            }
        }
    } else {
        debug_printf("Fast Connect: ERROR: Flash Data partition does not exist\n");
        return 0;
    }
    return 0;
}
#endif

/**
 * Returns 1 if the listener unique id in a received command is within a valid range.
 *
 * Else returns 0.
 */
unsigned acmp_listener_valid_listener_unique(void)
{
    return acmp_listener_rcvd_cmd_resp.listener_unique_id < AVB_1722_1_MAX_LISTENERS;
}

/**
 * Sets all fields in the listener stream info entry with unique_id to zero
 */
void acmp_zero_listener_stream_info(int unique_id)
{
    memset(&acmp_listener_streams[unique_id], 0, sizeof(avb_1722_1_acmp_listener_stream_info));
}

void acmp_add_listener_stream_info(void)
{
    int unique_id = acmp_listener_rcvd_cmd_resp.listener_unique_id;

    acmp_listener_streams[unique_id].connected = 1;
    memcpy(acmp_listener_streams[unique_id].destination_mac, acmp_listener_rcvd_cmd_resp.stream_dest_mac, 6);
    acmp_listener_streams[unique_id].stream_id = acmp_listener_rcvd_cmd_resp.stream_id;
    acmp_listener_streams[unique_id].talker_guid = acmp_listener_rcvd_cmd_resp.talker_guid;
    acmp_listener_streams[unique_id].talker_unique_id = acmp_listener_rcvd_cmd_resp.talker_unique_id;
}

avb_1722_1_acmp_status_t acmp_listener_get_state(void)
{
    int unique_id = acmp_listener_rcvd_cmd_resp.listener_unique_id;

    acmp_listener_rcvd_cmd_resp.stream_id = acmp_listener_streams[unique_id].stream_id;
    memcpy(acmp_listener_rcvd_cmd_resp.stream_dest_mac, acmp_listener_streams[unique_id].destination_mac, 6);
    acmp_listener_rcvd_cmd_resp.talker_guid = acmp_listener_streams[unique_id].talker_guid;
    acmp_listener_rcvd_cmd_resp.talker_unique_id = acmp_listener_streams[unique_id].talker_unique_id;

    acmp_listener_rcvd_cmd_resp.connection_count = acmp_listener_streams[unique_id].connected;
    if (acmp_listener_rcvd_cmd_resp.stream_id.l)
    {
        acmp_listener_rcvd_cmd_resp.vlan_id = AVB_DEFAULT_VLAN;
    }
    else
    {
        acmp_listener_rcvd_cmd_resp.vlan_id = 0;
    }


    /* If for some reason we couldn't get the state, we could return a STATE_UNVAILABLE status instead */

    return ACMP_STATUS_SUCCESS;
}

avb_1722_1_acmp_status_t acmp_talker_get_state(void)
{
    int unique_id = acmp_talker_rcvd_cmd_resp.talker_unique_id;

    acmp_talker_rcvd_cmd_resp.stream_id = acmp_talker_streams[unique_id].stream_id;
    memcpy(acmp_talker_rcvd_cmd_resp.stream_dest_mac, acmp_talker_streams[unique_id].destination_mac, 6);
    acmp_talker_rcvd_cmd_resp.connection_count = acmp_talker_streams[unique_id].connection_count;
    if (acmp_talker_rcvd_cmd_resp.stream_id.l)
    {
        acmp_talker_rcvd_cmd_resp.vlan_id = AVB_DEFAULT_VLAN;
    }
    else
    {
        acmp_talker_rcvd_cmd_resp.vlan_id = 0;
    }

    return ACMP_STATUS_SUCCESS;
}

avb_1722_1_acmp_status_t acmp_talker_get_connection(void)
{
    int unique_id = acmp_talker_rcvd_cmd_resp.talker_unique_id;
    unsigned short connection = acmp_talker_rcvd_cmd_resp.connection_count;

    // Check if connection exists
    if (connection >= AVB_1722_1_MAX_LISTENERS_PER_TALKER)
    {
        return ACMP_STATUS_STATE_UNAVAILABLE;
    }
    else if (acmp_talker_streams[unique_id].connected_listeners[connection].guid.l == 0)
    {
        return ACMP_STATUS_NO_SUCH_CONNECTION;
    }

    acmp_talker_rcvd_cmd_resp.stream_id = acmp_talker_streams[unique_id].stream_id;
    memcpy(acmp_talker_rcvd_cmd_resp.stream_dest_mac, acmp_talker_streams[unique_id].destination_mac, 6);

    acmp_talker_rcvd_cmd_resp.listener_guid.l = acmp_talker_streams[unique_id].connected_listeners[connection].guid.l;
    acmp_talker_rcvd_cmd_resp.listener_unique_id = acmp_talker_streams[unique_id].connected_listeners[connection].unique_id;
    acmp_talker_rcvd_cmd_resp.vlan_id = AVB_DEFAULT_VLAN;

    return ACMP_STATUS_SUCCESS;
}

void acmp_add_talker_stream_info(void)
{
    int i;
    int unique_id = acmp_talker_rcvd_cmd_resp.talker_unique_id;

    // Check listener_guid and listener_unique_id are not in connected_listeners as per 8.2.2.6.2.2. of the spec
    for (i = 0; i < AVB_1722_1_MAX_LISTENERS_PER_TALKER; i++)
    {
        if (acmp_talker_streams[unique_id].connected_listeners[i].guid.l == acmp_talker_rcvd_cmd_resp.listener_guid.l &&
                acmp_talker_streams[unique_id].connected_listeners[i].unique_id == acmp_talker_rcvd_cmd_resp.listener_unique_id)
        {
            // Listener already connected
            return;
        }
    }

    for (i = 0; i < AVB_1722_1_MAX_LISTENERS_PER_TALKER; i++)
    {
        if (acmp_talker_streams[unique_id].connected_listeners[i].guid.l == 0) // The first empty connected_listeners field
        {
            acmp_talker_streams[unique_id].connected_listeners[i].guid.l = acmp_talker_rcvd_cmd_resp.listener_guid.l;
            acmp_talker_streams[unique_id].connected_listeners[i].unique_id = acmp_talker_rcvd_cmd_resp.listener_unique_id;
            acmp_talker_streams[unique_id].connection_count++;
            break;
        }
    }
}

void acmp_remove_talker_stream_info(void)
{
    int i;
    int unique_id = acmp_talker_rcvd_cmd_resp.talker_unique_id;

    for (i = 0; i < AVB_1722_1_MAX_LISTENERS_PER_TALKER; i++)
    {
        if (acmp_talker_streams[unique_id].connected_listeners[i].guid.l == acmp_talker_rcvd_cmd_resp.listener_guid.l &&
                acmp_talker_streams[unique_id].connected_listeners[i].unique_id == acmp_talker_rcvd_cmd_resp.listener_unique_id)
        {
            acmp_talker_streams[unique_id].connected_listeners[i].guid.l = 0;
            acmp_talker_streams[unique_id].connected_listeners[i].unique_id = 0;
            acmp_talker_streams[unique_id].connection_count--;

#ifdef AVB_1722_1_ENABLE_ASSERTIONS
            assert(acmp_talker_streams[unique_id].connection_count >= 0);
#endif
            return;
        }
    }
}

/**
 * Returns 1 if the talker unique id in a received command is within a valid range.
 *
 * Else returns 0.
 */
unsigned acmp_talker_valid_talker_unique(void)
{
#if (AVB_NUM_SOURCES > 0)
        return acmp_talker_rcvd_cmd_resp.talker_unique_id < AVB_1722_1_MAX_TALKERS;
#else
        return 0;
#endif
}

static void process_avb_1722_1_acmp_controller_packet(unsigned char message_type, avb_1722_1_acmp_packet_t* pkt)
{
    int inflight_index = 0;

    if (acmp_controller_state != ACMP_CONTROLLER_WAITING) return;
    if (compare_guid(pkt->controller_guid, &my_guid) == 0) return;

    inflight_index = acmp_get_inflight_from_sequence_id(CONTROLLER, ntoh_16(pkt->sequence_id));
    if (inflight_index < 0) return; // We don't have an inflight entry for this command

    if (message_type != (acmp_controller_inflight_commands[inflight_index].command.message_type + 1)) return;

    store_rcvd_cmd_resp(&acmp_controller_cmd_resp, pkt);

    switch (message_type)
    {
        case ACMP_CMD_CONNECT_RX_RESPONSE:
            acmp_controller_state = ACMP_CONTROLLER_CONNECT_RX_RESPONSE;
            break;
        case ACMP_CMD_DISCONNECT_RX_RESPONSE:
            acmp_controller_state = ACMP_CONTROLLER_DISCONNECT_RX_RESPONSE;
            break;
        case ACMP_CMD_GET_TX_STATE_RESPONSE:
            acmp_controller_state = ACMP_CONTROLLER_GET_RX_STATE_RESPONSE;
            break;
        case ACMP_CMD_GET_RX_STATE_RESPONSE:
            acmp_controller_state = ACMP_CONTROLLER_GET_RX_STATE_RESPONSE;
            break;
        case ACMP_CMD_GET_TX_CONNECTION_RESPONSE:
            acmp_controller_state = ACMP_CONTROLLER_GET_TX_CONNECTION_RESPONSE;
            break;
        default:
        {
            acmp_controller_state = ACMP_CONTROLLER_WAITING;
            break;
        }
    }
}

static void process_avb_1722_1_acmp_talker_packet(unsigned char message_type, avb_1722_1_acmp_packet_t* pkt)
{
    if (compare_guid(pkt->talker_guid, &my_guid) == 0) return;
    if (acmp_talker_state != ACMP_TALKER_WAITING) return;

    store_rcvd_cmd_resp(&acmp_talker_rcvd_cmd_resp, pkt);

    switch (message_type)
    {
    case ACMP_CMD_CONNECT_TX_COMMAND:
        acmp_talker_state = ACMP_TALKER_CONNECT;
        break;
    case ACMP_CMD_DISCONNECT_TX_COMMAND:
        acmp_talker_state = ACMP_TALKER_DISCONNECT;
        break;
    case ACMP_CMD_GET_TX_STATE_COMMAND:
        acmp_talker_state = ACMP_TALKER_GET_STATE;
        break;
    case ACMP_CMD_GET_TX_CONNECTION_COMMAND:
        acmp_talker_state = ACMP_TALKER_GET_CONNECTION;
        break;
    }
}

static void process_avb_1722_1_acmp_listener_packet(unsigned char message_type, avb_1722_1_acmp_packet_t* pkt)
{
    if (compare_guid(pkt->listener_guid, &my_guid)==0) return;
    if (acmp_listener_state != ACMP_LISTENER_WAITING) return;

    store_rcvd_cmd_resp(&acmp_listener_rcvd_cmd_resp, pkt);

    switch (message_type)
    {
    case ACMP_CMD_CONNECT_TX_RESPONSE:
        acmp_listener_state = ACMP_LISTENER_CONNECT_TX_RESPONSE;
        break;
    case ACMP_CMD_DISCONNECT_TX_RESPONSE:
        acmp_listener_state = ACMP_LISTENER_DISCONNECT_TX_RESPONSE;
        break;
    case ACMP_CMD_CONNECT_RX_COMMAND:
        acmp_listener_state = ACMP_LISTENER_CONNECT_RX_COMMAND;
        break;
    case ACMP_CMD_DISCONNECT_RX_COMMAND:
        acmp_listener_state = ACMP_LISTENER_DISCONNECT_RX_COMMAND;
        break;
    case ACMP_CMD_GET_RX_STATE_COMMAND:
        acmp_listener_state = ACMP_LISTENER_GET_STATE;
        break;
    }
}

void process_avb_1722_1_acmp_packet(avb_1722_1_acmp_packet_t* pkt, CLIENT_INTERFACE(ethernet_if, i_eth))
{
    unsigned char message_type = GET_1722_1_MSG_TYPE(((avb_1722_1_packet_header_t*)pkt));

    switch (message_type)
    {
        // Talker messages
        case ACMP_CMD_CONNECT_TX_COMMAND:
        case ACMP_CMD_DISCONNECT_TX_COMMAND:
        case ACMP_CMD_GET_TX_STATE_COMMAND:
        case ACMP_CMD_GET_TX_CONNECTION_COMMAND:
        {
            process_avb_1722_1_acmp_talker_packet(message_type, pkt);
            return;
        }
        // Listener messages
        case ACMP_CMD_CONNECT_TX_RESPONSE:
        case ACMP_CMD_DISCONNECT_TX_RESPONSE:
        case ACMP_CMD_CONNECT_RX_COMMAND:
        case ACMP_CMD_DISCONNECT_RX_COMMAND:
        case ACMP_CMD_GET_RX_STATE_COMMAND:
        {
            process_avb_1722_1_acmp_listener_packet(message_type, pkt);
            return;
        }
        // Controller messages
        case ACMP_CMD_CONNECT_RX_RESPONSE:
        case ACMP_CMD_DISCONNECT_RX_RESPONSE:
        case ACMP_CMD_GET_RX_STATE_RESPONSE:
        case ACMP_CMD_GET_TX_STATE_RESPONSE:
        case ACMP_CMD_GET_TX_CONNECTION_RESPONSE:
        {
            process_avb_1722_1_acmp_controller_packet(message_type, pkt);
            return;
        }
    }
}

void avb_1722_1_talker_set_mac_address(unsigned talker_unique_id, unsigned char macaddr[])
{
    if (talker_unique_id < AVB_1722_1_MAX_TALKERS)
    {
        memcpy(acmp_talker_streams[talker_unique_id].destination_mac, macaddr, 6);
    }
}

void avb_1722_1_talker_set_stream_id(unsigned talker_unique_id, unsigned streamId[2])
{
    if (talker_unique_id < AVB_1722_1_MAX_TALKERS)
    {
        acmp_talker_streams[talker_unique_id].stream_id.l = (unsigned long long)streamId[1] + (((unsigned long long)streamId[0]) << 32);
    }
}

#undef CONTROLLER
#undef LISTENER

#undef TRUE
#undef FALSE
