/* This module implements the 802.1as gptp timing protocol.
   It is a restricted version of the protocol that can only handle
   endpoints with one port. As such it is optimized (particularly for
   memory usage) and combined the code for the port state machines and the site
   state machines into one. */
#include <string.h>
#include <limits.h>
#include <xclib.h>
#ifdef __avb_conf_h_exists__
#include "avb_conf.h"
#endif
#include "gptp.h"
#include "gptp_config.h"
#include "gptp_pdu.h"
#include "ethernet_tx_client.h"
#include "ethernet_rx_client.h"
#include "misc_timer.h"
#include "print.h"
#include "debug_print.h"
#include "avb_util.h"

//#define GPTP_DEBUG 1

#define timeafter(A, B) ((int)((B) - (A)) < 0)

#define NANOSECONDS_PER_SECOND (1000000000)

/* The adjust between local clock ticks and ptp clock ticks.
   This is the ratio between our clock speed and the grandmaster less 1.
   For example, if we are running 1% faster than the master clock then
   this value will be 0.01 */
#define PTP_ADJUST_WEIGHT 32
static int g_ptp_adjust_valid = 0;
signed g_ptp_adjust = 0;
signed g_inv_ptp_adjust = 0;

/* The average path delay (over the last PDELAY_AVG_WINDOW pdelay_reqs)
   between the foreign master port and our slave port in nanoseconds (ptp time)
*/
#define PTP_PATH_DELAY_WEIGHT 32

ptp_port_info_t ptp_port_info[PTP_NUM_PORTS];
static unsigned short steps_removed_from_gm;

/* These variables make up the state of the local clock/port */
unsigned ptp_reference_local_ts;
ptp_timestamp ptp_reference_ptp_ts;
static long long ptp_gmoffset = 0;
static int expect_gm_discontinuity = 1;
static int ptp_candidate_gmoffset_valid = 0;
static n64_t my_port_id;
static n80_t master_port_id;
static u8_t ptp_priority1;
static u8_t ptp_priority2 = PTP_DEFAULT_PRIORITY2;

/* Timing variables */
static unsigned last_received_announce_time_valid[PTP_NUM_PORTS];
static unsigned last_received_announce_time[PTP_NUM_PORTS];
static unsigned last_received_sync_time[PTP_NUM_PORTS];
static unsigned last_receive_sync_upstream_interval[PTP_NUM_PORTS];
static unsigned last_announce_time[PTP_NUM_PORTS];
static unsigned last_sync_time[PTP_NUM_PORTS];
static unsigned last_pdelay_req_time[PTP_NUM_PORTS];

static ptp_timestamp prev_adjust_master_ts;
static unsigned prev_adjust_local_ts;
static int prev_adjust_valid = 0;

static unsigned received_sync = 0;
static u16_t received_sync_id;
static unsigned received_sync_ts;

static int sync_lock = 0;
static int sync_count = 0;

static AnnounceMessage best_announce_msg;

static unsigned long long pdelay_epoch_timer;
static unsigned prev_pdelay_local_ts;

static int tile_timer_offset;
static int periodic_counter;

#define DEBUG_PRINT 0
#define DEBUG_PRINT_ANNOUNCE 0
#define DEBUG_PRINT_AS_CAPABLE 0

ptp_port_role_t ptp_current_state()
{
  //TODO: FIME
  return 0;
  // return ptp_state;
}

unsigned local_timestamp_to_ptp_mod32(unsigned local_ts,
                                      ptp_time_info_mod64 &info)
{
  long long local_diff = (signed) local_ts - (signed) info.local_ts;

  local_diff *= 10;
  local_diff = local_diff + ((local_diff * info.ptp_adjust) >> PTP_ADJUST_PREC);

  return (info.ptp_ts_lo + (int) local_diff);
}

void local_timestamp_to_ptp_mod64(unsigned local_ts,
                                  ptp_time_info_mod64 *info,
                                  unsigned *hi,
                                  unsigned *lo)
{
  long long local_diff = (signed) local_ts - (signed) info->local_ts;
  unsigned long long ptp_mod64 = ((unsigned long long) info->ptp_ts_hi << 32) + info->ptp_ts_lo;

  local_diff *= 10;
  local_diff = local_diff + ((local_diff * info->ptp_adjust) >> PTP_ADJUST_PREC);

  ptp_mod64 += local_diff;

  *hi = ptp_mod64 >> 32;
  *lo = (unsigned) ptp_mod64;
}



void ptp_get_reference_ptp_ts_mod_64(unsigned &hi, unsigned &lo)
{
  unsigned long long t;
  t = ptp_reference_ptp_ts.seconds[0] +  ((unsigned long long) ptp_reference_ptp_ts.seconds[1] << 32);
  t = t * NANOSECONDS_PER_SECOND;
  t += ptp_reference_ptp_ts.nanoseconds;
  hi = (unsigned) (t >> 32);
  lo = (unsigned) t;
}

static long long local_time_to_ptp_time(unsigned t, int l_ptp_adjust)
{
  long long ret = ((long long) t)*10;

  if (g_ptp_adjust_valid) {
    ret = ret + ((ret * l_ptp_adjust) >> PTP_ADJUST_PREC);
  }
  return ret;
}


static void ptp_timestamp_offset64(ptp_timestamp &alias dst,
                                   ptp_timestamp &alias ts,
                                   long long offset)
{
  unsigned long long sec = ts.seconds[0] |
                           ((unsigned long long) ts.seconds[1] << 32);

  unsigned long long nanosec = ts.nanoseconds;

  nanosec = nanosec + offset;

  sec = sec + nanosec / NANOSECONDS_PER_SECOND;

  nanosec = nanosec % NANOSECONDS_PER_SECOND;

  dst.seconds[1] = (unsigned) (sec >> 32);

  dst.seconds[0] = (unsigned) sec;

  dst.nanoseconds = nanosec;
}


void ptp_timestamp_offset(ptp_timestamp &ts, int offset)
{
  ptp_timestamp_offset64(ts, ts, offset);
}

static long long ptp_timestamp_diff(ptp_timestamp &a,
                                    ptp_timestamp &b)
{
  unsigned long long sec_a = a.seconds[0] |
                           ((unsigned long long) a.seconds[1] << 32);
  unsigned long long sec_b = b.seconds[0] |
                           ((unsigned long long) b.seconds[1] << 32);
  unsigned long long nanosec_a = a.nanoseconds;
  unsigned long long nanosec_b = b.nanoseconds;

  long long sec_diff = sec_a - sec_b;
  long long nanosec_diff = nanosec_a - nanosec_b;

  nanosec_diff += sec_diff * NANOSECONDS_PER_SECOND;

  return nanosec_diff;
}

unsigned ptp_timestamp_to_local(ptp_timestamp &ts,
                                ptp_time_info &info)
{
    long long ptp_diff;
    long long local_diff;
    ptp_diff = ptp_timestamp_diff(ts, info.ptp_ts);

    local_diff = ptp_diff + ((ptp_diff * info.inv_ptp_adjust) >> PTP_ADJUST_PREC);
    local_diff = local_diff / 10;
    return (info.local_ts + local_diff);
}

