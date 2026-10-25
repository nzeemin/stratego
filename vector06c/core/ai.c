/* ai.c - faithful transcription of Vorticon's GENMOVE / SCOUTMOVE /
 * CHECKEN / FINDEN and the top-level move selection.
 *
 * Structured with gotos mirroring the original's labels on purpose: it keeps
 * the correspondence checkable line by line against the BASIC source, and it
 * translates directly to assembler later.
 *
 * Faithful means faithful: the known defects of SPEC section 8 are reproduced,
 * including the uninitialised variables that survive across calls. Those live
 * as file-scope statics below, mirroring XB's by-reference parameters that the
 * original never initialises on entry.
 */
#include "ai.h"
#include "rng.h"

#ifdef AI_TRACE
#include <stdio.h>
#endif

/* Recommended set, chosen by measurement rather than by argument.
 *
 * fix_mdflag is OFF: head to head over 10,000 games it scores 49.1% +-1.1,
 *   i.e. no effect. Freeing the Spy makes it charge unknown pieces at score 70
 *   and die, which is worth about what leaving it frozen is worth. Turn it on
 *   only together with a re-tuned AI_SPY_LOOSE.
 * fix_dist is off because enabling it changes what the score table was
 *   balanced against.
 * fix_seek is ON despite measuring neutral (49.7% +-1.1 over 10,000 games).
 *   The desync fires ~39 times a game, and committing target and score
 *   together is how anyone would naturally write this - keeping the bug would
 *   mean a porter has to reproduce a desync on purpose. */
AiFlags g_ai = {
    0,   /* fix_mdflag  */
    0,   /* fix_dist    */
    1,   /* fix_checken */
    1,   /* fix_seek    */
    1,   /* fix_flank   */
    1,   /* fix_guard   */
    1    /* fix_setup   */
};

u8 g_ai_trace;

/* XB by-reference parameters the original leaves stale between calls. */
static s8  s_tx, s_ty;    /* TX, TY   - never initialised on entry     */
static u8  s_flag;        /* BFLAG    - shared across every piece      */
static s8  s_dir;         /* DIR      - only written when lflag hits 2 */
static s16 s_dist;        /* DIST     - never written at all, SPEC 8.2 */
static s8  s_mtx, s_mty;  /* FINDEN's MTX/MTY, stale when no target    */

void ai_reset(void)
{
    s_tx = s_ty = 0;
    s_flag = 0;
    s_dir = 0;
    s_dist = 0;
    s_mtx = s_mty = 0;
}

#ifdef HARNESS
long g_ai_count[AI_CNT_MAX];
#define CNT(i) (g_ai_count[i]++)

void ai_state_save(AiPersist *p)
{
    p->tx = s_tx; p->ty = s_ty; p->flag = s_flag; p->dir = s_dir;
    p->dist = s_dist; p->mtx = s_mtx; p->mty = s_mty;
}

void ai_state_load(const AiPersist *p)
{
    s_tx = p->tx; s_ty = p->ty; s_flag = p->flag; s_dir = p->dir;
    s_dist = p->dist; s_mtx = p->mtx; s_mty = p->mty;
}
#endif
#ifndef HARNESS
#define CNT(i) ((void)0)
#endif

/* ------------------------------------------------------------------ */
/* CHECKEN - is there a known superior enemy at (col,row)?            */
/* ------------------------------------------------------------------ */

u8 ai_check_enemy(GameState *g, s8 pv, s8 col, s8 row)
{
    s8 i;

    for (i = 0; i < NPIECES; i++) {
        if (!g->known[i]) {
            /* SPEC 8.3: the original tests this before the position check,
             * so any unknown moved piece anywhere vetoes every miner. */
            if (pv == R_MINER && g->emoved[i]) {
                if (!g_ai.fix_checken) return 1;
                if (g->play[i].col == col && g->play[i].row == row) return 1;
            }
            continue;
        }
        if (g->play[i].col != col || g->play[i].row != row) continue;
        if (g->play[i].value != R_BOMB && g->play[i].value > pv) return 1;
    }
    return 0;
}

/* The original writes the adjacency veto out four times, once per direction.
 * Collapsed here; the edge conditions are preserved exactly. */
