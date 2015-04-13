#include "debug_print.h"
#include "media_input_fifo.h"
#include "hwlock.h"
#include "avb_1722_def.h"
#include <xscope.h>

static hwlock_t enable_lock;
unsigned int enable_request_state = 0;
unsigned int enable_indication_state = 0;

void media_input_fifo_enable_fifos(unsigned int enable)
{
	if (!enable_lock) return;
	hwlock_acquire(enable_lock);
	enable_request_state |= enable;
	hwlock_release(enable_lock);
}

void media_input_fifo_disable_fifos(unsigned int enable)
{
	if (!enable_lock) return;
	hwlock_acquire(enable_lock);
	enable_request_state &= ~enable;
	hwlock_release(enable_lock);
}

unsigned int media_input_fifo_enable_ind_state()
{
	return enable_indication_state;
}

unsigned int media_input_fifo_enable_req_state()
{
	return enable_request_state;
}

void media_input_fifo_update_enable_ind_state(unsigned int enable, unsigned int mask)
{
	if (!enable_lock) return;
	hwlock_acquire(enable_lock);
	enable_indication_state = (enable_indication_state & ~mask) | enable;
	hwlock_release(enable_lock);
}


void media_input_fifo_init(media_input_fifo_t media_input_fifo0, int stream_num)
{
  volatile ififo_t *media_input_fifo =  (ififo_t *) media_input_fifo0;

  media_input_fifo->sampleCountInPacket = -1;
  media_input_fifo->packetSize = -1;
  return;
}

void media_input_fifo_disable(media_input_fifo_t media_input_fifo0)
{
	media_input_fifo_init(media_input_fifo0, 0);
}

int media_input_fifo_enable(media_input_fifo_t media_input_fifo0,
                             int rate)
{
  volatile ififo_t *media_input_fifo =  (ififo_t *) media_input_fifo0;

  media_input_fifo->rdIndex = (int) &media_input_fifo->buf[0];
  media_input_fifo->wrIndex = (int) &media_input_fifo->buf[0];
  media_input_fifo->fifoEnd = (int) &media_input_fifo->buf[MEDIA_INPUT_FIFO_SAMPLE_FIFO_SIZE];
  return 0;
}

void media_input_fifo_push_sample(media_input_fifo_t media_input_fifo0,
                                  unsigned int sample,
                                  unsigned int ts)
{
  volatile ififo_t *media_input_fifo =  (ififo_t *) media_input_fifo0;
  int* wrIndex = (int *)media_input_fifo->wrIndex;

  int spaceLeft = ((int *) media_input_fifo->rdIndex) - wrIndex;

  spaceLeft &= (MEDIA_INPUT_FIFO_SAMPLE_FIFO_SIZE-1);

  if (spaceLeft && (spaceLeft < 2)) {
    return;
  }

  wrIndex[0] = sample;
  wrIndex[1] = ts;

  wrIndex += 2;

  if ((wrIndex + 2) > (int *) media_input_fifo->fifoEnd)
  	wrIndex = (int *) &media_input_fifo->buf[0];

  media_input_fifo->wrIndex = (int) wrIndex;
}

int media_input_fifo_fill_level(media_input_fifo_t media_input_fifo0)
{
  volatile ififo_t *media_input_fifo =  (ififo_t *) media_input_fifo0;
  int fill = ((int *) media_input_fifo->wrIndex) - (int *)media_input_fifo->rdIndex;

  fill &= (MEDIA_INPUT_FIFO_SAMPLE_FIFO_SIZE-1);

  fill = fill >> 1;

  return fill;
}

int media_input_fifo_empty(media_input_fifo_t media_input_fifo0)
{
 volatile ififo_t *media_input_fifo =  (ififo_t *) media_input_fifo0;
 return (media_input_fifo->rdIndex==0 ||
         media_input_fifo->rdIndex==media_input_fifo->startIndex);
}

void media_input_fifo_flush(media_input_fifo_t media_input_fifo0)
{
	volatile ififo_t *media_input_fifo =  (ififo_t *) media_input_fifo0;
	media_input_fifo->rdIndex = (int) &media_input_fifo->buf[0];
	media_input_fifo->wrIndex = (int) &media_input_fifo->buf[0];
}

void
init_media_input_fifos(media_input_fifo_t ififos[],
                       media_input_fifo_data_t ififo_data[],
                       int n)
{
	enable_lock = hwlock_alloc();
	for(int i=0;i<n;i++) {
    ififos[i] = (unsigned int) &ififo_data[i];
    media_input_fifo_flush(ififos[i]);
	}
}

extern inline void
media_input_fifo_move_sample_ptr(media_input_fifo_t media_infput_fifo0);

extern inline int *
media_input_fifo_get_sample_ptr(media_input_fifo_t media_infput_fifo0);
