#ifndef __media_clock_server_h__
#define __media_clock_server_h__

#include "avb_conf.h"
#include "gptp.h"

#ifndef AVB_NUM_MEDIA_CLOCKS
#define AVB_NUM_MEDIA_CLOCKS 1
#endif

#ifndef MAX_CLK_CTL_CLIENTS
#define MAX_CLK_CTL_CLIENTS 8
#endif

#ifndef PLL_TO_WORD_MULTIPLIER
#define PLL_TO_WORD_MULTIPLIER 100
#endif

/** The type of a media clock.
 *  A media clock can be either be recovered
 *  from an
 *  incoming media FIFO (which in turn will derive its timing
 *  from the IEEE 1722 audio stream it came from) or use the
 *  local oscillator
 */
typedef enum media_clock_type_t {
  INPUT_STREAM_DERIVED,
  LOCAL_CLOCK
} media_clock_type_t;

typedef struct media_clock_info_t {
  int active;
  media_clock_type_t clock_type;  ///< The type of the clock
  int source;               ///< If the clock is derived from a fifo
                            ///  this is the id of the output
                            ///  fifo it should be derived from.
  int rate;                 ///<  The rate of the media clock in Hz
} media_clock_info_t;

#ifdef __XC__
interface media_clock_if {
  void register_clock(unsigned i, unsigned clock_num);
  media_clock_info_t get_clock_info(unsigned clock_num);
  void set_clock_info(unsigned clock_num, media_clock_info_t info);
  void set_buf_fifo(unsigned i, int fifo);
};
#endif

/** The media clock server.
 *
 *  \param media_clock_ctl  server interface of type media_clock_if connected to the avb_manager() task
 *                          and passed into avb_init()
 *  \param ptp_svr          chanend connected to the PTP server
 *  \param buf_ctl[]        array of links to listener components
 *                          requiring buffer management
 *  \param num_buf_ctl      size of the buf_ctl array
 *  \param p_fs             output port to drive PLL reference clock
 *  \param c_rx             chanend connected to the ethernet server (receive)
 *  \param c_tx             chanend connected to the ethernet server (transmit)
 *  \param c_ptp[]          an array of chanends to connect to clients of the ptp server
 *  \param num_ptp          The number of PTP clients attached
 *  \param server_type      The type of the PTP server (``PTP_GRANDMASTER_CAPABLE``
                            or ``PTP_SLAVE_ONLY``)
 */
#ifdef __XC__
void media_clock_server(server interface media_clock_if media_clock_ctl,
                        chanend ?ptp_svr,
                        chanend (&?buf_ctl)[num_buf_ctl], unsigned num_buf_ctl,
                        out buffered port:32 p_fs[]
#if COMBINE_MEDIA_CLOCK_AND_PTP
                        ,chanend c_rx,
                        chanend c_tx,
                        chanend c_ptp[num_ptp],
                        unsigned num_ptp,
                        enum ptp_server_type server_type
#endif
                        );
#endif

#endif