static u8 veto_adjacent(GameState *g, s8 x, s8 y, s8 xh, s8 yh, s8 pv)
{
    s8 c1x = -1, c1y = -1, c2x = -1, c2y = -1, c3x = -1, c3y = -1;

    if (xh < x) {                       /* moving left  */
        if (xh > 0) { c1x = (s8)(xh - 1); c1y = y; }
        if (y  > 0) { c2x = xh; c2y = (s8)(y - 1); }
        if (y  < 9) { c3x = xh; c3y = (s8)(y + 1); }
    } else if (xh > x) {                /* moving right */
        if (xh < 9) { c1x = (s8)(xh + 1); c1y = y; }
        if (y  > 0) { c2x = xh; c2y = (s8)(y - 1); }
        if (y  < 9) { c3x = xh; c3y = (s8)(y + 1); }
    } else if (yh < y) {                /* moving up    */
        if (yh > 0) { c1x = x; c1y = (s8)(yh - 1); }
        if (x  > 0) { c2x = (s8)(x - 1); c2y = yh; }
        if (x  < 9) { c3x = (s8)(x + 1); c3y = yh; }
    } else {                            /* moving down  */
        if (yh < 9) { c1x = x; c1y = (s8)(yh + 1); }
        if (x  > 0) { c2x = (s8)(x - 1); c2y = yh; }
        if (x  < 9) { c3x = (s8)(x + 1); c3y = yh; }
    }

    if (c1x >= 0 && IS_PLAY(CELL(g, c1x, c1y)) && ai_check_enemy(g, pv, c1x, c1y)) return 1;
    if (c2x >= 0 && IS_PLAY(CELL(g, c2x, c2y)) && ai_check_enemy(g, pv, c2x, c2y)) return 1;
    if (c3x >= 0 && IS_PLAY(CELL(g, c3x, c3y)) && ai_check_enemy(g, pv, c3x, c3y)) return 1;
    return 0;
}

/* ------------------------------------------------------------------ */
/* FINDEN - direction toward the nearest eligible player piece        */
/* ------------------------------------------------------------------ */

void ai_find_nearest(GameState *g, s8 id, s8 *dx, s8 *dy)
{
    s8  ox = g->comp[id].col;
    s8  oy = g->comp[id].row;
    s8  pv = g->comp[id].value;
    s16 mindist = 9999;
    s8  i;

    *dx = 0;
    *dy = 0;

    for (i = 0; i < NPIECES; i++) {
        s16 d, ddx, ddy;
        if (g->play[i].value == R_DEAD) continue;
        if (g->known[i] &&
            (g->play[i].value > pv ||
             (pv != R_MINER && g->play[i].value == R_BOMB))) continue;
        if (g->emoved[i] && pv == R_MINER) continue;

        ddx = (s16)(ox - g->play[i].col);
        ddy = (s16)(oy - g->play[i].row);
        d = (s16)(ddx * ddx + ddy * ddy);
        if (d < mindist) {
            mindist = d;
            s_mtx = g->play[i].col;
            s_mty = g->play[i].row;
        }
    }

    /* SPEC 8.2: the original computes the distance here and then throws it
     * away, leaving GENMOVE's DIST at zero. */
    if (g_ai.fix_dist) s_dist = (mindist == 9999) ? 0 : mindist;

    if (s_mtx > ox) *dx =  1;
    if (s_mtx < ox) *dx = -1;
    if (s_mty > oy) *dy =  1;
    if (s_mty < oy) *dy = -1;
}

/* ------------------------------------------------------------------ */
/* GENMOVE                                                            */
/* ------------------------------------------------------------------ */

