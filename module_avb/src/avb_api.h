#ifndef _api_h_
#define _api_h_
#include <xccompat.h>
#include "debug_print.h"
#include "xc2compat.h"
#include "avb_control_types.h"
#include "avb_stream.h"
#include "media_clock_server.h"
#include "string.h"

#ifdef __XC__
interface avb_interface {
  void initialise(void);
  /** Intended for internal use within client interface get and set extensions only */
  avb_source_info_t _get_source_info(unsigned source_num);
  /** Intended for internal use within client interface get and set extensions only */
  void _set_source_info(unsigned source_num, avb_source_info_t info);
  /** Intended for internal use within client interface get and set extensions only */
  avb_sink_info_t _get_sink_info(unsigned sink_num);
  /** Intended for internal use within client interface get and set extensions only */
  void _set_sink_info(unsigned sink_num, avb_sink_info_t info);
  /** Intended for internal use within client interface get and set extensions only */
  media_clock_info_t _get_media_clock_info(unsigned clock_num);
  /** Intended for internal use within client interface get and set extensions only */
  void _set_media_clock_info(unsigned clock_num, media_clock_info_t info);
};


extends client interface avb_interface : {
  /** Get the format of an AVB source.
   *  \param source_num the local source number
   *  \param format     the format of the stream
   *  \param rate       the sample rate of the stream in Hz
   */
  static inline int get_source_format(client interface avb_interface i, unsigned source_num,
                        enum avb_stream_format_t &format,
                        int &rate)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    format = source.stream.format;
    rate = source.stream.rate;
    return 1;
  }

  /** Set the format of an AVB source.
   *
   *  The AVB source format covers the encoding and sample rate of the source.
   *  Currently the format is limited to a single encoding MBLA 24 bit signed
   *  integers.
   *
   *  This setting will not take effect until the next time the source
   *  state moves from disabled to potential.
   *
   *  \param source_num the local source number
   *  \param format     the format of the stream
   *  \param rate       the sample rate of the stream in Hz
   */
  static inline int set_source_format(client interface avb_interface i, unsigned source_num,
                        enum avb_stream_format_t format, int rate)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    if (source.stream.state != AVB_SOURCE_STATE_DISABLED)
      return 0;
    source.stream.format = format;
    source.stream.rate = rate;
    i._set_source_info(source_num, source);
    return 1;
  }

  /** Get the channel count of an AVB source.
   *  \param source_num   the local source number
   *  \param channels     the number of channels
   */
  static inline int get_source_channels(client interface avb_interface i, unsigned source_num,
                          int &channels)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    channels = source.stream.num_channels;
    return 1;
  }

  /** Set the channel count of an AVB source.
   *
   *  Sets the number of channels in the stream.
   *
   *  This setting will not take effect until the next time the source
   *  state moves from disabled to potential.
   *
   *  \param source_num   the local source number
   *  \param channels     the number of channels
   */
  static inline int set_source_channels(client interface avb_interface i, unsigned source_num,
                          int channels)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    if (source.stream.state != AVB_SOURCE_STATE_DISABLED)
      return 0;
    source.stream.num_channels = channels;
    i._set_source_info(source_num, source);
    return 1;
  }

  /** Get the media clock of an AVB source.
   *  \param source_num   the local source number
   *  \param sync         the media clock number
   */
  static inline int get_source_sync(client interface avb_interface i, unsigned source_num,
                      int &sync)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    sync = source.stream.sync;
    return 1;
  }

  /** Set the media clock of an AVB source.
   *
   *  Sets the media clock of the stream.
   *
   *  \param source_num   the local source number
   *  \param sync         the media clock number
   */
  static inline int set_source_sync(client interface avb_interface i, unsigned source_num,
                      int sync)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    if (source.stream.state != AVB_SOURCE_STATE_DISABLED)
      return 0;
    source.stream.sync = sync;
    i._set_source_info(source_num, source);
    return 1;
  }

  /** Get the presentation time offset of an AVB source.
   *  \param source_num       the local source number to set
   *  \param presentation     the presentation offset in ms
   */
  static inline int get_source_presentation(client interface avb_interface i, unsigned source_num,
                              int &presentation)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    presentation = source.presentation;
    return 1;
  }

  /** Set the presentation time offset of an AVB source.
   *
   *  Sets the presentation time offset of a source i.e. the
   *  time after sampling that the stream should be played. The default
   *  value for this is 2ms.
   *
   *  This setting will not take effect until the next time the source
   *  state moves from disabled to potential.
   *
   *  \param source_num       the local source number to set
   *  \param presentation     the presentation offset in ms
   *
   *
   **/
  static inline int set_source_presentation(client interface avb_interface i, unsigned source_num,
                              int presentation)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    if (source.stream.state != AVB_SOURCE_STATE_DISABLED)
      return 0;
    source.presentation = presentation;
    i._set_source_info(source_num, source);
    return 1;
  }


  /** Get the destination vlan of an AVB source.
   *  \param source_num the local source number
   *  \param vlan       the destination vlan id, The media clock number
   */
  static inline int get_source_vlan(client interface avb_interface i, unsigned source_num,
                      int &vlan)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    vlan = source.reservation.vlan_id;
    return 1;
  }

  /** Set the destination vlan of an AVB source.
   *
   *  Sets the vlan that the source will transmit on. This defaults
   *  to 2.
   *
   *  This setting will not take effect until the next time the source
   *  state moves from disabled to potential.
   *
   *  \param source_num the local source number
   *  \param vlan       the destination vlan id, The media clock number
   */
  static inline int set_source_vlan(client interface avb_interface i, unsigned source_num,
                      int vlan)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    if (source.stream.state != AVB_SOURCE_STATE_DISABLED)
      return 0;
    source.reservation.vlan_id = vlan;
    i._set_source_info(source_num, source);
    return 1;
  }

  /** Get the current state of an AVB source.
   *  \param source_num the local source number
   *  \param state      the state of the source
   */
  static inline int get_source_state(client interface avb_interface i, unsigned source_num,
                       enum avb_source_state_t &state)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    state = source.stream.state;
    return 1;
  }

  /** Set the current state of an AVB source.
   *
   *  Sets the current state of an AVB source. You cannot set the
   *  state to ``ENABLED``. Changing the state to ``AVB_SOURCE_STATE_POTENTIAL`` turns the stream
   *  on and it will automatically change to ``ENABLED`` when connected to
   *  a listener and streaming.
   *
   *  \param source_num the local source number
   *  \param state      the state of the source
   */
  static inline int set_source_state(client interface avb_interface i, unsigned source_num,
                       enum avb_source_state_t state)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    source.stream.state = state;
    i._set_source_info(source_num, source);
    return 1;
  }

  /** Get the channel map of an avb source.
   *  \param source_num the local source number to set
   *  \param map the map, an array of integers giving the input FIFOs that
   *             make up the stream
   *  \param len the length of the map; should be equal to the number of channels
   *             in the stream
   */
  static inline int get_source_map(client interface avb_interface i, unsigned source_num,
                     int map[], int &len)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    len = source.stream.num_channels;
    memcpy(map, source.map, len<<2);
    return 1;
  }

  /** Set the channel map of an avb source.
   *
   *  Sets the channel map of a source i.e. the list of
   *  input FIFOs that constitute the stream.
   *
   *  This setting will not take effect until the next time the source
   *  state moves from disabled to potential.
   *
   *  \param source_num the local source number to set
   *  \param map the map, an array of integers giving the input FIFOs that
   *             make up the stream
   *  \param len the length of the map; should be equal to the number of channels
   *             in the stream
   *
   **/
  static inline int set_source_map(client interface avb_interface i, unsigned source_num,
                     int map[len], unsigned len)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    if (source.stream.state != AVB_SOURCE_STATE_DISABLED)
      return 0;
    if (len > AVB_MAX_CHANNELS_PER_TALKER_STREAM)
      return 0;
    memcpy(source.map, map, len<<2);
    i._set_source_info(source_num, source);
    return 1;
  }

  /** Get the destination address of an avb source.
   *  \param source_num   the local source number
   *  \param addr         the destination address as an array of 6 bytes
   *  \param len          the length of the address, should always be equal to 6
   */
  static inline int get_source_dest(client interface avb_interface i, unsigned source_num,
                      unsigned char addr[], int &len)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    len = 6;
    memcpy(addr, source.reservation.dest_mac_addr, 6);
    return 1;
  }

  /** Set the destination address of an avb source.
   *
   *  Sets the destination MAC address of a source.
   *  This setting will not take effect until the next time the source
   *  state moves from disabled to potential.
   *
   *  \param source_num   the local source number
   *  \param addr         the destination address as an array of 6 bytes
   *  \param len          the length of the address, should always be equal to 6
   *
   **/
  static inline int set_source_dest(client interface avb_interface i, unsigned source_num,
                      unsigned char addr[len], unsigned len)
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    if (source.stream.state != AVB_SOURCE_STATE_DISABLED)
      return 0;
    if (len != 6)
      return 0;
    memcpy(source.reservation.dest_mac_addr, addr, 6);
    i._set_source_info(source_num, source);
    return 1;
  }

  static inline int get_source_id(client interface avb_interface i, unsigned source_num,
                    unsigned int id[2])
  {
    if (source_num >= AVB_NUM_SOURCES)
      return 0;
    avb_source_info_t source;
    source = i._get_source_info(source_num);
    memcpy(id, source.reservation.stream_id, 8);
    return 1;
  }

  /** Get the stream id that an AVB sink listens to.
   * \param sink_num      the number of the sink
   * \param stream_id     int array containing the 64-bit of the stream
   */
  static inline int get_sink_id(client interface avb_interface i, unsigned sink_num,
                  unsigned int stream_id[2])
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    memcpy(stream_id, sink.reservation.stream_id, 8);
    return 1;
  }

  /** Set the stream id that an AVB sink listens to.
   *
   *  Sets the stream id that an AVB sink listens to.
   *
   *  This setting will not take effect until the next time the sink
   *  state moves from disabled to potential.
   *
   * \param sink_num      the number of the sink
   * \param stream_id     int array containing the 64-bit of the stream
   *
   */
  static inline int set_sink_id(client interface avb_interface i, unsigned sink_num,
                  unsigned int stream_id[2])
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    if (sink.stream.state != AVB_SINK_STATE_DISABLED)
      return 0;
    memcpy(sink.reservation.stream_id, stream_id, 8);
    i._set_sink_info(sink_num, sink);
    return 1;
  }


   /** Get the format of an AVB sink.
   *  \param sink_num the local sink number
   *  \param format     the format of the stream
   *  \param rate       the sample rate of the stream in Hz
   */
  static inline int get_sink_format(client interface avb_interface i, unsigned sink_num,
                      enum avb_stream_format_t &format, int &rate)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    format = sink.stream.format;
    rate = sink.stream.rate;
    return 1;
  }

  /** Set the format of an AVB sink.
   *
   *  The AVB sink format covers the encoding and sample rate of the sink.
   *  Currently the format is limited to a single encoding MBLA 24 bit signed
   *  integers.
   *
   *  This setting will not take effect until the next time the sink
   *  state moves from disabled to potential.
   *
   *  \param sink_num     the local sink number
   *  \param format       the format of the stream
   *  \param rate         the sample rate of the stream in Hz
   */
  static inline int set_sink_format(client interface avb_interface i, unsigned sink_num,
                      enum avb_stream_format_t format, int rate)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    if (sink.stream.state != AVB_SINK_STATE_DISABLED)
      return 0;
    sink.stream.format = format;
    sink.stream.rate = rate;
    i._set_sink_info(sink_num, sink);
    return 1;
  }

  /** Get the channel count of an AVB sink.
   *  \param sink_num     the local sink number
   *  \param channels     the number of channels
   */
  static inline int get_sink_channels(client interface avb_interface i, unsigned sink_num,
                        int &channels)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    channels = sink.stream.num_channels;
    return 1;
  }

  /** Set the channel count of an AVB sink.
   *
   *  Sets the number of channels in the stream.
   *
   *  This setting will not take effect until the next time the sink
   *  state moves from disabled to potential.
   *
   *  \param sink_num     the local sink number
   *  \param channels     the number of channels
   */
  static inline int set_sink_channels(client interface avb_interface i, unsigned sink_num,
                        int channels)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    if (sink.stream.state != AVB_SINK_STATE_DISABLED)
      return 0;
    sink.stream.num_channels = channels;
    i._set_sink_info(sink_num, sink);
    return 1;
  }

  /** Get the media clock of an AVB sink.
   *  \param sink_num   the local sink number
   *  \param sync         the media clock number
   */
  static inline int get_sink_sync(client interface avb_interface i, unsigned sink_num,
                    int &sync)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    sync = sink.stream.sync;
    return 1;
  }

  /** Set the media clock of an AVB sink.
   *
   *  Sets the media clock of the stream.
   *
   *  \param sink_num   the local sink number
   *  \param sync         the media clock number
   */
  static inline int set_sink_sync(client interface avb_interface i, unsigned sink_num,
                    int sync)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    if (sink.stream.state != AVB_SINK_STATE_DISABLED)
      return 0;
    sink.stream.sync = sync;
    i._set_sink_info(sink_num, sink);
    return 1;
  }

  /** Get the virtual lan id of an AVB sink.
   * \param sink_num the number of the sink
   * \param vlan     the vlan id of the sink
   */
  static inline int get_sink_vlan(client interface avb_interface i, unsigned sink_num,
                    int &vlan)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    vlan = sink.reservation.vlan_id;
    return 1;
  }

  /** Set the virtual lan id of an AVB sink.
   *
   *  Sets the vlan id of the incoming stream.
   *
   *  This setting will not take effect until the next time the sink
   *  state moves from disabled to potential.
   *
   * \param sink_num the number of the sink
   * \param vlan     the vlan id of the sink
   *
   */
  static inline int set_sink_vlan(client interface avb_interface i, unsigned sink_num,
                                  int vlan)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    if (sink.stream.state != AVB_SINK_STATE_DISABLED)
      return 0;
    sink.reservation.vlan_id = vlan;
    i._set_sink_info(sink_num, sink);
    return 1;
  }

  /** Get the incoming destination mac address of an avb sink.
   *  \param sink_num     The local sink number
   *  \param addr         The mac address as an array of 6 bytes.
   *  \param len          The length of the address, should always be equal to 6.
   */
  static inline int get_sink_addr(client interface avb_interface i, unsigned sink_num,
                    unsigned char addr[], int &len)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    len = 6;
    memcpy(addr, sink.reservation.dest_mac_addr, 6);
    return 1;
  }

  /** Set the incoming destination mac address of an avb sink.
   *
   *  Set the incoming destination mac address of a sink.
   *  This needs to be set if the address is a multicast address so
   *  the endpoint can register for that multicast group with the switch.
   *
   *  This setting will not take effect until the next time the sink
   *  state moves from disabled to potential.
   *
   *  \param sink_num     The local sink number
   *  \param addr         The mac address as an array of 6 bytes.
   *  \param len          The length of the address, should always be equal to 6.
   *
   **/
  static inline int set_sink_addr(client interface avb_interface i, unsigned sink_num,
                    unsigned char addr[len], unsigned len)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    if (sink.stream.state != AVB_SINK_STATE_DISABLED)
      return 0;
    if (len != 6)
      return 0;
    memcpy(sink.reservation.dest_mac_addr, addr, 6);
    i._set_sink_info(sink_num, sink);
    return 1;
  }

  /** Get the state of an AVB sink.
   * \param sink_num the number of the sink
   * \param state the state of the sink
   */
  static inline int get_sink_state(client interface avb_interface i, unsigned sink_num,
                     enum avb_sink_state_t &state)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    state = sink.stream.state;
    return 1;
  }

  /** Set the state of an AVB sink.
   *
   *  Sets the current state of an AVB sink. You cannot set the
   *  state to ``ENABLED``. Changing the state to ``POTENTIAL`` turns the stream
   *  on and it will automatically change to ``ENABLED`` when connected to
   *  a talker and receiving samples.
   *
   * \param sink_num the number of the sink
   * \param state the state of the sink
   *
   */
  static inline int set_sink_state(client interface avb_interface i, unsigned sink_num,
                     enum avb_sink_state_t state)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    sink.stream.state = state;
    i._set_sink_info(sink_num, sink);
    return 1;
  }

  /** Get the map of an AVB sink.
   * \param sink_num   the number of the sink
   * \param map        array containing the media output FIFOs that the
   *                   stream will be split into
   * \param len        the length of the map; should equal to the number
   *                   of channels in the stream
   */
  static inline int get_sink_map(client interface avb_interface i, unsigned sink_num,
                   int map[], int &len)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    len = sink.stream.num_channels;
    memcpy(map, sink.map, len<<2);
    return 1;
  }

  /** Set the map of an AVB sink.
   *
   *  Sets the map i.e. the mapping from the 1722 stream to output FIFOs.
   *
   *  This setting will not take effect until the next time the sink
   *  state moves from disabled to potential.
   *
   * \param sink_num   the number of the sink
   * \param map        array containing the media output FIFOs that the
   *                   stream will be split into
   * \param len        the length of the map; should equal to the number
   *                   of channels in the stream
   */
  static inline int set_sink_map(client interface avb_interface i, unsigned sink_num,
                   int map[len], unsigned len)
  {
    if (sink_num >= AVB_NUM_SINKS)
      return 0;
    avb_sink_info_t sink;
    sink = i._get_sink_info(sink_num);
    if (sink.stream.state != AVB_SINK_STATE_DISABLED)
      return 0;
    if (len > AVB_MAX_CHANNELS_PER_LISTENER_STREAM)
      return 0;
    memcpy(sink.map, map, len<<2);
    i._set_sink_info(sink_num, sink);
    return 1;
  }


  /** Get the rate of a media clock.
   *  \param clock_num the number of the media clock
   *  \param rate the rate of the clock in Hz
   */
  static inline int get_device_media_clock_rate(client interface avb_interface i,
                                  int clock_num, int &rate)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    rate = info.rate;
    return 1;
  }

  /** Set the rate of a media clock.
   *
   *  Sets the rate of the media clock.
   *
   *  \param clock_num the number of the media clock
   *  \param rate the rate of the clock in Hz
   *
   **/
  static inline int set_device_media_clock_rate(client interface avb_interface i,
                                  int clock_num, int rate)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    info.rate = rate;
    i._set_media_clock_info(clock_num, info);
    return 1;
  }

  /** Get the state of a media clock.
   *  \param clock_num the number of the media clock
   *  \param state the state of the clock
   */
  static inline int get_device_media_clock_state(client interface avb_interface i,
                                   int clock_num,
                                   enum device_media_clock_state_t &state)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    state = info.active ? DEVICE_MEDIA_CLOCK_STATE_ENABLED :
                          DEVICE_MEDIA_CLOCK_STATE_DISABLED;
    return 1;
  }

  /** Set the state of a media clock.
   *
   *  This function can be used to enabled/disable a media clock.
   *
   *  \param clock_num the number of the media clock
   *  \param state the state of the clock
   **/
  static inline int set_device_media_clock_state(client interface avb_interface i,
                                   int clock_num,
                                   enum device_media_clock_state_t state)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    info.active = (state == DEVICE_MEDIA_CLOCK_STATE_ENABLED);
    i._set_media_clock_info(clock_num, info);
    return 1;
  }

  /** Get the source of a media clock.
   *  \param clock_num the number of the media clock
   *  \param source the output FIFO number to base the clock on
   */
  static inline int get_device_media_clock_source(client interface avb_interface i,
                                    int clock_num, int &source)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    source = info.source;
    return 1;
  }

  /** Set the source of a media clock.
   *
   *  For clocks that are derived from an output FIFO. This function
   *  gets/sets which FIFO the clock should be derived from.
   *
   *  \param clock_num the number of the media clock
   *  \param source the output FIFO number to base the clock on
   *
   **/
  static inline int set_device_media_clock_source(client interface avb_interface i,
                                    int clock_num, int source)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    info.source = source;
    i._set_media_clock_info(clock_num, info);
    return 1;
  }


  /** Get the type of a media clock.
   *
   *  \param clock_num the number of the media clock
   *  \param clock_type the type of the clock
   */
  static inline int get_device_media_clock_type(client interface avb_interface i,
                                  int clock_num,
                                  enum device_media_clock_type_t &clock_type)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    clock_type = info.clock_type;
    return 1;
  }

  /** Set the type of a media clock.
   *
   *  \param clock_num the number of the media clock
   *  \param clock_type the type of the clock
   *
   **/
  static inline int set_device_media_clock_type(client interface avb_interface i,
                                  int clock_num,
                                  enum device_media_clock_type_t clock_type)
  {
    if (clock_num >= AVB_NUM_MEDIA_CLOCKS)
      return 0;
    media_clock_info_t info;
    info = i._get_media_clock_info(clock_num);
    info.clock_type = clock_type;
    char clksrc_str[] = "Setting clock source:";
    if (info.clock_type) debug_printf("%s LOCAL_CLOCK\n", clksrc_str);
    else debug_printf("%s INPUT_STREAM_DERIVED\n", clksrc_str);
    i._set_media_clock_info(clock_num, info);
    return 1;
  }

}

#endif

int avb_get_source_state(CLIENT_INTERFACE(avb_interface, avb), unsigned source_num, REFERENCE_PARAM(enum avb_source_state_t, state));
int avb_set_source_state(CLIENT_INTERFACE(avb_interface, avb), unsigned source_num, enum avb_source_state_t state);

#endif // _api_h_
