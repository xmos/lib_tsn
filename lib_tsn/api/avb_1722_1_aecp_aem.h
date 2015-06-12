// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef AVB_1722_1_AECP_AEM_H_
#define AVB_1722_1_AECP_AEM_H_

#include "avb_1722_1_protocol.h"
#include "avb_1722_1_default_conf.h"

typedef enum {
    AECP_AEM_CMD_ACQUIRE_ENTITY = 0,
    AECP_AEM_CMD_LOCK_ENTITY = 1,
    AECP_AEM_CMD_ENTITY_AVAILABLE = 2,
    AECP_AEM_CMD_CONTROLLER_AVAILABLE = 3,
    AECP_AEM_CMD_READ_DESCRIPTOR = 4,
    AECP_AEM_CMD_WRITE_DESCRIPTOR = 5,
    AECP_AEM_CMD_SET_CONFIGURATION = 6,
    AECP_AEM_CMD_GET_CONFIGURATION = 7,
    AECP_AEM_CMD_SET_STREAM_FORMAT = 8,
    AECP_AEM_CMD_GET_STREAM_FORMAT = 9,
    AECP_AEM_CMD_SET_VIDEO_FORMAT = 10,
    AECP_AEM_CMD_GET_VIDEO_FORMAT = 11,
    AECP_AEM_CMD_SET_SENSOR_FORMAT = 12,
    AECP_AEM_CMD_GET_SENSOR_FORMAT = 13,
    AECP_AEM_CMD_SET_STREAM_INFO = 14,
    AECP_AEM_CMD_GET_STREAM_INFO = 15,
    AECP_AEM_CMD_SET_NAME = 16,
    AECP_AEM_CMD_GET_NAME = 17,
    AECP_AEM_CMD_SET_ASSOCIATION_ID = 18,
    AECP_AEM_CMD_GET_ASSOCIATION_ID = 19,
    AECP_AEM_CMD_SET_SAMPLING_RATE = 20,
    AECP_AEM_CMD_GET_SAMPLING_RATE = 21,
    AECP_AEM_CMD_SET_CLOCK_SOURCE = 22,
    AECP_AEM_CMD_GET_CLOCK_SOURCE = 23,
    AECP_AEM_CMD_SET_CONTROL = 24,
    AECP_AEM_CMD_GET_CONTROL = 25,
    AECP_AEM_CMD_INCREMENT_CONTROL = 26,
    AECP_AEM_CMD_DECREMENT_CONTROL = 27,
    AECP_AEM_CMD_SET_SIGNAL_SELECTOR = 28,
    AECP_AEM_CMD_GET_SIGNAL_SELECTOR = 29,
    AECP_AEM_CMD_SET_MIXER = 30,
    AECP_AEM_CMD_GET_MIXER = 31,
    AECP_AEM_CMD_SET_MATRIX = 32,
    AECP_AEM_CMD_GET_MATRIX = 33,
    AECP_AEM_CMD_START_STREAMING = 34,
    AECP_AEM_CMD_STOP_STREAMING = 35,
    AECP_AEM_CMD_REGISTER_UNSOLICITED_NOTIFICATION = 36,
    AECP_AEM_CMD_DEREGISTER_UNSOLICITED_NOTIFICATION = 37,
    AECP_AEM_CMD_IDENTIFY_NOTIFICATION = 38,
    AECP_AEM_CMD_GET_AVB_INFO = 39,
    AECP_AEM_CMD_GET_AS_PATH = 40,
    AECP_AEM_CMD_GET_COUNTERS = 41,
    AECP_AEM_CMD_REBOOT = 42,
    AECP_AEM_CMD_GET_AUDIO_MAP = 43,
    AECP_AEM_CMD_ADD_AUDIO_MAPPINGS = 44,
    AECP_AEM_CMD_REMOVE_AUDIO_MAPPINGS = 45,
    AECP_AEM_CMD_GET_VIDEO_MAP = 46,
    AECP_AEM_CMD_ADD_VIDEO_MAPPINGS = 47,
    AECP_AEM_CMD_REMOVE_VIDEO_MAPPINGS = 48,
    AECP_AEM_CMD_GET_SENSOR_MAP = 49,
    AECP_AEM_CMD_ADD_SENSOR_MAPPINGS = 50,
    AECP_AEM_CMD_REMOVE_SENSOR_MAPPINGS = 51,
    AECP_AEM_CMD_START_OPERATION = 52,
    AECP_AEM_CMD_ABORT_OPERATION = 53,
    AECP_AEM_CMD_OPERATION_STATUS = 54,
    AECP_AEM_CMD_AUTH_ADD_KEY = 55,
    AECP_AEM_CMD_AUTH_DELETE_KEY = 56,
    AECP_AEM_CMD_AUTH_GET_KEY_COUNT = 57,
    AECP_AEM_CMD_AUTH_GET_KEY = 58,
    AECP_AEM_CMD_AUTHENTICATE = 59,
    AECP_AEM_CMD_DEAUTHENTICATE = 60,
} avb_1722_1_aecp_aem_cmd_code;

