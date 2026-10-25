/* rng.h - seedable 16-bit xorshift.
 *
 * Deliberately NOT rand(). Every random decision in the AI goes through this
 * so a seed reproduces a game exactly: needed for tuning regressions and for
 * validating a later assembler port against this reference move-for-move.
 * Hand-translates to roughly 20 bytes of 8-bit assembler.
 */
#ifndef RNG_H
#define RNG_H

#include "stratego.h"

void rng_seed(u16 seed);
u16  rng_next(void);
u8   rng_range(u8 n);   /* 0 .. n-1 */

#ifdef HARNESS
/* Head-to-head play gives each side its own stream, so one side's decisions
 * cannot perturb the other's. Not needed by the game or by a port. */
u16  rng_get_state(void);
void rng_set_state(u16 state);
#endif

#endif
