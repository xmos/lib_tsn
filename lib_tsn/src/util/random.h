#ifndef __RANDOM_H__
#define __RANDOM_H__

#include <xccompat.h>

#ifdef __random_conf_h_exists__
#include "random_conf.h"
#endif

/** This define controls whether hardware seeded random numbers can be
    used. By setting this define, one of the devices ring oscillators will
    be set running at startup and then can be used later on to seed a
    random number generator. */
#ifndef RANDOM_ENABLE_HW_SEED
#define RANDOM_ENABLE_HW_SEED 0
#endif

/** Type representing a random number generator.
 */
typedef unsigned random_generator_t;

/** Function that creates a random number generator from a seed.
 *
 * \param seed  seed for the generator.
 *
 * \returns     a random number generator.
 */
random_generator_t random_create_generator_from_seed(unsigned seed);

#if (defined(__XS1_L__) && RANDOM_ENABLE_HW_SEED) || defined(__DOXYGEN__)
/** Function that attempts to create a random number generator from
 *  a true random value into the seed, using
 *  an asynchronous timer. To use this function you must enable the
 *  ``RANDOM_ENABLE_HW_SEED`` define in your application's ``random_conf.h``.
 *
 *  \returns a random number generator.
 */
random_generator_t random_create_generator_from_hw_seed(void);
#endif


/** Function that produces a random number. The number has a cycle of 2^32
 *  and is produced using a LFSR.
 *
 *  \param g    the used generator to produce the seed.
 *
 *  \returns    a random 32 bit number.
 */
unsigned
random_get_random_number(REFERENCE_PARAM(random_generator_t, g));

#endif // __RANDOM_H__
