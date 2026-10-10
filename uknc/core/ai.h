/* ai.h - move generation and scoring. Pure logic, no I/O. */
#ifndef AI_H
#define AI_H

#include "stratego.h"

/* --- score constants, SPEC section 9 ------------------------------- */
#define AI_URGENT_HIT     100   /* guard attack, spy takes marshal      */
#define AI_FLANK_BONUS     60   /* pv + this, attacking unknown sideways */
#define AI_MOVED_BONUS     60   /* pv + this, target has moved before   */
#define AI_SPY_LOOSE       70   /* spy attacking unknown once mdflag    */
#define AI_STILL_BONUS     40   /* pv + this, target never moved        */
#define AI_FLEE_BONUS      45   /* pv + this, empty square while fleeing */
#define AI_KILL_MINER      32   /* pv + this, known weaker miner        */
#define AI_KILL_BONUS      30   /* pv + this, known weaker piece        */
#define AI_DEFUSE          50   /* miner onto known bomb                */
#define AI_GUARD_RETURN    50   /* guard walking back to its post       */
#define AI_SEEK_BASE       35   /* 35 + pv - dist                       */
#define AI_FORWARD          3   /* pv + this                            */
#define AI_BACKWARD        -2   /* pv + this                            */

#define AI_SEEK_GATE       27   /* seeking engages at pleft <= this     */
#define AI_TIE_SLOTS        5

/* --- defect switches, SPEC section 8 -------------------------------
 * g_ai defaults to the recommended set (see ai.c). Zero every field to
 * reproduce the original's behaviour, bugs included, for comparison.
 *
 * When porting, take the fixed path and drop the branches - these exist to
 * keep the faithful baseline measurable, not because the target needs them. */
typedef struct {
    u8 fix_mdflag;   /* 8.1 spy unlock                      off - measured neutral */
    u8 fix_dist;     /* 8.2 real distance in seek score     off */
    u8 fix_checken;  /* 8.3 position-test the miner clause  ON  */
    u8 fix_seek;     /* 8.4 target/score desync             ON  */
    u8 fix_flank;    /* 8.5 flank attack validates target   ON  */
    u8 fix_guard;    /* 8.7 guard steps home, not teleports ON  */
    u8 fix_setup;    /* 8.6 marshal/general placement check ON  */
} AiFlags;

extern AiFlags g_ai;

typedef struct {
    s16 score;      /* -1 = no acceptable move       */
    s8  col, row;
    u8  attack;     /* destination holds an enemy    */
    u8  urgent;     /* execute now, skip the tie list */
} Move;

void ai_reset(void);

#ifdef HARNESS
/* Rare-path counters. Coverage evidence for the trace oracle, and the only
 * way to see how often the leftover defects actually fire. */
#define AI_CNT_SEEK       0
#define AI_CNT_SEEK_DROP  1     /* seek overwrote the target but lost the score */
#define AI_CNT_FLANK      2
#define AI_CNT_GUARD      3
#define AI_CNT_SPY_MARSH  4
#define AI_CNT_FLEE       5
#define AI_CNT_DEFUSE     6
#define AI_CNT_MAX        7
extern long g_ai_count[AI_CNT_MAX];

/* ai.c keeps XB's stale by-reference parameters as file statics. Two AIs
 * alternating would cross-contaminate them, so the harness swaps a set per
 * side. Opaque on purpose - only ai.c knows what is in it. */
typedef struct { s8 tx, ty, dir, mtx, mty; u8 flag; s16 dist; } AiPersist;
void ai_state_save(AiPersist *p);
void ai_state_load(const AiPersist *p);
#endif
u8   ai_choose_move(GameState *g, s8 *from_id, Move *out);   /* 0 = resign */
void ai_gen_move(GameState *g, s8 id, Move *m);
void ai_scout_move(GameState *g, s8 id, Move *m);
u8   ai_check_enemy(GameState *g, s8 pv, s8 col, s8 row);
void ai_find_nearest(GameState *g, s8 id, s8 *dx, s8 *dy);

/* Tracing, for debugging an incomplete-information AI. */
extern u8 g_ai_trace;

#endif
