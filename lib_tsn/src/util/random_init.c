#include "random.h"
#include <xs1.h>

#if (defined(__XS1_L__) && RANDOM_ENABLE_HW_SEED)

static const unsigned XS1_L_RING_OSCILLATOR_CONTROL_REG    = 0x060B;
static const unsigned XS1_L_RING_OSCILLATOR_CONTROL_START  = 0x3;

__attribute__((constructor))
void random_simple_init_seed()
{
/* This constructor starts of the ring oscillator when the program loads.
   This will run on an asynchronous time base to the main xCORE. By starting it
   off now the later call to random_create_generator_from_hw_seed will pick up
   a value later which has drifted to a random state */
  setps(XS1_L_RING_OSCILLATOR_CONTROL_REG,
        XS1_L_RING_OSCILLATOR_CONTROL_START);
}

#endif