void ai_gen_move(GameState *g, s8 id, Move *m)
{
    s8  x  = g->comp[id].col;
    s8  y  = g->comp[id].row;
    s8  pv = g->comp[id].value;
    s16 maxscore = -1;
    s16 score;
    s8  lflag = 0, forward = 0, latflag = 0, sflag = 0;
    u8  hflag = 0, tflag = 0;
    s8  dx = 0, dy = 0;
    s8  seek_x, seek_y;
    s8  xh, yh;
    u8  c;

search_loop:
    if (g->pleft <= AI_SEEK_GATE) ai_find_nearest(g, id, &dx, &dy);

    for (yh = (s8)(y - 1); yh <= (s8)(y + 1); yh++) {
    for (xh = (s8)(x - 1); xh <= (s8)(x + 1); xh++) {

        score = -1;

        /* Centre square, diagonals and off-board are all skipped. Note the
         * centre has yh == y, so it sets sflag every single scan. */
        if ((yh == y && xh == x) || (xh != x && yh != y) || !ON_BOARD(xh, yh)) {
            if (yh == y) sflag = 1;
            goto move_to_next_square;
        }

        c = CELL(g, xh, yh);
        if (IS_LAKE(c) || IS_COMP(c)) {
            if (yh == y) sflag = 1;
            goto move_to_next_square;
        }

        if (g->guard_id == id || pv == R_SPY) goto keep_checking;
        if (veto_adjacent(g, x, y, xh, yh, pv)) {
            score = -1;
            goto next_square;       /* note: tflag deliberately not cleared */
        }

keep_checking:
        if (IS_PLAY(c)) goto found_enemy_piece;

        /* ---- empty destination ---- */
        if (g->guard_id == id && g->comp[id].col == g->gx && g->comp[id].row == g->gy) {
            score = -1;
            goto move_to_next_square;
        }
        if (g->guard_id == id) {
            if (g_ai.fix_guard) {
                /* SPEC 8.7: the original targets the post itself, which is
                 * illegal unless the post happens to be adjacent, and it
                 * repeats every turn. Accept this candidate square instead,
                 * but only if it gets the guard closer to home. The square is
                 * already known empty, on-board and not a lake. */
                s16 dnow = (s16)((x  > g->gx ? x  - g->gx : g->gx - x) +
                                 (y  > g->gy ? y  - g->gy : g->gy - y));
                s16 dnew = (s16)((xh > g->gx ? xh - g->gx : g->gx - xh) +
                                 (yh > g->gy ? yh - g->gy : g->gy - yh));
                if (dnew >= dnow) { score = -1; goto move_to_next_square; }
                s_tx = xh; s_ty = yh;
            } else {
                s_tx = g->gx; s_ty = g->gy;
            }
            s_flag = 0;
            maxscore = AI_GUARD_RETURN;
            CNT(AI_CNT_GUARD);
            goto done;
        }
        if (pv == R_SPY && !g->mdflag) goto move_to_next_square;

        if (yh > y) {
            if (forward == -1) forward = 2; else forward = 1;
            score = (s16)(pv + AI_FORWARD);
        }
        if (yh < y) {
            forward = -1;
            score = (s16)(pv + AI_BACKWARD);
        }
        if (xh < x) lflag = 1;
        if (xh > x && lflag == 1) {
            s_dir = (s8)(rng_range(10) + 1);
            lflag = 2;
            latflag = 2;
        } else if (xh > x) {
            lflag = -1;
        }
        if (xh != x) score = pv;
        if (forward == 1 && lflag != 0) {
            if (rng_range(10) + 1 <= 3) { score = -1; forward = 0; }
        }
        if (hflag) score = (s16)(pv + AI_FLEE_BONUS);

move_to_next_square:
        tflag = 0;
        goto next_square;

found_enemy_piece:
        {
            s8 ei  = CELL_IDX(c);
            s8 epv = g->play[ei].value;

            if (!g->known[ei] && g->guard_id == id) goto guard_attack;
            if (!g->known[ei]) goto unknown_enemy;
            if (g->guard_id != id) goto not_guard;
            if (epv > pv) {                       /* guard_stay */
                s_flag = 0;
                maxscore = -1;
                goto done;
            }
guard_attack:
            s_flag = 1;
            maxscore = AI_URGENT_HIT;
            s_tx = xh; s_ty = yh;
            hflag = 1;
            goto done;

not_guard:
            if (epv <= pv) {
                score = (s16)(pv + ((epv != R_MINER) ? AI_KILL_BONUS : AI_KILL_MINER));
                tflag = 1;
                goto next_square;
            }
            if (pv == R_SPY && epv == R_MARSHAL) {
                maxscore = AI_URGENT_HIT;
                s_flag = 1;
                s_tx = xh; s_ty = yh;
                hflag = 1;
                CNT(AI_CNT_SPY_MARSH);
                goto done;
            }
            if (pv == R_MINER && epv == R_BOMB) {
                score = AI_DEFUSE;
                CNT(AI_CNT_DEFUSE);
                tflag = 1;
                goto next_square;
            }
            if (g->moved[id] && epv > pv && epv < R_BOMB) {
                if (!hflag) { hflag = 1; CNT(AI_CNT_FLEE); goto search_loop; }
            }
            score = -1;
            tflag = 0;
            goto next_square;

unknown_enemy:
            if (pv != R_MINER) goto not_miner;
            if (g->emoved[ei]) {
                if (!hflag) { hflag = 1; CNT(AI_CNT_FLEE); goto search_loop; }
                score = -1;
                tflag = 0;
                goto next_square;
            }
not_miner:
            tflag = 1;
            if (pv == R_SPY && !g->mdflag) { score = -1; tflag = 0; goto next_square; }
            if (pv == R_SPY &&  g->mdflag) { score = AI_SPY_LOOSE; tflag = 1; goto next_square; }

            if (yh <= y) goto not_sideways;
            if (latflag == 2 || (lflag != 0 && sflag)) goto not_sideways;
            {
                /* SPEC 8.5: the original validates the flank target in no way
                 * at all - not bounds, not terrain, not occupancy. Measured
                 * over 2000 games: 1067 off-board, 973 onto a friendly piece,
                 * 329 into a lake. Off-board is just the loud variant.
                 *
                 * The draw happens first either way, so the RNG stream is
                 * identical whether the fix is on or off. */
                s8 att = (s8)(rng_range(10) + 1);
                s8 fx = 0;
                u8 has_target = 0;

                if (lflag == -1 && att <= 5)     { fx = (s8)(x - 1); has_target = 1; }
                else if (lflag >= 0 && att > 5)  { fx = (s8)(x + 1); has_target = 1; }

                if (g_ai.fix_flank && has_target) {
                    if (!ON_BOARD(fx, y)) goto not_sideways;
                    {
                        u8 fc = CELL(g, fx, y);
                        if (IS_LAKE(fc) || IS_COMP(fc)) goto not_sideways;
                    }
                }
                if (lflag == -1 && att <= 5) {
                    s_tx = (s8)(x - 1); s_ty = y; s_flag = 1;
                    maxscore = (s16)(pv + AI_FLANK_BONUS);
                    CNT(AI_CNT_FLANK);
                    goto done;
                }
                if (lflag >= 0 && att > 5) {
                    s_tx = (s8)(x + 1); s_ty = y; s_flag = 1;
                    maxscore = (s16)(pv + AI_FLANK_BONUS);
                    CNT(AI_CNT_FLANK);
                    goto done;
                }
            }
not_sideways:
            score = (s16)(pv + (g->emoved[ei] ? AI_MOVED_BONUS : AI_STILL_BONUS));
        }

next_square:
        if (score < -1) score = -1;
        if (score >= maxscore) {
            maxscore = score;
            s_tx = xh; s_ty = yh;
            s_flag = tflag;
            /* Harmless in practice: lflag is cleared at the end of this same
             * iteration, so this only ever fires on the lateral candidate,
             * where the row already matches. Measured: no effect. */
            if (lflag == 2 && s_dir <= 5) s_tx = (s8)(x - 1);
        }
        if (lflag == 2) lflag = 0;
    }
    }

    if (s_flag == 1 || g->pleft > AI_SEEK_GATE) goto done;

    /* SPEC 8.4: the original commits TX/TY here and only *then* tests whether
     * the score is good enough to adopt. When it is not, the move returned is
     * the seek square carrying some other candidate's score. Measured: 77820
     * times per 2000 games, about 39 a game - not an edge case.
     *
     * Fixed, the target is held aside and committed together with the score. */
    seek_x = x; seek_y = y;
    if      ((forward == 1 || forward == 2) && dy ==  1) { seek_y = (s8)(y + 1); }
    else if ((forward == -1 || forward == 2) && dy == -1) { seek_y = (s8)(y - 1); }
    else if ((lflag == 1 || latflag == 2) && dx == -1)    { seek_x = (s8)(x - 1); }
    else if ((lflag == -1 || latflag == 2) && dx ==  1)   { seek_x = (s8)(x + 1); }
    else goto done;

    if (!g_ai.fix_seek) { s_tx = seek_x; s_ty = seek_y; }   /* commit early */

    CNT(AI_CNT_SEEK);
    score = (s16)(AI_SEEK_BASE + pv - s_dist);
    if (score > maxscore) {
        maxscore = score;
        s_tx = seek_x; s_ty = seek_y;
        s_flag = 0;                 /* seeking always steps to an empty square */
    } else {
        CNT(AI_CNT_SEEK_DROP);
    }

done:
    m->score  = maxscore;
    m->col    = s_tx;
    m->row    = s_ty;
    m->attack = s_flag;
    m->urgent = hflag;
}

