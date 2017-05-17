// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved
#ifndef __AUDIO_OUTPUT_FIFO_h__
#define __AUDIO_OUTPUT_FIFO_h__

#include <xccompat.h>
#include <xc2compat.h>
#include "default_avb_conf.h"
#include "audio_buffering.h"

#ifndef AVB_MAX_AUDIO_SAMPLE_RATE
#define AVB_MAX_AUDIO_SAMPLE_RATE (48000)
#endif

#ifndef AUDIO_OUTPUT_FIFO_WORD_SIZE
#define AUDIO_OUTPUT_FIFO_WORD_SIZE (AVB_MAX_AUDIO_SAMPLE_RATE/450)
#endif

#define START_OF_FIFO(s) ((unsigned int*)&((s)->fifo[0]))
#define END_OF_FIFO(s)   ((unsigned int*)&((s)->fifo[AUDIO_OUTPUT_FIFO_WORD_SIZE]))

typedef enum ofifo_state_t {
  DISABLED, //!< Not active
  ZEROING,  //!< pushing zeros through to fill
  LOCKING,  //!< Clock recovery trying to lock to the sample stream
  LOCKED    //!< Clock recovery is locked and working
} ofifo_state_t;


struct audio_output_fifo_data_t {
  int zero_flag;							//!< When set, the FIFO will output zero samples instead of its contents
  unsigned int dptr;						//!< The read pointer
  unsigned int wrptr;						//!< The write pointer
  unsigned int marker;						//!< This indicates which sample is the one which the timestamps apply to
  int local_ts;								//!< When a marked sample has played out, this contains the ref clock when it happened.
  int ptp_ts;								//!< Contains the PTP timestamp of the marked sample.
  unsigned int sample_count;				//!< The count of samples that have passed through the buffer.
  unsigned int zero_marker;					//!<
  ofifo_state_t state;						//!< State of the FIFO
  int last_notification_time;				//!< Last time that the clock recovery thread was informed of the timestamp info
  int media_clock;							//!<
  int pending_init_notification;			//!<
  int volume;                               //!< The linear volume multipler in 2.30 signed fixed point format
  unsigned int fifo[AUDIO_OUTPUT_FIFO_WORD_SIZE];
};

typedef struct ofifo_t {
  int zero_flag;
  unsigned int *unsafe dptr;
  unsigned int *unsafe wrptr;
  unsigned int *unsafe marker;
  int local_ts;
  int ptp_ts;
  unsigned int sample_count;
  unsigned int *unsafe zero_marker;
  ofifo_state_t state;
  int last_notification_time;
  int media_clock;
  int pending_init_notification;
  int volume;
  unsigned int fifo[AUDIO_OUTPUT_FIFO_WORD_SIZE];
} ofifo_t;

/**
 * \brief This type provides the data structure used by a media output FIFO.
 */
typedef struct audio_output_fifo_data_t audio_output_fifo_data_t;

/**
 * \brief Intiialise a FIFO
 */
void audio_output_fifo_init(buffer_handle_t s, unsigned index);

/**
 * \brief Disable a FIFO
 *
 * This prevents samples from flowing through the FIFO
 */
void disable_audio_output_fifo(buffer_handle_t s, unsigned index);

/**
 * \brief Enable a FIFO
 *
 * This starts samples flowing through the FIFO
 */
void enable_audio_output_fifo(buffer_handle_t s,
                              unsigned index,
                              int media_clock);

/**
 *  \brief Perform maintanance on the FIFO, called periodically
 *
 *  This should be called periodically to allow the FIFO to
 *  perform tasks such as informing the clock recovery thread
 *  of some new timing information.
 *
 *  \param s handle to FIFO buffers
 *  \param index which buffer to operate on
 *  \param buf_ctl a channel end that links the FIFO to the media clock service
 *  \param notified_buf_ctl pointer to a flag which is set when the media clock has been notified of a timing event in the FIFO
 */
void
audio_output_fifo_maintain(buffer_handle_t s,
                           unsigned index,
                           chanend buf_ctl,
                           REFERENCE_PARAM(int, notified_buf_ctl));


#ifndef __XC__