unsigned ptp_mod32_timestamp_to_local(unsigned ts, ptp_time_info_mod64& info)
{
    long long ptp_diff;
    long long local_diff;
    ptp_diff = (signed) ts - (signed)info.ptp_ts_lo;

    local_diff = ptp_diff + ((ptp_diff * info.inv_ptp_adjust) >> PTP_ADJUST_PREC);
    local_diff = local_diff / 10;
    return (info.local_ts + local_diff);
}

static void _local_timestamp_to_ptp(ptp_timestamp &ptp_ts,
                                    unsigned local_ts,
                                    unsigned reference_local_ts,
                                    ptp_timestamp &reference_ptp_ts,
                                    unsigned ptp_adjust)
{
  unsigned local_diff = (signed) local_ts - (signed) reference_local_ts;

  unsigned long long diff = local_time_to_ptp_time(local_diff, ptp_adjust);

  ptp_timestamp_offset64(ptp_ts, reference_ptp_ts, diff);
}

void local_timestamp_to_ptp(ptp_timestamp &ptp_ts,
                            unsigned local_ts,
                            ptp_time_info &info)
{
  _local_timestamp_to_ptp(ptp_ts,
                          local_ts,
                          info.local_ts,
                          info.ptp_ts,
                          info.ptp_adjust);
}

#define local_to_ptp_ts(ptp_ts, local_ts) _local_timestamp_to_ptp(ptp_ts, local_ts, ptp_reference_local_ts, ptp_reference_ptp_ts, g_ptp_adjust)

static void create_my_announce_msg(AnnounceMessage *pAnnounceMesg);

static void set_new_role(enum ptp_port_role_t new_role,
                         int port_num) {

  unsigned t = get_local_time();

  if (new_role == PTP_SLAVE) {

    debug_printf("PTP Port %d Role: Slave\n", port_num);

    // Reset synotization variables
    ptp_port_info[port_num].delay_info.valid = 0;
    g_ptp_adjust = 0;
    g_inv_ptp_adjust = 0;
    prev_adjust_valid = 0;
    g_ptp_adjust_valid = 0;
    // Since there has been a role change there may be a gm discontinuity
    // to detect
    expect_gm_discontinuity = 1;
    ptp_candidate_gmoffset_valid = 0;
    last_pdelay_req_time[port_num] = t;
    sync_lock = 0;
    sync_count = 0;
  }

  if (new_role == PTP_MASTER) {

    debug_printf("PTP Port %d Role: Master\n", port_num);

    // Now we are the master so no rate matching is needed
    g_ptp_adjust = 0;
    g_inv_ptp_adjust = 0;

    ptp_reference_local_ts =
      ptp_reference_local_ts;

    ptp_gmoffset = 0;
    last_sync_time[port_num] = last_announce_time[port_num] = t;
  }


  ptp_port_info[port_num].role_state = new_role;

  if ((new_role == PTP_MASTER || new_role == PTP_UNCERTAIN)
#if (PTP_NUM_PORTS == 2)
    && (ptp_port_info[!port_num].role_state == PTP_MASTER)
#endif
    ) {
    create_my_announce_msg(&best_announce_msg);
  }
}


/* Assume very conservatively that the worst case is that
   the sync messages a .5sec apart. That is 5*10^9ns which can
   be stored in 29 bits. So we have 35 fractional bits to calculate
   with */
#define ADJUST_CALC_PREC 35

#define DEBUG_ADJUST

static int update_adjust(ptp_timestamp &master_ts,
                          unsigned local_ts)
{

  if (prev_adjust_valid) {
    signed long long adjust, inv_adjust, master_diff, local_diff;


    /* Calculated the difference between two sync message on
       the master port and the local port */
    master_diff = ptp_timestamp_diff(master_ts, prev_adjust_master_ts);
    local_diff = (signed) local_ts - (signed) prev_adjust_local_ts;

    /* The local timestamps are based on 100Mhz. So
       convert to nanoseconds */
    local_diff *= 10;

    /* Work at the new adjust value in 64 bits */
    adjust = master_diff - local_diff;
    inv_adjust = local_diff - master_diff;

    // Detect and ignore outliers
#if PTP_THROW_AWAY_SYNC_OUTLIERS
    if (master_diff > 150000000 || master_diff < 100000000) {
      prev_adjust_valid = 0;
      debug_printf("PTP threw away Sync outlier (master_diff %d)\n", master_diff);
      return 1;
    }
#endif

    adjust <<= ADJUST_CALC_PREC;
    inv_adjust <<= ADJUST_CALC_PREC;

    if (master_diff == 0 || local_diff == 0) {
      prev_adjust_valid = 0;
      return 1;
    }

    adjust = adjust / master_diff;
    inv_adjust = inv_adjust / local_diff;

    /* Reduce it down to PTP_ADJUST_PREC */
    adjust >>= (ADJUST_CALC_PREC - PTP_ADJUST_PREC);
    inv_adjust >>= (ADJUST_CALC_PREC - PTP_ADJUST_PREC);

    /* Re-average the adjust with a given weighting.
       This method loses a few bits of precision */
    if (g_ptp_adjust_valid) {

      long long diff = adjust - (long long) g_ptp_adjust;

      if (diff < 0)
        diff = -diff;

      if (!sync_lock) {
        if (diff < PTP_SYNC_LOCK_ACCEPTABLE_VARIATION) {
          sync_count++;
          if (sync_count > PTP_SYNC_LOCK_STABILITY_COUNT) {
            debug_printf("PTP sync locked\n");
            sync_lock = 1;
            sync_count = 0;
          }
        }
        else
          sync_count = 0;
      }
      else {
        if (diff > PTP_SYNC_LOCK_ACCEPTABLE_VARIATION) {
          sync_count++;
          if (sync_count > PTP_SYNC_LOCK_STABILITY_COUNT) {
            debug_printf("PTP sync lock lost\n");
            sync_lock = 0;
            sync_count = 0;
            prev_adjust_valid = 0;
            return 1;
          }
        }
        else
          sync_count = 0;
      }

      adjust = (((long long)g_ptp_adjust) * (PTP_ADJUST_WEIGHT - 1) + adjust) / PTP_ADJUST_WEIGHT;

      g_ptp_adjust = (int) adjust;

      inv_adjust = (((long long)g_inv_ptp_adjust) * (PTP_ADJUST_WEIGHT - 1) + inv_adjust) / PTP_ADJUST_WEIGHT;

      g_inv_ptp_adjust = (int) inv_adjust;
    }
    else {
      g_ptp_adjust = (int) adjust;
      g_inv_ptp_adjust = (int) inv_adjust;
      g_ptp_adjust_valid = 1;
    }
  }

  prev_adjust_local_ts = local_ts;
  prev_adjust_master_ts = master_ts;
  prev_adjust_valid = 1;

  return 0;
}