/* ------------------------------------------------------------------ */
/* SCOUTMOVE - forward ray, then left, then right                     */
/* ------------------------------------------------------------------ */

void ai_scout_move(GameState *g, s8 id, Move *m)
{
    s8  x = g->comp[id].col;
    s8  y = g->comp[id].row;
    s16 score = -1;
    s16 maxscore = -1;
    s8  n = 0;
    s8  xh = x, yh = y;
    s8  iv = 0, fv = 0, st = 0, sn = 0;
    s8  i;
    u8  c;

    s_flag = 0;

    for (yh = (s8)(y + 1); yh <= 9; yh++) {
        c = CELL(g, x, yh);
        if (IS_LAKE(c) || IS_COMP(c)) {
            if (yh == (s8)(y + 1)) { score = -1; goto stop_ray; }
            score = 5; yh--; goto stop_ray;
        }
        if (!IS_PLAY(c)) continue;

        for (i = 0; i < NPIECES; i++) {
            if (!g->known[i]) { score = 30; continue; }
            if (g->play[i].col == x && g->play[i].row == yh) { score = -1; goto stop_ray; }
        }
        s_flag = 1;
        goto stop_ray;
    }

stop_ray:
    if (score == -1) { iv = (s8)(x - 1); fv = 0; st = -1; sn = 1; goto horizontal_ray; }
    goto exit_scout;

horizontal_ray:
    n++;
    if (n == 3) goto exit_scout;

    for (xh = iv; (st < 0) ? (xh >= fv) : (xh <= fv); xh = (s8)(xh + st)) {
        if (xh < 0 || xh > 9) break;
        c = CELL(g, xh, y);
        if (IS_LAKE(c) || IS_COMP(c)) {
            if (xh == iv) { score = -1; goto stop_ray_1; }
            score = 5; xh = (s8)(xh + sn); goto stop_ray_1;
        }
        if (!IS_PLAY(c)) continue;

        for (i = 0; i < NPIECES; i++) {
            if (!g->known[i]) { score = 30; continue; }
            if (g->play[i].col == xh && g->play[i].row == y) { score = -1; goto stop_ray_1; }
        }
        s_flag = 1;
        goto stop_ray_1;
    }

stop_ray_1:
    if (score == -1) { iv = (s8)(x + 1); fv = 9; st = 1; sn = -1; goto horizontal_ray; }

exit_scout:
    if (score >= maxscore) {
        maxscore = score;
        if (n == 0) { s_tx = x;  s_ty = yh; }
        else        { s_tx = xh; s_ty = y;  }
    }

    m->score  = maxscore;
    m->col    = s_tx;
    m->row    = s_ty;
    m->attack = s_flag;
    m->urgent = 0;
}