/** The result status of the AEM command in the response field */
typedef enum {
    AECP_AEM_STATUS_SUCCESS = 0, /**< The AVDECC Entity successfully performed the command and has valid results. */
    AECP_AEM_STATUS_NOT_IMPLEMENTED = 1, /**< The AVDECC Entity does not support the command type. */
    AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR = 2, /**< A descriptor with the descriptor_type and descriptor_index specified does not exist. */
    AECP_AEM_STATUS_ENTITY_LOCKED = 3, /**< The AVDECC Entity has been locked by another AVDECC Controller. */
    AECP_AEM_STATUS_ENTITY_ACQUIRED = 4, /**< The AVDECC Entity has been acquired by another AVDECC Controller. */
    AECP_AEM_STATUS_NOT_AUTHENTICATED = 5, /**< The AVDECC Controller is not authenticated with the AVDECC Entity. */
    AECP_AEM_STATUS_AUTHENTICATION_DISABLED = 6, /**< The AVDECC Controller is trying to use an authentication command when authentication isn’t enable on the AVDECC Entity. */
    AECP_AEM_STATUS_BAD_ARGUMENTS = 7, /**< One or more of the values in the fields of the frame were deemed to be bad by the AVDECC Entity (unsupported, incorrect combination, etc). */
    AECP_AEM_STATUS_NO_RESOURCES = 8, /**< The AVDECC Entity cannot complete the command because it does not have the resources to support it. */
    AECP_AEM_STATUS_IN_PROGRESS = 9, /**< The AVDECC Entity is processing the command and will send a second response at a later time with the result of the command. */
    AECP_AEM_STATUS_ENTITY_MISBEHAVING = 10, /**< The AVDECC Entity is generated an internal error while trying to process the command. */
    AECP_AEM_STATUS_NOT_SUPPORTED = 11, /**< The command is implemented but the target of the command is not supported. For example trying to set the value of a read-only Control. */
    AECP_AEM_STATUS_STREAM_IS_RUNNING = 12, /**< The Stream is currently streaming and the command is one which cannot be executed on an Active Stream. */
} avb_1722_1_aecp_aem_status_code;

/* 7.4.2.1. READ_DESCRIPTOR Command Format */

typedef struct {
    unsigned char configuration[2];
    unsigned char reserved[2];
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
} avb_1722_1_aem_read_descriptor_command_t;

/* 7.4.2.2. READ_DESCRIPTOR Response Format */
typedef struct {
    unsigned char configuration[2];
    unsigned char reserved[2];
    unsigned char descriptor[512];
} avb_1722_1_aem_read_descriptor_response_t;

/* 7.4.1. ACQUIRE_ENTITY Command */
typedef struct {
    unsigned char flags[4];
    unsigned char owner_guid[8];
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
} avb_1722_1_aem_acquire_entity_command_t;

#define AEM_ACQUIRE_ENTITY_PERSISTENT_FLAG(cmd)     ((cmd)->flags[3] & 1)
#define AEM_ACQUIRE_ENTITY_RELEASE_FLAG(cmd)     ((cmd)->flags[0] & 0x80)

/* 7.4.2. LOCK_ENTITY Command */
typedef struct {
    unsigned char flags[4];
    unsigned char locked_guid[8];
} avb_1722_1_aem_lock_entity_command_t;