static void update_reference_timestamps(ptp_timestamp &master_egress_ts,
                                        unsigned local_ingress_ts,
                                        ptp_port_info_t &port_info)
{
  ptp_timestamp master_ingress_ts;

  ptp_timestamp_offset64(master_ingress_ts, master_egress_ts, port_info.delay_info.pdelay);

  /* Update the reference timestamps */
  ptp_reference_local_ts = local_ingress_ts;
  ptp_reference_ptp_ts = master_ingress_ts;
}

#define UPDATE_REFERENCE_TIMESTAMP_PERIOD (500000000) // 5 sec

static void periodic_update_reference_timestamps(unsigned int local_ts)
{

  int local_diff = local_ts - ptp_reference_local_ts;



  if (local_diff > UPDATE_REFERENCE_TIMESTAMP_PERIOD) {
    long long ptp_diff = local_time_to_ptp_time(local_diff, g_ptp_adjust);

    ptp_reference_local_ts = local_ts;
    ptp_timestamp_offset64(ptp_reference_ptp_ts,
                           ptp_reference_ptp_ts,
                           ptp_diff);
  }
}


static void update_path_delay(ptp_timestamp &master_ingress_ts,
                              ptp_timestamp &master_egress_ts,
                              unsigned local_egress_ts,
                              unsigned local_ingress_ts,
                              ptp_port_info_t &port_info)
{
  long long master_diff;
  long long local_diff;
  long long delay;
  long long round_trip;

  /* The sequence of events is:

     local egress   (ptp req sent from our local port)
     master ingress (ptp req recv on master port)
     master egress  (ptp resp sent from master port)
     local ingress  (ptp resp recv on our local port)

     So transit time (assuming a symetrical link) is:

     ((local_ingress_ts - local_egress_ts) - (master_egress_ts - master_ingress_ts) ) / 2

  */

  master_diff = ptp_timestamp_diff(master_egress_ts,  master_ingress_ts);

  local_diff = (signed) local_ingress_ts - (signed) local_egress_ts;

  local_diff = local_time_to_ptp_time(local_diff, g_ptp_adjust);

  round_trip = (local_diff - master_diff);

  round_trip -= LOCAL_EGRESS_DELAY;

  delay = round_trip / 2;

  if (delay < 0)
    delay = 0;

  if (port_info.delay_info.valid) {

    /* Re-average the adjust with a given weighting.
       This method loses a few bits of precision */
    port_info.delay_info.pdelay = ((port_info.delay_info.pdelay * (PTP_PATH_DELAY_WEIGHT - 1)) + (int) delay) / PTP_PATH_DELAY_WEIGHT;
  }
  else {
    port_info.delay_info.pdelay = delay;
    port_info.delay_info.valid = 1;
  }
}

/* Returns:
      -1 - if clock is worse than me
      1  - if clock is better than me
      0  - if clocks are equal
*/
static int compare_clock_identity_to_me(n64_t *clockIdentity)
{
  for (int i=0;i<8;i++) {
    if (clockIdentity->data[i] > my_port_id.data[i]) {
      return -1;
    }
    else if (clockIdentity->data[i] < my_port_id.data[i]) {
      return 1;
    }
  }

  // Thje two clock identities are the same
  return 0;
}

static int compare_clock_identity(n64_t *c1,
                                  n64_t *c2)
{
  for (int i=0;i<8;i++) {
    if (c1->data[i] > c2->data[i]) {
      return -1;
    }
    else if (c1->data[i] < c2->data[i]) {
      return 1;
    }
  }
  // Thje two clock identities are the same
  return 0;
}

static void bmca_update_roles(char *msg, unsigned t, int port_num)
{
  ComMessageHdr *pComMesgHdr = (ComMessageHdr *) msg;
  AnnounceMessage *pAnnounceMesg = (AnnounceMessage *) ((char *) pComMesgHdr+sizeof(ComMessageHdr));
  int clock_identity_comp;
  int new_best = 0;

  clock_identity_comp =
    compare_clock_identity_to_me(&pAnnounceMesg->grandmasterIdentity);

  if (clock_identity_comp == 0) {
    /* If the message is about me then we win since our stepsRemoved is 0 */
  }
  else {
   /* Message is from a different clock. Let's work out if it is better or
      worse according to the BMCA */
    if (pAnnounceMesg->grandmasterPriority1 > best_announce_msg.grandmasterPriority1) {
      new_best = -1;
    }
    else if (pAnnounceMesg->grandmasterPriority1 < best_announce_msg.grandmasterPriority1) {
      new_best = 1;
    }
    else if (pAnnounceMesg->clockClass > best_announce_msg.clockClass)  {
      new_best = -1;
    }
    else if (pAnnounceMesg->clockClass < best_announce_msg.clockClass) {
     new_best = 1;
    }
    else if (pAnnounceMesg->clockAccuracy > best_announce_msg.clockAccuracy) {
      new_best = -1;
    }
    else if (pAnnounceMesg->clockAccuracy < best_announce_msg.clockAccuracy) {
     new_best = 1;
    }
    else if (ntoh16(pAnnounceMesg->clockOffsetScaledLogVariance) > ntoh16(best_announce_msg.clockOffsetScaledLogVariance)) {
      new_best = -1;
    }
    else if (ntoh16(pAnnounceMesg->clockOffsetScaledLogVariance) < ntoh16(best_announce_msg.clockOffsetScaledLogVariance)) {
     new_best = 1;
    }
    else if (pAnnounceMesg->grandmasterPriority2 > best_announce_msg.grandmasterPriority2) {
      new_best = -1;
    }
    else if (pAnnounceMesg->grandmasterPriority2 < best_announce_msg.grandmasterPriority2) {
     new_best = 1;
    }
    else
      {
        clock_identity_comp =
          compare_clock_identity(&pAnnounceMesg->grandmasterIdentity,
                                 &best_announce_msg.grandmasterIdentity);

        if (clock_identity_comp <= 0) {
          //
        }
        else  {
          new_best = 1;
        }
      }
  }


  if (new_best > 0) {
    memcpy(&best_announce_msg, pAnnounceMesg, sizeof(AnnounceMessage));
    master_port_id = pComMesgHdr->sourcePortIdentity;

    {
#if DEBUG_PRINT_ANNOUNCE
      debug_printf("NEW BEST: %d\n", port_num);
#endif
      set_new_role(PTP_SLAVE, port_num);
      if (PTP_NUM_PORTS == 2) {
        set_new_role(PTP_MASTER, !port_num);
      }
      last_received_announce_time_valid[port_num] = 0;
      master_port_id = pComMesgHdr->sourcePortIdentity;
    }
  }
  else if (new_best < 0 && ptp_port_info[port_num].role_state == PTP_SLAVE) {
    set_new_role(PTP_MASTER, port_num);
    last_received_announce_time_valid[port_num] = 0;
  }
}


