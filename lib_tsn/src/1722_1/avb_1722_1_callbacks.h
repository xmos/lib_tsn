#ifndef _avb_1722_1_callbacks_h_
#define _avb_1722_1_callbacks_h_

#include "avb_1722_1_aecp_aem.h"

#ifdef __XC__
interface avb_1722_1_control_callbacks {
  /** This function events on a GET_CONTROL 1722.1 command received from a Controller.
    *
    * \param control_index  the index of the CONTROL descriptor
    * \param values_length  a reference to the length in bytes of the ``values`` array
    * \param values         an array of values to return to the Controller
    *                       The contents of this field are dependent on the Control being fetched.
    *
    * \returns              an AEM status code of enum ``avb_1722_1_aecp_aem_status_code`` for the GET_CONTROL response
    */
  unsigned char get_control_value(unsigned short control_index,
                                  unsigned short &values_length,
                                  unsigned char values[AEM_MAX_CONTROL_VALUES_LENGTH_BYTES]);

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
                                  unsigned char values[AEM_MAX_CONTROL_VALUES_LENGTH_BYTES]);

};
#endif

#endif // _api_h_
