#include "random.h"
#include <xs1.h>

static const unsigned random_poly = 0xEDB88320;

unsigned random_get_random_number(random_generator_t &g)
{
  crc32(g, -1, random_poly);
  return (unsigned) g;
}

random_generator_t random_create_generator_from_seed(unsigned seed)
{
  random_generator_t gen = (random_generator_t) seed;
  (void) random_get_random_number(gen);
  return gen;
}

static const unsigned XS1_L_RING_OSCILLATOR_VALUE_REG  = 0x070B;

random_generator_t random_create_generator_from_hw_seed(void)
{
  unsigned init_seed = getps(XS1_L_RING_OSCILLATOR_VALUE_REG);
  return random_create_generator_from_seed(init_seed);
}