static void timestamp_to_network(n80_t &msg,
                                 ptp_timestamp &ts)
{
  char *sec0_p = (char *) &ts.seconds[0];
  char *sec1_p = (char *) &ts.seconds[1];
  char *nsec_p = (char *) &ts.nanoseconds;

  // Convert seconds to big-endian
  msg.data[0] = sec1_p[3];
  msg.data[1] = sec1_p[2];

  for (int i=2; i < 6; i++)
    msg.data[i] = sec0_p[5-i];

  // Now convert nanoseconds
  for (int i=6; i < 10; i++)
    msg.data[i] = nsec_p[9-i];
}

/*
extern void timestamp_to_network(n80_t &msg,
                                 ptp_timestamp &ts);
*/

static void network_to_ptp_timestamp(ptp_timestamp &ts,
                                     n80_t &msg)
{
  char *sec0_p = (char *) &ts.seconds[0];
  char *sec1_p = (char *) &ts.seconds[1];
  char *nsec_p = (char *) &ts.nanoseconds;

  sec1_p[3] = msg.data[0];
  sec1_p[2] = msg.data[1];
  sec1_p[1] = 0;
  sec1_p[0] = 0;

  for (int i=2; i < 6; i++)
    sec0_p[5-i] = msg.data[i];

  for (int i=6; i < 10; i++)
    nsec_p[9-i] = msg.data[i];
}

static int port_identity_equal(n64_t &a, n64_t &b)
{
  for (int i=0;i<8;i++)
    if (a.data[i] != b.data[i])
      return 0;
  return 1;
}

static int source_port_identity_equal(n80_t &a, n80_t &b)
{
  for (int i=0;i<10;i++)
    if (a.data[i] != b.data[i])
      return 0;
  return 1;
}

static int clock_id_equal(n64_t *a, n64_t *b)
{
  for (int i=0;i<8;i++)
    if (a->data[i] != b->data[i])
      return 0;
  return 1;
}


static void ptp_tx(chanend c_tx,
                   unsigned int *buf,
                   int len,
                   int port_num)
{
  len = len < 64 ? 64 : len;
  mac_tx(c_tx, buf, len, port_num);
  return;
}

static void ptp_tx_timed(chanend c_tx,
                         unsigned int buf[],
                         int len,
                         unsigned &ts,
                         int port_num)
{
  len = len < 64 ? 64 : len;
  mac_tx_timed(c_tx, buf, len, ts, port_num);
  ts = ts - tile_timer_offset;
}

static unsigned char src_mac_addr[6];
static unsigned char dest_mac_addr[6] = PTP_DEFAULT_DEST_ADDR;


static void set_ptp_ethernet_hdr(unsigned char *buf)
{
  ethernet_hdr_t *hdr = (ethernet_hdr_t *) buf;

  for (int i=0;i<6;i++)  {
    hdr->src_addr[i] = src_mac_addr[i];
    hdr->dest_addr[i] = dest_mac_addr[i];
  }

  hdr->ethertype.data[0] = (PTP_ETHERTYPE >> 8);
  hdr->ethertype.data[1] = (PTP_ETHERTYPE & 0xff);
}

// Estimate of announce message processing time delay.
#define MESSAGE_PROCESS_TIME    (3563)

static u16_t announce_seq_id[PTP_NUM_PORTS];

static void create_my_announce_msg(AnnounceMessage *pAnnounceMesg)
{
   // setup the Announce message
   pAnnounceMesg->currentUtcOffset = hton16(PTP_CURRENT_UTC_OFFSET);
   pAnnounceMesg->grandmasterPriority1 = ptp_priority1;


   // grandMaster clock quality.
   pAnnounceMesg->clockClass = PTP_CLOCK_CLASS;
   pAnnounceMesg->clockAccuracy = PTP_CLOCK_ACCURACY;

   pAnnounceMesg->clockOffsetScaledLogVariance =
     hton16(PTP_OFFSET_SCALED_LOG_VARIANCE);

   // grandMaster priority
   pAnnounceMesg->grandmasterPriority2 = ptp_priority2;

   for (int i=0;i<8;i++)
     pAnnounceMesg->grandmasterIdentity.data[i] = my_port_id.data[i];

   pAnnounceMesg->stepsRemoved = hton16(0);

   pAnnounceMesg->timeSource = PTP_TIMESOURCE;

   pAnnounceMesg->tlvType = hton16(PTP_ANNOUNCE_TLV_TYPE);
   pAnnounceMesg->tlvLength = hton16(8);

   for (int i=0;i<8;i++)
     pAnnounceMesg->pathSequence[0].data[i] = my_port_id.data[i];
}

static void send_ptp_announce_msg(chanend c_tx, int port_num)
{
#define ANNOUNCE_PACKET_SIZE (sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr) + sizeof(AnnounceMessage))
  unsigned int buf0[(ANNOUNCE_PACKET_SIZE+3)/4];
  unsigned char *buf = (unsigned char *) &buf0[0];
  ComMessageHdr *pComMesgHdr = (ComMessageHdr *) &buf[sizeof(ethernet_hdr_t)];
  AnnounceMessage *pAnnounceMesg = (AnnounceMessage *) &buf[sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr)];

  set_ptp_ethernet_hdr(buf);

  int message_length = sizeof(ComMessageHdr) + sizeof(AnnounceMessage);

  // setup the common message header.
  memset(pComMesgHdr, 0, message_length);

  pComMesgHdr->transportSpecific_messageType =
    PTP_TRANSPORT_SPECIFIC_HDR | PTP_ANNOUNCE_MESG;

  pComMesgHdr->versionPTP = PTP_VERSION_NUMBER;

  pComMesgHdr->flagField[1] =
   ((PTP_LEAP61 & 0x1)) |
   ((PTP_LEAP59 & 0x1) << 1) |
   ((PTP_CURRENT_UTC_OFFSET_VALID & 0x1) << 2) |
   ((PTP_TIMESCALE & 0x1) << 3) |
   ((PTP_TIME_TRACEABLE & 0x1) << 4) |
   ((PTP_FREQUENCY_TRACEABLE & 0x1) << 5);

  // portId assignment
  for (int i=0; i < 8; i++) {
    pComMesgHdr->sourcePortIdentity.data[i] = my_port_id.data[i];
  }
  pComMesgHdr->sourcePortIdentity.data[9] = port_num + 1;

  // sequence id.
  announce_seq_id[port_num] += 1;
  pComMesgHdr->sequenceId = hton16(announce_seq_id[port_num]);

  pComMesgHdr->controlField = PTP_CTL_FIELD_OTHERS;

  pComMesgHdr->logMessageInterval = PTP_LOG_ANNOUNCE_INTERVAL;

  // create_my_announce_msg(pAnnounceMesg);
    // setup the Announce message
  pAnnounceMesg->currentUtcOffset = hton16(PTP_CURRENT_UTC_OFFSET);
  pAnnounceMesg->grandmasterPriority1 = best_announce_msg.grandmasterPriority1;


  // grandMaster clock quality.
  pAnnounceMesg->clockClass = best_announce_msg.clockClass;
  pAnnounceMesg->clockAccuracy = best_announce_msg.clockAccuracy;

  pAnnounceMesg->clockOffsetScaledLogVariance = best_announce_msg.clockOffsetScaledLogVariance;

  // grandMaster priority
  pAnnounceMesg->grandmasterPriority2 = best_announce_msg.grandmasterPriority2;

  for (int i=0;i<8;i++)
   pAnnounceMesg->grandmasterIdentity.data[i] = best_announce_msg.grandmasterIdentity.data[i];

  steps_removed_from_gm = ntoh16(best_announce_msg.stepsRemoved);

