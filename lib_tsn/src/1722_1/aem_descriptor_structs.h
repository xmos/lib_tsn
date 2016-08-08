// Copyright (c) 2013-2016, XMOS Ltd, All rights reserved
#include <inttypes.h>

typedef struct aem_desc_audio_unit_t
{
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t object_name[64];
    uint8_t localized_description[2];
    uint8_t clock_domain_index[2];
    uint8_t number_of_stream_input_ports[2];
    uint8_t base_stream_input_port[2];
    uint8_t number_of_stream_output_ports[2];
    uint8_t base_stream_output_port[2];
    uint8_t number_of_external_input_ports[2];
    uint8_t base_external_input_port[2];
    uint8_t number_of_external_output_ports[2];
    uint8_t base_external_output_port[2];
    uint8_t number_of_internal_input_ports[2];
    uint8_t base_internal_input_port[2];
    uint8_t number_of_internal_output_ports[2];
    uint8_t base_internal_output_port[2];
    uint8_t number_of_controls[2];
    uint8_t base_control[2];
    uint8_t number_of_signal_selectors[2];
    uint8_t base_signal_selector[2];
    uint8_t number_of_mixers[2];
    uint8_t base_mixer[2];
    uint8_t number_of_matrices[2];
    uint8_t base_matrix[2];
    uint8_t number_of_splitters[2];
    uint8_t base_splitter[2];
    uint8_t number_of_combiners[2];
    uint8_t base_combiner[2];
    uint8_t number_of_demultiplexers[2];
    uint8_t base_demultiplexer[2];
    uint8_t number_of_multiplexers[2];
    uint8_t base_multiplexer[2];
    uint8_t number_of_transcoders[2];
    uint8_t base_transcoder[2];
    uint8_t number_of_control_blocks[2];
    uint8_t base_control_block[2];
    uint8_t current_sampling_rate[4];
    uint8_t sampling_rates_offset[2];
    uint8_t sampling_rates_count[2];
    // sampling_rates
} aem_desc_audio_unit_t;

typedef struct aem_desc_control_t
{
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t object_name[64];
    uint8_t localized_description[2];
    uint8_t block_latency[4];
    uint8_t control_latency[4];
    uint8_t control_domain[2];
    uint8_t control_value_type[2];
    uint8_t control_type[8];
    uint8_t reset_time[4];
    uint8_t values_offset[2];
    uint8_t number_of_values[2];
    uint8_t signal_type[2];
    uint8_t signal_index[2];
    uint8_t signal_output[2];
    // value_details
} aem_desc_control_t;

typedef struct aem_desc_signal_selector_t
{
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t object_name[64];
    uint8_t localized_description[2];
    uint8_t block_latency[4];
    uint8_t control_latency[4];
    uint8_t control_domain[2];
    uint8_t sources_offset[2];
    uint8_t number_of_sources[2];
    uint8_t current_signal_type[2];
    uint8_t current_signal_index[2];
    uint8_t current_signal_output[2];
    uint8_t default_signal_type[2];
    uint8_t default_signal_index[2];
    uint8_t default_signal_output[2];
    // sources
} aem_desc_signal_selector_t;

typedef struct aem_desc_clock_domain_t
{
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t object_name[64];
    uint8_t localized_description[2];
    uint8_t clock_source_index[2];
    uint8_t clock_sources_offset[2];
    uint8_t clock_sources_count[2];
    // clock_sources
} aem_desc_clock_domain_t;

typedef struct aem_desc_audio_cluster_t {
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t object_name[64];
    uint8_t localized_description[2];
    uint8_t signal_type[2];
    uint8_t signal_index[2];
    uint8_t signal_output[2];
    uint8_t path_latency[4];
    uint8_t block_latency[4];
    uint8_t channel_count[2];
    uint8_t format[1];
} aem_desc_audio_cluster_t;

typedef struct aem_desc_stream_input_output_t {
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t object_name[64];
    uint8_t localized_description[2];
    uint8_t clock_domain_index[2];
    uint8_t stream_flags[2];
    uint8_t current_format[8];
    uint8_t formats_offset[2];
    uint8_t number_of_formats[2];
    uint8_t backup_talker_entity_id_0[8];
    uint8_t backup_talker_unique_id_0[2];
    uint8_t backup_talker_entity_id_1[8];
    uint8_t backup_talker_unique_id_1[2];
    uint8_t backup_talker_entity_id_2[8];
    uint8_t backup_talker_unique_id_2[2];
    uint8_t backedup_talker_entity_id[8];
    uint8_t backedup_talker_unique_id[2];
    uint8_t avb_interface_index[2];
    uint8_t buffer_length[4];
    #define MAX_NUM_STREAM_FORMATS 16
    uint8_t formats[16*MAX_NUM_STREAM_FORMATS];
} aem_desc_stream_input_output_t;

typedef struct aem_audio_map_format_t {
    uint8_t mapping_stream_index[2];
    uint8_t mapping_stream_channel[2];
    uint8_t mapping_cluster_offset[2];
    uint8_t mapping_cluster_channel[2];
} aem_audio_map_format_t;

typedef struct aem_desc_audio_map_t {
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t mappings_offset[2];
    uint8_t number_of_mappings[2];
    #define MAX_NUM_MAPPINGS 8
    aem_audio_map_format_t mappings[MAX_NUM_MAPPINGS];
} aem_desc_audio_map_t;

typedef struct aem_desc_stream_port_input_output_t {
    uint8_t descriptor_type[2];
    uint8_t descriptor_index[2];
    uint8_t clock_domain_index[2];
    uint8_t port_flags[2];
    uint8_t number_of_controls[2];
    uint8_t base_control[2];
    uint8_t number_of_clusters[2];
    uint8_t base_cluster[2];
    uint8_t number_of_maps[2];
    uint8_t base_map[2];
} aem_desc_stream_port_input_output_t;