/* 7.4.40.1 GET_AVB_INFO Command */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
} avb_1722_1_aem_get_avb_info_command_t;

/* 7.4.40.2 GET_AVB_INFO Response */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char as_grandmaster_id[8];
    unsigned char propagation_delay[4];
    unsigned char reserved[2];
    unsigned char msrp_mappings_count[2];
    unsigned char msrp_mappings[4];
} avb_1722_1_aem_get_avb_info_response_t;

/* 7.4.9.1 SET_STREAM_FORMAT Command/response */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char stream_format[8];
} avb_1722_1_aem_getset_stream_format_t;

/* 7.4.22. SET_SAMPLING_RATE Command/Response */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char sampling_rate[4];
} avb_1722_1_aem_getset_sampling_rate_t;

/* 7.4.23. SET_CLOCK_SOURCE Command/Response */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char clock_source_index[2];
    unsigned char reserved[2];
} avb_1722_1_aem_getset_clock_source_t;

#define AECP_STREAM_INFO_FLAGS_STREAM_VLAN_ID_VALID     (0x02000000)
#define AECP_STREAM_INFO_FLAGS_CONNECTED                (0x04000000)
#define AECP_STREAM_INFO_FLAGS_MSRP_FAILURE_VALID       (0x08000000)
#define AECP_STREAM_INFO_FLAGS_STREAM_DESC_MAC_VALID    (0x10000000)
#define AECP_STREAM_INFO_FLAGS_MSRP_ACC_LAT_VALID       (0x20000000)
#define AECP_STREAM_INFO_FLAGS_STREAM_ID_VALID          (0x40000000)
#define AECP_STREAM_INFO_FLAGS_STREAM_FORMAT_VALID      (0x80000000)

/* 7.4.15.1. SET_STREAM_INFO Command/Response */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char flags[4];
    unsigned char stream_format[8];
    unsigned char stream_id[8];
    unsigned char msrp_accumulated_latency[4];
    unsigned char stream_dest_mac[6];
    unsigned char msrp_failure_code;
    unsigned char reserved1;
    unsigned char msrp_failure_bridge_id[8];
    unsigned char stream_vlan_id[2];
    unsigned char reserved2[2];
} avb_1722_1_aem_getset_stream_info_t;

#define AEM_MAX_CONTROL_VALUES_LENGTH_BYTES 508

/* 7.4.25.1 SET_CONTROL */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
} avb_1722_1_aem_getset_control_t;

/* 7.4.29 SET_SIGNAL_SELECTOR */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char signal_type[2];
    unsigned char signal_index[2];
    unsigned char signal_output[2];
    unsigned char reserved[2];
} avb_1722_1_aem_getset_signal_selector_t;

/* 7.4.42 GET_COUNTERS */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char counters_valid[4];
    unsigned char counters_block[128];
} avb_1722_1_aem_get_counters_t;

#define AECP_GET_COUNTERS_CLOCK_DOMAIN_LOCKED_VALID     (0x00000001)
#define AECP_GET_COUNTERS_CLOCK_DOMAIN_UNLOCKED_VALID   (0x00000002)

#define AECP_GET_COUNTERS_CLOCK_DOMAIN_LOCKED_OFFSET    (0)
#define AECP_GET_COUNTERS_CLOCK_DOMAIN_UNLOCKED_OFFSET  (4)

/* 7.4.35.1 START_STREAMING */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
} avb_1722_1_aem_startstop_streaming_t;

/* 7.4.39.1 IDENTIFY_NOTIFICATION */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_index[2];
} avb_1722_1_aem_identify_notification_t;

/* 7.4.53 START_OPERATION Command */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char operation_id[2];
    unsigned char operation_type[2];
} avb_1722_1_aem_start_operation_t;

/* 7.4.55 OPERATION_STATUS Unsolicited Response */
typedef struct {
    unsigned char descriptor_type[2];
    unsigned char descriptor_id[2];
    unsigned char operation_id[2];
    unsigned char percent_complete[2];
} avb_1722_1_aem_operation_status_t;


#endif /* AVB_1722_1_AECP_AEM_H_ */