#if (PTP_NUM_PORTS == 2)
  if ((ptp_port_info[0].role_state == PTP_MASTER) ^ (ptp_port_info[1].role_state == PTP_MASTER)) {
    // Only increment steps removed if we are not the grandmaster
    steps_removed_from_gm++;
  }
#endif

  pAnnounceMesg->stepsRemoved = hton16(steps_removed_from_gm);

  pAnnounceMesg->timeSource = PTP_TIMESOURCE;

  pAnnounceMesg->tlvType = hton16(PTP_ANNOUNCE_TLV_TYPE);
  pAnnounceMesg->tlvLength = hton16((steps_removed_from_gm+1)*8);

  memcpy(pAnnounceMesg->pathSequence, best_announce_msg.pathSequence, steps_removed_from_gm*8);

  for (int i=0;i<8;i++)
  {
    pAnnounceMesg->pathSequence[steps_removed_from_gm].data[i] = my_port_id.data[i];
  }

  message_length -= (PTP_MAXIMUM_PATH_TRACE_TLV-(steps_removed_from_gm+1))*8;

  pComMesgHdr->messageLength = hton16(message_length);

  // send the message.
  ptp_tx(c_tx, buf0, sizeof(ethernet_hdr_t)+message_length, port_num);

#if DEBUG_PRINT_ANNOUNCE
  debug_printf("TX Announce, Port %d\n", port_num);
#endif

   return;
}


static u16_t sync_seq_id = 0;

static void send_ptp_sync_msg(chanend c_tx, int port_num)
{
 #define SYNC_PACKET_SIZE (sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr) + sizeof(SyncMessage))
 #define FOLLOWUP_PACKET_SIZE (sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr) + sizeof(FollowUpMessage))
  unsigned int buf0[(FOLLOWUP_PACKET_SIZE+3)/4];
  unsigned char *buf = (unsigned char *) &buf0[0];
  ComMessageHdr *pComMesgHdr = (ComMessageHdr *) &buf[sizeof(ethernet_hdr_t)];;
  FollowUpMessage *pFollowUpMesg = (FollowUpMessage *) &buf[sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr)];
  unsigned local_egress_ts = 0;
  ptp_timestamp ptp_egress_ts;

  set_ptp_ethernet_hdr(buf);

  memset(pComMesgHdr, 0, sizeof(ComMessageHdr) + sizeof(FollowUpMessage));

  // 1. Send Sync message.

  pComMesgHdr->transportSpecific_messageType =
    PTP_TRANSPORT_SPECIFIC_HDR | PTP_SYNC_MESG;

  pComMesgHdr->versionPTP = PTP_VERSION_NUMBER;

  pComMesgHdr->messageLength = hton16(sizeof(ComMessageHdr) +
                                      sizeof(SyncMessage));

  pComMesgHdr->flagField[0] = 0x2;   // set two steps flag
  pComMesgHdr->flagField[1] = (PTP_TIMESCALE & 0x1) << 3;

  for(int i=0;i<8;i++) pComMesgHdr->correctionField.data[i] = 0;

  for (int i=0; i < 8; i++) {
    pComMesgHdr->sourcePortIdentity.data[i] = my_port_id.data[i];
  }
  pComMesgHdr->sourcePortIdentity.data[9] = port_num + 1;

  sync_seq_id += 1;

  pComMesgHdr->sequenceId = hton16(sync_seq_id);

  pComMesgHdr->controlField = PTP_CTL_FIELD_SYNC;

  pComMesgHdr->logMessageInterval = PTP_LOG_SYNC_INTERVAL;

  // transmit the packet and record the egress time.
  ptp_tx_timed(c_tx, buf0,
               SYNC_PACKET_SIZE,
               local_egress_ts,
               port_num);

#if DEBUG_PRINT
  debug_printf("TX sync, Port %d\n", port_num);
#endif

  // Send Follow_Up message

  pComMesgHdr->transportSpecific_messageType =
    PTP_TRANSPORT_SPECIFIC_HDR | PTP_FOLLOW_UP_MESG;

  pComMesgHdr->controlField = PTP_CTL_FIELD_FOLLOW_UP;

  pComMesgHdr->messageLength = hton16(sizeof(ComMessageHdr) +
                                      sizeof(FollowUpMessage));

  pComMesgHdr->flagField[0] = 0;   // clear two steps flag for follow up

  // populate the time in packet
  local_to_ptp_ts(ptp_egress_ts, local_egress_ts);

  timestamp_to_network(pFollowUpMesg->preciseOriginTimestamp, ptp_egress_ts);

  for(int i=0;i<8;i++) pComMesgHdr->correctionField.data[i] = 0;

  // Fill in follow up fields as per 802.1as section 11.4.4.2
  pFollowUpMesg->tlvType = hton16(0x3);
  pFollowUpMesg->lengthField = hton16(28);
  pFollowUpMesg->organizationId[0] = 0x00;
  pFollowUpMesg->organizationId[1] = 0x80;
  pFollowUpMesg->organizationId[2] = 0xc2;
  pFollowUpMesg->organizationSubType[0] = 0;
  pFollowUpMesg->organizationSubType[1] = 0;
  pFollowUpMesg->organizationSubType[2] = 1;

  ptp_tx(c_tx, buf0, FOLLOWUP_PACKET_SIZE, port_num);

#if DEBUG_PRINT
  debug_printf("TX sync follow up, Port %d\n", port_num);
#endif

  return;
}

static u16_t pdelay_req_seq_id[PTP_NUM_PORTS];
static unsigned pdelay_request_sent[PTP_NUM_PORTS];
static unsigned pdelay_request_sent_ts[PTP_NUM_PORTS];

