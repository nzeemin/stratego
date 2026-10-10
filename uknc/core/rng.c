#include "rng.h"

static u16 s_state = 1;

void rng_seed(u16 seed)
{
    s_state = seed ? seed : 1;
}

u16 rng_next(void)
{
    u16 x = s_state;
    x ^= (u16)(x << 7);
    x ^= (u16)(x >> 9);
    x ^= (u16)(x << 8);
    s_state = x;
    return x;
}

u8 rng_range(u8 n)
{
    return (u8)(rng_next() % (u16)n);
}

#ifdef HARNESS
u16  rng_get_state(void)      { return s_state; }
void rng_set_state(u16 state) { s_state = state ? state : 1; }
#endif
