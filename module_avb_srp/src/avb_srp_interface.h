#ifndef _avb_srp_interface_h_
#define _avb_srp_interface_h_
#include <xccompat.h>
#include "xc2compat.h"
#include "avb_srp_pdu.h"
#include "avb_1722_talker.h"
#include "avb_mrp.h"
#include "avb_control_types.h"
#include "avb_stream.h"
#include "avb_api.h"

#ifdef __XC__
interface srp_interface {
  /** Used by a Talker application entity to issue a request to the MSRP Participant
   *  to initiate the advertisement of an available Stream
   *
   *  \param stream_info Struct of type avb_srp_info_t containing parameters of the stream to register
   */
  void register_stream_request(avb_srp_info_t stream_info);

  /** Used by a Talker application entity to request removal of the Talker’s advertisement declaration,
   *  and thus remove the advertisement of a Stream, from the network.
   *
   *  \param stream_id two int array containing the Stream ID of the stream to deregister
   */
  void deregister_stream_request(unsigned stream_id[2]);

  /** Used by a Listener application entity to issue a request to attach to the referenced Stream.
   *
   *  \param stream_id two int array containing the Stream ID of the stream to register
   */
  void register_attach_request(unsigned stream_id[2]);

  /** Used by a Listener application entity to remove the request to attach to the referenced Stream.
   *
   *  \param stream_id two int array containing the Stream ID of the stream to deregister
   */
  void deregister_attach_request(unsigned stream_id[2]);
};

#endif


#endif // _avb_srp_interface_h_