static void send_ptp_pdelay_req_msg(chanend c_tx, int port_num)
{
#define PDELAY_REQ_PACKET_SIZE (sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr) + sizeof(PdelayReqMessage))
  unsigned int buf0[(PDELAY_REQ_PACKET_SIZE+3)/4];
  unsigned char *buf = (unsigned char *) &buf0[0];
  ComMessageHdr *pComMesgHdr = (ComMessageHdr *) &buf[sizeof(ethernet_hdr_t)];

  set_ptp_ethernet_hdr(buf);

  int message_length = sizeof(ComMessageHdr) + sizeof(PdelayReqMessage);

  // clear the send data first.
  memset(pComMesgHdr, 0, message_length);

  // build up the packet as required.
  pComMesgHdr->transportSpecific_messageType =
    PTP_TRANSPORT_SPECIFIC_HDR | PTP_PDELAY_REQ_MESG;

  pComMesgHdr->versionPTP = PTP_VERSION_NUMBER;

  pComMesgHdr->messageLength = hton16(message_length);

  pComMesgHdr->flagField[1] = (PTP_TIMESCALE & 0x1) << 3;

  // correction field, & flagField are zero.
  for(int i=0;i<8;i++) pComMesgHdr->correctionField.data[i] = 0;

  for (int i=0; i < 8; i++) {
    pComMesgHdr->sourcePortIdentity.data[i] = my_port_id.data[i];
  }
  pComMesgHdr->sourcePortIdentity.data[9] = port_num + 1;

  // increment the sequence id.
  pdelay_req_seq_id[port_num] += 1;
  pComMesgHdr->sequenceId = hton16(pdelay_req_seq_id[port_num]);

  // control field for backward compatiability
  pComMesgHdr->controlField = PTP_CTL_FIELD_OTHERS;
  pComMesgHdr->logMessageInterval = PTP_LOG_MIN_PDELAY_REQ_INTERVAL;

  // sent out the data and record the time.

  ptp_tx_timed(c_tx, buf0,
               PDELAY_REQ_PACKET_SIZE,
               pdelay_request_sent_ts[port_num],
               port_num);

  pdelay_request_sent[port_num] = 1;

#if DEBUG_PRINT
  debug_printf("TX Pdelay req, Port %d\n", port_num);
#endif

  return;
}

void local_to_epoch_ts(unsigned local_ts, ptp_timestamp *epoch_ts)
{
  unsigned long long sec;
  unsigned long long nanosec;

  if (local_ts <= prev_pdelay_local_ts) // We overflowed 32 bits
  {
    pdelay_epoch_timer += ((UINT_MAX - prev_pdelay_local_ts) + local_ts);
  }
  else
  {
    pdelay_epoch_timer += (local_ts - prev_pdelay_local_ts);
  }

  nanosec = pdelay_epoch_timer * 10;

  sec = nanosec / NANOSECONDS_PER_SECOND;
  nanosec = nanosec % NANOSECONDS_PER_SECOND;

  epoch_ts->seconds[1] = (unsigned) (sec >> 32);

  epoch_ts->seconds[0] = (unsigned) sec;

  epoch_ts->nanoseconds = nanosec;

  prev_pdelay_local_ts = local_ts;

}

static void send_ptp_pdelay_resp_msg(chanend c_tx,
                              char *pdelay_req_msg,
                              unsigned req_ingress_ts,
                              int port_num)
{
#define PDELAY_RESP_PACKET_SIZE (sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr) + sizeof(PdelayRespMessage))
  unsigned int buf0[(PDELAY_RESP_PACKET_SIZE+3)/4];
  unsigned char *buf = (unsigned char *) &buf0[0];
  // received packet pointers.
  ComMessageHdr *pRxMesgHdr = (ComMessageHdr *) pdelay_req_msg;
  // transmit packet pointers.
  ComMessageHdr *pTxMesgHdr = (ComMessageHdr *) &buf[sizeof(ethernet_hdr_t)];
  PdelayRespMessage *pTxRespHdr =
   (PdelayRespMessage *) &buf[sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr)];
  PdelayRespFollowUpMessage *pTxFollowUpHdr =
   (PdelayRespFollowUpMessage *) &buf[sizeof(ethernet_hdr_t) + sizeof(ComMessageHdr)];

  ptp_timestamp epoch_req_ingress_ts;
  ptp_timestamp epoch_resp_ts;
  unsigned local_resp_ts;

  set_ptp_ethernet_hdr(buf);

  memset(pTxMesgHdr, 0, sizeof(ComMessageHdr) + sizeof(PdelayRespMessage));

  pTxMesgHdr->versionPTP = PTP_VERSION_NUMBER;

  pTxMesgHdr->messageLength = hton16(sizeof(ComMessageHdr) +
                                     sizeof(PdelayRespMessage));

  pTxMesgHdr->flagField[0] = 0x2;   // set two steps flag
  pTxMesgHdr->flagField[1] = (PTP_TIMESCALE & 0x1) << 3;

  for (int i=0; i < 8; i++) {
    pTxMesgHdr->sourcePortIdentity.data[i] = my_port_id.data[i];
  }
  pTxMesgHdr->sourcePortIdentity.data[9] = port_num + 1;

  pTxMesgHdr->controlField = PTP_CTL_FIELD_OTHERS;
  pTxMesgHdr->logMessageInterval = 0x7F;

  pTxMesgHdr->sequenceId = pRxMesgHdr->sequenceId;

  memcpy(&pTxRespHdr->requestingPortIdentity, &pRxMesgHdr->sourcePortIdentity, sizeof(pTxRespHdr->requestingPortIdentity));
  pTxRespHdr->requestingPortId.data[0] = pRxMesgHdr->sourcePortIdentity.data[8];
  pTxRespHdr->requestingPortId.data[1] = pRxMesgHdr->sourcePortIdentity.data[9];

  pTxMesgHdr->domainNumber = pRxMesgHdr->domainNumber;

  pTxMesgHdr->correctionField = pRxMesgHdr->correctionField;

  /* Send the response message */

  pTxMesgHdr->transportSpecific_messageType =
    PTP_TRANSPORT_SPECIFIC_HDR | PTP_PDELAY_RESP_MESG;

  local_to_epoch_ts(req_ingress_ts, &epoch_req_ingress_ts);

  timestamp_to_network(pTxRespHdr->requestReceiptTimestamp,
                       epoch_req_ingress_ts);

  ptp_tx_timed(c_tx,  buf0, PDELAY_RESP_PACKET_SIZE, local_resp_ts, port_num);
#if DEBUG_PRINT
  debug_printf("TX Pdelay resp, Port %d\n", port_num);
#endif

  /* Now send the follow up */

  local_to_epoch_ts(local_resp_ts, &epoch_resp_ts);

  pTxMesgHdr->transportSpecific_messageType =
    PTP_TRANSPORT_SPECIFIC_HDR | PTP_PDELAY_RESP_FOLLOW_UP_MESG;

  pTxMesgHdr->flagField[0] = 0;   // clear two steps flag

  timestamp_to_network(pTxFollowUpHdr->responseOriginTimestamp,
                       epoch_resp_ts);

  ptp_tx(c_tx, buf0, PDELAY_RESP_PACKET_SIZE, port_num);
#if DEBUG_PRINT
  debug_printf("TX Pdelay resp follow up, Port %d\n", port_num);
#endif

  return;
}


static unsigned received_pdelay[PTP_NUM_PORTS];
static u16_t received_pdelay_id[PTP_NUM_PORTS];
static unsigned pdelay_resp_ingress_ts[PTP_NUM_PORTS];
static ptp_timestamp pdelay_request_receipt_ts[PTP_NUM_PORTS];

