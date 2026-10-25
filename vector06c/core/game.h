/* game.h - rules, setup, combat. No I/O. */
#ifndef GAME_H
#define GAME_H

#include "stratego.h"

/* Combat outcomes, matching the original's BO codes. */
#define BO_BOTH_DIE      0
#define BO_ATTACKER_WINS 1
#define BO_DEFENDER_WINS 2

typedef struct {
    u8 fought;      /* a battle took place                   */
    s8 att_value;   /* ranks as they were before resolution  */
    s8 def_value;
    s8 att_id;      /* index of the attacker in its own array */
    s8 def_id;      /* index of the defender, -1 if no battle */
    u8 result;      /* BO_*                                  */
    u8 flag_taken;
} Combat;

void game_new(GameState *g, u16 seed);
void game_setup_computer(GameState *g);
void game_setup_player_random(GameState *g);
void game_rebuild_grid(GameState *g);

/* 0 = illegal. side is SIDE_COMP or SIDE_PLAY. */
u8 game_legal(GameState *g, u8 side, s8 fc, s8 fr, s8 tc, s8 tr);

/* Caller must have validated with game_legal (the AI is trusted). */
void game_apply(GameState *g, u8 side, s8 fc, s8 fr, s8 tc, s8 tr, Combat *ci);

/* 1 when that side has no movable piece left. */
u8 game_check_loss(GameState *g, u8 side);

s8 game_count_alive(GameState *g, u8 side);

#endif