/**
 *  \brief Push a set of samples into the FIFO
 *
 *  The samples are taken from the buffer pointed to by the sample_ptr,
 *  but are read from that buffer with a stride between each sample.
 *
 *  The 1722 listener thread uses this to put samples from the decoded
 *  packet into the audio FIFOs.
 *
 *  \param s0 handle to FIFO buffers
 *  \param index which buffer to operate on
 *  \param sample_ptr a pointer to a block of samples in the 1722 packet
 *  \param stride the number of words between successive samples for this FIFO
 *  \param n the number of samples to push into the buffer
 */
void
audio_output_fifo_strided_push(buffer_handle_t s0,
                               unsigned index,
                               unsigned int *sample_ptr,
                               int stride,
                               int n);
#endif


/**
 *  \brief Used by the audio output system to pull the next sample from the FIFO
 *
 *  If there are no samples in the buffer, a zero will be returned. The current
 *  ref clock time is passed into the function, and the FIFO will record this
 *  time if the sample which has been removed was the marked sample
 *
 *  \param s0 handle to FIFO buffers
 *  \param index which buffer to operate on
 *  \param timestamp the ref clock time of the sample playout
 */
 /*
unsigned int
audio_output_fifo_pull_sample(buffer_handle_t s0,
                              unsigned index,
                              unsigned int timestamp);
*/
__attribute__((always_inline))
unsafe static inline unsigned int
audio_output_fifo_pull_sample(buffer_handle_t s0,
                              unsigned index,
                              unsigned int timestamp)
{
  ofifo_t *unsafe s = (ofifo_t *unsafe)((struct output_finfo *unsafe)s0)->p_buffer[index];
  unsigned int sample;
  unsigned int *unsafe dptr = s->dptr;

  if (dptr == s->wrptr)
  {
    // Underflow
    // printstrln("Media output FIFO underflow");
    return 0;
  }

  sample = *dptr;
  if (dptr == s->marker && s->local_ts == 0) {
    if (timestamp==0) timestamp=1;
    s->local_ts = timestamp;
  }
  dptr++;
  if (dptr == END_OF_FIFO(s)) {
    dptr = START_OF_FIFO(s);
  }

  s->dptr = dptr;

  if (s->zero_flag)
    sample = 0;

  return sample;
}


/**
 *  \brief Set the PTP timestamp on a specific sample in the buffer
 *
 *  When the 1722 thread unpacks a PDU, one of the samples in that
 *  PDU will have a PTP timestamp associated with it.  The 1722
 *  listener thread calls this to cause the FIFO to update control
 *  structures to record which sample is marked and the timestamp
 *  of that sample.
 *
 *  If the FIFO already has a marked timestamped sample within the
 *  buffer then it does not record the new timestamp.
 *
 *  \param s0 handle to FIFO buffers
 *  \param index which buffer to operate on
 *  \param timestamp the 32 bit PTP timestamp
 *  \param sample_number the sample, counted from the end of the FIFO, which the timestamp applies to
 *
 */
void audio_output_fifo_set_ptp_timestamp(buffer_handle_t s0,
                                         unsigned index,
                                         unsigned int timestamp,
                                         unsigned sample_number);


/**
 *  \brief Handle notification events on the buffer control channel
 *
 *  The 1722 listener thread notifies the clock server about timing
 *  events in the audio FIFOs using a channel. This function provides
 *  the processing of the messages which can be sent by the clock
 *  recovery thread over that channel.
 *
 *  \param buf_ctl  the communication channel with the clock recovery service
 *  \param s0 handle to FIFO buffers
 *  \param index which buffer to operate on
 *  \param stream_num  the number of the stream which is being handled
 *  \param buf_ctl_notified pointer to the flag which indicates whether the clock recovery thread has been notified of a timing event
 */
void
audio_output_fifo_handle_buf_ctl(chanend buf_ctl,
                                 buffer_handle_t s0,
                                 unsigned index,
                                 REFERENCE_PARAM(int, buf_ctl_notified),
                                 timer tmr);

/**
 *  \brief Set the volume control multiplier for the media FIFO
 *
 *  \param s0 handle to FIFO buffers
 *  \param index which buffer to operate on
 *  \param volume the 2.30 signed fixed point linear volume multiplier
 */
void
audio_output_fifo_set_volume(buffer_handle_t s0,
                             unsigned index,
                             unsigned int volume);

#endif