static int qualify_announce(ComMessageHdr &alias header, AnnounceMessage &alias announce_msg, int this_port)
{
  for (int i=0; i < 8; i++) {
    if (header.sourcePortIdentity.data[i] != my_port_id.data[i]) {
      break;
    }
    if (i == 7) {
      return 0;
    }
  }

  if (ntoh16(announce_msg.stepsRemoved) >= 255) {
    return 0;
  }

  int tlv = ntoh16(announce_msg.tlvLength) / 8;
  if (tlv) {
    if (tlv > PTP_MAXIMUM_PATH_TRACE_TLV) {
      tlv = PTP_MAXIMUM_PATH_TRACE_TLV;
    }
    for (int i=0; i < tlv; i++) {
      if (!compare_clock_identity_to_me(&announce_msg.pathSequence[i])) {
        return 0;
      }
    }
  }

  return 1;
}

static void set_ascapable(int eth_port) {
  ptp_port_info[eth_port].asCapable = 1;
  set_new_role(PTP_MASTER, eth_port);
#if DEBUG_PRINT_AS_CAPABLE
  debug_printf("asCapable = 1\n");
#endif
}

static void reset_ascapable(int eth_port) {
  ptp_port_info[eth_port].asCapable = 0;
  set_new_role(PTP_DISABLED, eth_port);

#if DEBUG_PRINT_AS_CAPABLE
  debug_printf("asCapable = 0\n");
#endif
}

static void pdelay_req_reset(int src_port) {
  received_pdelay[src_port] = 0;

  if (ptp_port_info[src_port].delay_info.lost_responses < PTP_ALLOWED_LOST_RESPONSES) {
    ptp_port_info[src_port].delay_info.lost_responses++;
#if DEBUG_PRINT_AS_CAPABLE
    debug_printf("Lost responses: %d\n", ptp_port_info[src_port].delay_info.lost_responses);
#endif
  }
  else {
    reset_ascapable(src_port);
  }
}

void ptp_recv(chanend c_tx,
              unsigned char buf[],
              unsigned local_ingress_ts,
              unsigned src_port,
              unsigned len)
{

  /* Extract the ethernet header and ptp common message header */
  struct ethernet_hdr_t *ethernet_hdr = (ethernet_hdr_t *) &buf[0];
  int has_qtag = ethernet_hdr->ethertype.data[1]==0x18;
  int ethernet_pkt_size = has_qtag ? 18 : 14;
  ComMessageHdr *msg =  (ComMessageHdr *) &buf[ethernet_pkt_size];

  local_ingress_ts = local_ingress_ts - tile_timer_offset;

  int asCapable = ptp_port_info[src_port].asCapable;

  if (GET_PTP_TRANSPORT_SPECIFIC(msg) != 1) {
    return;
  }

  switch ((msg->transportSpecific_messageType & 0xf))
    {
    case PTP_ANNOUNCE_MESG:
      AnnounceMessage *announce_msg = (AnnounceMessage *) (msg + 1);
      if (asCapable && qualify_announce(*msg, *announce_msg, src_port)) {
#if DEBUG_PRINT_ANNOUNCE
      debug_printf("RX Announce, Port %d\n", src_port);
#endif
        bmca_update_roles((char *) msg, local_ingress_ts, src_port);

        if (ptp_port_info[src_port].role_state == PTP_SLAVE &&
            source_port_identity_equal(msg->sourcePortIdentity, master_port_id) &&
            clock_id_equal(&best_announce_msg.grandmasterIdentity,
                           &announce_msg->grandmasterIdentity)) {
          last_received_announce_time_valid[src_port] = 1;
          last_received_announce_time[src_port] = local_ingress_ts;
        }
      }
      break;
    case PTP_SYNC_MESG:

      if (asCapable &&
          !received_sync &&
          ptp_port_info[src_port].role_state == PTP_SLAVE) {
        received_sync = 1;
        received_sync_id = ntoh16(msg->sequenceId);
        received_sync_ts = local_ingress_ts;
        last_received_sync_time[src_port] = local_ingress_ts;
        last_receive_sync_upstream_interval[src_port] = LOG_SEC_TO_TIMER_TICKS((signed char)(msg->logMessageInterval));
#if DEBUG_PRINT
        debug_printf("RX Sync, Port %d\n", src_port);
#endif
      }
      break;
    case PTP_FOLLOW_UP_MESG:
      if ((received_sync == 1) &&
          source_port_identity_equal(msg->sourcePortIdentity, master_port_id)) {

        if (received_sync_id == ntoh16(msg->sequenceId)) {
          FollowUpMessage *follow_up_msg = (FollowUpMessage *) (msg + 1);
          ptp_timestamp master_egress_ts;
          long long correction;

          correction = ntoh64(msg->correctionField);

          network_to_ptp_timestamp(master_egress_ts,
                                   follow_up_msg->preciseOriginTimestamp);

          ptp_timestamp_offset64(master_egress_ts, master_egress_ts,
                                 correction>>16);

          if (update_adjust(master_egress_ts,received_sync_ts) == 0) {
            update_reference_timestamps(master_egress_ts, received_sync_ts, ptp_port_info[src_port]);
          }
#if DEBUG_PRINT
          debug_printf("RX Follow Up, Port %d\n", src_port);
#endif
          received_sync = 2;
        }
      }
      else
      {
        received_sync = 0;
      }
      break;
    case PTP_PDELAY_REQ_MESG:
#if DEBUG_PRINT
      debug_printf("RX Pdelay req, Port %d\n", src_port);
#endif
      send_ptp_pdelay_resp_msg(c_tx, (char *) msg, local_ingress_ts, src_port);
      break;
    case PTP_PDELAY_RESP_MESG:
      PdelayRespMessage *resp_msg = (PdelayRespMessage *) (msg + 1);

      if (!pdelay_request_sent[src_port] &&
          received_pdelay[src_port] &&
          !source_port_identity_equal(msg->sourcePortIdentity, ptp_port_info[src_port].delay_info.rcvd_source_identity) &&
          pdelay_req_seq_id[src_port] == ntoh16(msg->sequenceId)) {

        if (!ptp_port_info[src_port].delay_info.multiple_resp_count ||
            (pdelay_req_seq_id[src_port] == ptp_port_info[src_port].delay_info.last_multiple_resp_seq_id+1)) {
          // Count consecutive multiple pdelay responses for a single pdelay request
          ptp_port_info[src_port].delay_info.multiple_resp_count++;
        }
        else {
          ptp_port_info[src_port].delay_info.multiple_resp_count = 0;
        }
        ptp_port_info[src_port].delay_info.last_multiple_resp_seq_id = pdelay_req_seq_id[src_port];
        pdelay_req_reset(src_port);
        break;
      }

      if (pdelay_request_sent[src_port] &&
          pdelay_req_seq_id[src_port] == ntoh16(msg->sequenceId) &&
          port_identity_equal(resp_msg->requestingPortIdentity, my_port_id) &&
          src_port+1 == ntoh16(resp_msg->requestingPortId)
          ) {
          received_pdelay[src_port] = 1;
          received_pdelay_id[src_port] = ntoh16(msg->sequenceId);
          pdelay_resp_ingress_ts[src_port] = local_ingress_ts;
          network_to_ptp_timestamp(pdelay_request_receipt_ts[src_port],
                                   resp_msg->requestReceiptTimestamp);
#if DEBUG_PRINT
          debug_printf("RX Pdelay resp, Port %d\n", src_port);
#endif
          ptp_port_info[src_port].delay_info.rcvd_source_identity = msg->sourcePortIdentity;
        }
        else {
          pdelay_req_reset(src_port);
        }
        pdelay_request_sent[src_port] = 0;

      break;
    case PTP_PDELAY_RESP_FOLLOW_UP_MESG:
      if (received_pdelay[src_port] &&
          received_pdelay_id[src_port] == ntoh16(msg->sequenceId) &&
          source_port_identity_equal(msg->sourcePortIdentity, ptp_port_info[src_port].delay_info.rcvd_source_identity)) {
          ptp_timestamp pdelay_resp_egress_ts;
          PdelayRespFollowUpMessage *follow_up_msg =
            (PdelayRespFollowUpMessage *) (msg + 1);

          network_to_ptp_timestamp(pdelay_resp_egress_ts,
                                   follow_up_msg->responseOriginTimestamp);

          update_path_delay(pdelay_request_receipt_ts[src_port],
                            pdelay_resp_egress_ts,
                            pdelay_request_sent_ts[src_port],
                            pdelay_resp_ingress_ts[src_port],
                            ptp_port_info[src_port]);

          ptp_port_info[src_port].delay_info.exchanges++;

          if (ptp_port_info[src_port].delay_info.valid &&
              ptp_port_info[src_port].delay_info.pdelay <= PTP_NEIGHBOR_PROP_DELAY_THRESH_NS &&
              ptp_port_info[src_port].delay_info.exchanges >= 2) {
            if (!ptp_port_info[src_port].asCapable) {
              set_ascapable(src_port);
            }
          }
          else {
            reset_ascapable(src_port);
          }
          ptp_port_info[src_port].delay_info.lost_responses = 0;
#if DEBUG_PRINT
          debug_printf("RX Pdelay resp follow up, Port %d\n", src_port);
#endif

        }
        else {
          pdelay_req_reset(src_port);
        }
        received_pdelay[src_port] = 0;
      break;
    }
}

