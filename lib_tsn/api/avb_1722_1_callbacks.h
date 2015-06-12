// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef _avb_1722_1_callbacks_h_
#define _avb_1722_1_callbacks_h_

#include "avb_1722_1_aecp_aem.h"

#ifdef __XC__
/** A callback interface for 1722.1 events */
interface avb_1722_1_control_callbacks {
  /** This function events on a GET_CONTROL 1722.1 command received from a Controller.
    *
    * \param control_index  the index of the CONTROL descriptor
    * \param value_size     the size in bytes of the type of the value
    * \param values_length  a reference to the length in bytes of the ``values`` array
    * \param values         an array of values to return to the Controller
    *                       The contents of this field are dependent on the Control being fetched.
    *
    * \returns              an AEM status code of enum ``avb_1722_1_aecp_aem_status_code`` for the GET_CONTROL response
    */
  unsigned char get_control_value(unsigned short control_index,
                                  unsigned int &value_size,
                                  unsigned short &values_length,
                                  unsigned char values[]);

  /** This function events on a SET_CONTROL 1722.1 command received from a Controller.
    *
    * The response should always contain the current value (i.e. it contains the new
    * value if the commands succeeds, or the old value if it fails)
    *
    * \param control_index  the index of the CONTROL descriptor
    * \param values_length  the length in bytes of the ``values`` array
    * \param values         an array of values to set from the Controller.
    *                       The contents of this field are dependent on the Control being addressed.
    *
    * \returns              an AEM status code of enum ``avb_1722_1_aecp_aem_status_code`` for the SET_CONTROL response
    */
  unsigned char set_control_value(unsigned short control_index,
                                  unsigned short values_length,
                                  unsigned char values[]);

  /** This function events on a GET_SIGNAL_SELECTOR 1722.1 command received from a Controller.
    *
    * \param selector_index the index of the SIGNAL_SELECTOR descriptor
    * \param signal_type    a reference to the descriptor type of signal source for the selector
    * \param signal_index   a reference to the descriptor index of signal source for the selector
    * \param signal_output  a reference to the index of the output of the signal source of the selector
    *
    * \returns              an AEM status code of enum ``avb_1722_1_aecp_aem_status_code`` for the GET_SIGNAL_SELECTOR response
    */
  unsigned char get_signal_selector(unsigned short selector_index,
                                    unsigned short &signal_type,
                                    unsigned short &signal_index,
                                    unsigned short &signal_output);

  /** This function events on a SET_SIGNAL_SELECTOR 1722.1 command received from a Controller.
    *
    * \param selector_index the index of the SIGNAL_SELECTOR descriptor
    * \param signal_type    the descriptor type of signal source for the selector
    * \param signal_index   the descriptor index of signal source for the selector
    * \param signal_output  the index of the output of the signal source of the selector
    *
    * \returns              an AEM status code of enum ``avb_1722_1_aecp_aem_status_code`` for the SET_SIGNAL_SELECTOR response
    */
  unsigned char set_signal_selector(unsigned short selector_index,
                                    unsigned short signal_type,
                                    unsigned short signal_index,
                                    unsigned short signal_output);

};
#endif

#endif // _api_h_