/* ------------------------------------------------------------------ */
/* Top level - tie list and selection, SPEC 3.1                       */
/* ------------------------------------------------------------------ */

u8 ai_choose_move(GameState *g, s8 *from_id, Move *out)
{
    s8   slot_id[AI_TIE_SLOTS];
    Move slot_mv[AI_TIE_SLOTS];
    s16  bestscore = -1, nbscore = -1;
    s8   nbid = -1;
    Move nbmv;
    s8   n = 0, i, k, limit;
    Move m;

    for (i = 0; i < AI_TIE_SLOTS; i++) slot_id[i] = -1;
    nbmv.score = -1; nbmv.col = 0; nbmv.row = 0; nbmv.attack = 0; nbmv.urgent = 0;

    for (i = 0; i < NPIECES; i++) {
        s8 pv = g->comp[i].value;

        if (pv == R_DEAD || pv >= R_BOMB) continue;   /* bombs and the flag */

        if (pv == R_SCOUT) ai_scout_move(g, i, &m);
        else               ai_gen_move(g, i, &m);

        if (m.score == -1) continue;

#ifdef AI_TRACE
        if (g_ai_trace) {
            fprintf(stderr, "  piece %2d rank %2d at %c%d -> %c%d  score %3d%s%s\n",
                    i, pv, 'a' + g->comp[i].col, g->comp[i].row,
                    'a' + m.col, m.row, m.score,
                    m.attack ? " ATTACK" : "", m.urgent ? " URGENT" : "");
        }
#endif

        g->moved[i] = 1;

        if (m.urgent) {
            *from_id = i;
            *out = m;
            return 1;
        }

        if (m.score > bestscore) n = 0;
        if (m.score >= bestscore && n < AI_TIE_SLOTS) {
            bestscore = m.score;
            slot_id[n] = i;
            slot_mv[n] = m;
            n++;
        } else if (m.score < bestscore && m.score > nbscore) {
            nbscore = m.score;
            nbid = i;
            nbmv = m;
        }
    }

    if (bestscore == -1) return 0;      /* resign */

    limit = AI_TIE_SLOTS;
    if (nbscore > -1) {
        slot_id[AI_TIE_SLOTS - 1] = nbid;
        slot_mv[AI_TIE_SLOTS - 1] = nbmv;
        limit = AI_TIE_SLOTS - 1;
    }

    for (k = 0; k < limit; k++) {
        if (slot_id[k] < 0) { slot_id[k] = slot_id[0]; slot_mv[k] = slot_mv[0]; }
    }

    k = (s8)rng_range(AI_TIE_SLOTS);
    *from_id = slot_id[k];
    *out = slot_mv[k];
    return 1;
}