void ptp_init(chanend c_tx, chanend c_rx, enum ptp_server_type stype)
{
  unsigned t;
  mac_get_tile_timer_offset(c_rx, tile_timer_offset);
  t = get_local_time();

  if (stype == PTP_GRANDMASTER_CAPABLE) {
    ptp_priority1 = PTP_DEFAULT_GM_CAPABLE_PRIORITY1;
  }
  else {
    ptp_priority1 = PTP_DEFAULT_NON_GM_CAPABLE_PRIORITY1;
  }

  mac_get_macaddr(c_tx, src_mac_addr);

  for (int i=0; i < 3; i ++)
    my_port_id.data[i] = src_mac_addr[i];

  my_port_id.data[3] = 0xff;
  my_port_id.data[4] = 0xfe;
  for (int i=5; i < 8; i ++)
    my_port_id.data[i] = src_mac_addr[i-2];

  for (int i=0; i < PTP_NUM_PORTS; i++)
  {
    set_new_role(PTP_MASTER, i);
    last_received_announce_time_valid[i] = 0;
    ptp_port_info[i].delay_info.multiple_resp_count = 0;
    periodic_counter = 0;
  }

  pdelay_epoch_timer = t;
}

void ptp_periodic(chanend c_tx, unsigned t)
{
  for (int i=0; i < PTP_NUM_PORTS; i++)
  {
    int role = ptp_port_info[i].role_state;
    int asCapable = ptp_port_info[i].asCapable;

    int recv_sync_timeout_interval = last_receive_sync_upstream_interval[i] * PTP_SYNC_RECEIPT_TIMEOUT_MULTIPLE;

    int sending_pdelay = (ptp_port_info[i].delay_info.multiple_resp_count < 3);

    if (!sending_pdelay) {
      periodic_counter++;
      const int five_minutes_in_periodic = 5 * 60 * (XS1_TIMER_HZ/PTP_PERIODIC_TIME);
      if (periodic_counter >= five_minutes_in_periodic) {
        sending_pdelay = 1;
        ptp_port_info[i].delay_info.multiple_resp_count = 0;
        periodic_counter = 0;
      }
    }

    if ((last_received_announce_time_valid[i] &&
        timeafter(t, last_received_announce_time[i] + RECV_ANNOUNCE_TIMEOUT)) ||
        // syncReceiptTimeout
        (received_sync && (ptp_port_info[i].role_state == PTP_SLAVE) &&
        timeafter(t, last_received_sync_time[i] + recv_sync_timeout_interval)) ||
        // followUpReceiptTimeout:
        (received_sync == 1 && (ptp_port_info[i].role_state == PTP_SLAVE) &&
        timeafter(t, last_received_sync_time[i] + last_receive_sync_upstream_interval[i])))  {

      received_sync = 0;

      if (role == PTP_SLAVE ) {
        set_new_role(PTP_UNCERTAIN, i);
        last_received_announce_time[i] = t;
        last_announce_time[i] = t - ANNOUNCE_PERIOD - 1;
#if DEBUG_PRINT_ANNOUNCE
        debug_printf("RX Announce timeout, Port %d\n", i);
#endif
      }
      else if (role == PTP_UNCERTAIN) {
        set_new_role(PTP_MASTER, i);
      }
    }

    if (asCapable && (role == PTP_MASTER || role == PTP_UNCERTAIN) &&
        timeafter(t, last_announce_time[i] + ANNOUNCE_PERIOD)) {
      send_ptp_announce_msg(c_tx, i);
      last_announce_time[i] = t;
    }

    if (asCapable && role == PTP_MASTER &&
        timeafter(t, last_sync_time[i] + SYNC_PERIOD)) {
      send_ptp_sync_msg(c_tx, i);
      last_sync_time[i] = t;
    }

    if (timeafter(t, last_pdelay_req_time[i] + PDELAY_REQ_PERIOD)) {
      if (pdelay_request_sent[i] && !received_pdelay[i]) {
        pdelay_req_reset(i);
      }
      if (sending_pdelay) send_ptp_pdelay_req_msg(c_tx, i);
      last_pdelay_req_time[i] = t;
    }
  }

  periodic_update_reference_timestamps(t);
}

void ptp_current_grandmaster(char grandmaster[8])
{
  memcpy(grandmaster, best_announce_msg.grandmasterIdentity.data, 8);
}
