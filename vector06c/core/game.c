/* game.c - board rules, setup placement, combat resolution.
 *
 * Computer setup placement follows SPEC section 10, transcribed from the
 * original's place_computer_pieces. RNG draw counts are preserved even where
 * a draw is discarded, so a seed reproduces the original's layouts.
 */
#include "game.h"
#include "rng.h"
#include "ai.h"         /* g_ai: the defect switches of SPEC section 8 */

/* Setup-time occupancy for computer rows 0..3. The original's LOC(10,4). */
static u8 s_loc[BOARD_N][4];

static u8 loc_take(s8 col, s8 row)
{
    if (s_loc[col][row]) return 1;      /* occupied */
    s_loc[col][row] = 1;
    return 0;
}

static void piece_set(Piece *p, s8 value, s8 col, s8 row)
{
    p->value = value;
    p->col   = col;
    p->row   = row;
}

/* ------------------------------------------------------------------ */
/* Grid                                                               */
/* ------------------------------------------------------------------ */

void game_rebuild_grid(GameState *g)
{
    s16 i;
    s8  k;

    for (i = 0; i < NCELLS; i++) g->grid[i] = CELL_EMPTY;

    /* Two 2x2 lakes, columns 2-3 and 6-7, rows 4-5. */
    for (k = 4; k <= 5; k++) {
        CELL(g, 2, k) = CELL_LAKE;
        CELL(g, 3, k) = CELL_LAKE;
        CELL(g, 6, k) = CELL_LAKE;
        CELL(g, 7, k) = CELL_LAKE;
    }

    for (k = 0; k < NPIECES; k++) {
        if (g->comp[k].value != R_DEAD)
            CELL(g, g->comp[k].col, g->comp[k].row) = (u8)(CELL_COMP | (u8)k);
    }
    for (k = 0; k < NPIECES; k++) {
        if (g->play[k].value != R_DEAD)
            CELL(g, g->play[k].col, g->play[k].row) = (u8)(CELL_PLAY | (u8)k);
    }
}

/* ------------------------------------------------------------------ */
/* Computer setup - SPEC 10                                           */
/* ------------------------------------------------------------------ */

/* Each pattern places the flag and its bomb ring, reserves the guard post,
 * and reports how many bombs are left over for the final sweep. */
static void flag_left_corner(GameState *g, s8 *bleft)
{
    piece_set(&g->comp[0], R_FLAG, 0, 0);
    piece_set(&g->comp[1], R_BOMB, 0, 1);
    piece_set(&g->comp[2], R_BOMB, 1, 0);
    *bleft = 4;
    s_loc[0][0] = 1; s_loc[1][0] = 1; s_loc[0][1] = 1; s_loc[1][1] = 1;
    g->gx = 1; g->gy = 1;
}

static void flag_right_corner(GameState *g, s8 *bleft)
{
    piece_set(&g->comp[0], R_FLAG, 9, 0);
    piece_set(&g->comp[1], R_BOMB, 9, 1);
    piece_set(&g->comp[2], R_BOMB, 8, 0);
    *bleft = 4;
    s_loc[8][0] = 1; s_loc[9][0] = 1; s_loc[9][1] = 1; s_loc[8][1] = 1;
    g->gx = 8; g->gy = 1;
}

static void flag_back_row(GameState *g, s8 *bleft)
{
    s8 f = (s8)(rng_range(8) + 1);          /* column 1..8 */

    piece_set(&g->comp[0], R_FLAG, f, 0);
    piece_set(&g->comp[1], R_BOMB, (s8)(f - 1), 0);
    piece_set(&g->comp[2], R_BOMB, (s8)(f + 1), 0);
    piece_set(&g->comp[3], R_BOMB, f, 1);
    *bleft = 3;
    s_loc[f][0] = 1; s_loc[f - 1][0] = 1; s_loc[f + 1][0] = 1;
    s_loc[f][1] = 1; s_loc[f - 1][1] = 1;
    g->gx = (s8)(f - 1); g->gy = 1;
}

static void flag_second_row(GameState *g, s8 *bleft)
{
    s8 f = (s8)(rng_range(8) + 1);

    piece_set(&g->comp[0], R_FLAG, f, 1);
    piece_set(&g->comp[1], R_BOMB, f, 0);
    piece_set(&g->comp[2], R_BOMB, (s8)(f - 1), 1);
    piece_set(&g->comp[3], R_BOMB, f, 2);
    piece_set(&g->comp[4], R_BOMB, (s8)(f + 1), 1);
    *bleft = 2;
    s_loc[f][1] = 1; s_loc[f][0] = 1; s_loc[f - 1][1] = 1;
    s_loc[f][2] = 1; s_loc[f + 1][1] = 1; s_loc[f - 1][2] = 1;
    g->gx = (s8)(f - 1); g->gy = 2;
}

/* The original retries placement forever. Cap it and fall back to a linear
 * scan so the prototype cannot hang; in practice the cap is never reached. */
#define PLACE_TRIES 500

static s8 free_cell_fallback(s8 *col, s8 *row, s8 row_lo, s8 row_hi)
{
    s8 c, r;
    for (r = row_lo; r <= row_hi; r++) {
        for (c = 0; c < BOARD_N; c++) {
            if (!s_loc[c][r]) { s_loc[c][r] = 1; *col = c; *row = r; return 1; }
        }
    }
    return 0;
}

static void place_computer_pieces(GameState *g, s8 n, s8 bleft)
{
    s8  x, y, i;
    s16 t;                  /* must outrange PLACE_TRIES; an s8 never can */
    s8  nc = 4, nl = 4, nm = 5, nb = bleft;
    s8  gen_col;

    /* Marshal, row 2. SPEC 8.6: the original places these two without an
     * occupancy check, unlike every other piece. Row 3 happens to be empty at
     * this point so the General is safe, but the second-row flag pattern puts
     * a bomb and the guard post on row 2 - measured, 5.0% of setups stacked
     * the Marshal on one of them, leaving a live piece off the grid. */
    x = (s8)rng_range(10);
    if (g_ai.fix_setup) {
        for (t = 0; t < PLACE_TRIES; t++) {
            if (!loc_take(x, 2)) break;
            x = (s8)rng_range(10);
        }
    } else {
        s_loc[x][2] = 1;
    }
    piece_set(&g->comp[n], R_MARSHAL, x, 2);
    n++;

    /* General, row 3. */
    x = (s8)rng_range(10);
    if (g_ai.fix_setup) {
        for (t = 0; t < PLACE_TRIES; t++) {
            if (!loc_take(x, 3)) break;
            x = (s8)rng_range(10);
        }
    } else {
        s_loc[x][3] = 1;
    }
    piece_set(&g->comp[n], R_GENERAL, x, 3);
    n++;
    gen_col = x;

    /* Spy, row 2, in the general's column or one to either side. */
    for (t = 0; t < PLACE_TRIES; t++) {
        s8 off = (s8)((s8)rng_range(7) - 3);     /* char-unit offset -3..3 */
        s8 xs;
        if (off != 0 && off != -3 && off != 3) continue;  /* discarded draw */
        xs = (s8)(gen_col + off / 3);
        if (xs < 0 || xs > 9) continue;
        if (loc_take(xs, 2)) continue;
        piece_set(&g->comp[n], R_SPY, xs, 2);
        n++;
        break;
    }
    if (t == PLACE_TRIES) {
        if (free_cell_fallback(&x, &y, 0, 3)) { piece_set(&g->comp[n], R_SPY, x, y); n++; }
    }

    /* Colonels, row 2. */
    for (i = 0; i < 2; i++) {
        for (t = 0; t < PLACE_TRIES; t++) {
            x = (s8)rng_range(10);
            if (loc_take(x, 2)) continue;
            piece_set(&g->comp[n], R_COLONEL, x, 2);
            n++;
            break;
        }
        if (t == PLACE_TRIES && free_cell_fallback(&x, &y, 0, 3)) {
            piece_set(&g->comp[n], R_COLONEL, x, y); n++;
        }
    }

    /* Majors: one on row 3, one on row 1, one on the guard post. */
    for (t = 0; t < PLACE_TRIES; t++) {
        x = (s8)rng_range(10);
        if (loc_take(x, 3)) continue;
        piece_set(&g->comp[n], R_MAJOR, x, 3);
        n++;
        break;
    }
    for (t = 0; t < PLACE_TRIES; t++) {
        x = (s8)rng_range(10);
        if (loc_take(x, 1)) continue;
        piece_set(&g->comp[n], R_MAJOR, x, 1);
        n++;
        break;
    }
    piece_set(&g->comp[n], R_MAJOR, g->gx, g->gy);
    g->guard_id = n;
    n++;

    /* Scouts fill every free cell of row 3. */
    for (x = 0; x < BOARD_N; x++) {
        if (loc_take(x, 3)) continue;
        piece_set(&g->comp[n], R_SCOUT, x, 3);
        n++;
    }

    /* Sergeants: one below each flag-ring bomb where possible. */
    for (i = 1; i <= 4; i++) {
        if (g->comp[i].value == R_BOMB) {
            x = g->comp[i].col;
            y = (s8)(g->comp[i].row + 1);
            if (y <= 3 && !loc_take(x, y)) {
                piece_set(&g->comp[n], R_SERGEANT, x, y);
                n++;
                continue;
            }
        }
        for (t = 0; t < PLACE_TRIES; t++) {
            x = (s8)rng_range(10);
            y = (s8)rng_range(4);
            if (loc_take(x, y)) continue;
            piece_set(&g->comp[n], R_SERGEANT, x, y);
            n++;
            break;
        }
        if (t == PLACE_TRIES && free_cell_fallback(&x, &y, 0, 3)) {
            piece_set(&g->comp[n], R_SERGEANT, x, y); n++;
        }
    }

    /* Captains, lieutenants, miners and leftover bombs: sweep rows 2,1,0. */
    for (y = 2; y >= 0; y--) {
        for (x = 0; x < BOARD_N; x++) {
            s8 nt = 4;
            for (t = 0; t < PLACE_TRIES; t++) {
                nt = (s8)(rng_range(4) + 1);
                if ((nt == 1 && nc == 0) || (nt == 2 && nl == 0) ||
                    (nt == 3 && nm == 0) || (nt == 4 && nb == 0)) continue;
                break;
            }
            if (t == PLACE_TRIES) goto done;
            if (loc_take(x, y)) continue;
            if      (nt == 1) { piece_set(&g->comp[n], R_CAPTAIN,    x, y); nc--; }
            else if (nt == 2) { piece_set(&g->comp[n], R_LIEUTENANT, x, y); nl--; }
            else if (nt == 3) { piece_set(&g->comp[n], R_MINER,      x, y); nm--; }
            else              { piece_set(&g->comp[n], R_BOMB,       x, y); nb--; }
            n++;
            if (nc == 0 && nl == 0 && nm == 0 && nb == 0) goto done;
        }
    }
done:
    return;
}

void game_setup_computer(GameState *g)
{
    s8 bleft = 0, n, i, j;

    for (i = 0; i < BOARD_N; i++)
        for (j = 0; j < 4; j++) s_loc[i][j] = 0;

    for (i = 0; i < NPIECES; i++) piece_set(&g->comp[i], R_DEAD, 0, 0);

    switch (rng_range(4)) {
        case 0:  flag_left_corner(g, &bleft);  break;
        case 1:  flag_right_corner(g, &bleft); break;
        case 2:  flag_back_row(g, &bleft);     break;
        default: flag_second_row(g, &bleft);   break;
    }

    n = (s8)(7 - bleft);   /* first free record after flag + ring bombs */
    place_computer_pieces(g, n, bleft);
}

/* ------------------------------------------------------------------ */
/* Player setup - random for now                                      */
/* ------------------------------------------------------------------ */

static const s8 k_army[NPIECES] = {
    R_MARSHAL,
    R_GENERAL,
    R_COLONEL, R_COLONEL,
    R_MAJOR, R_MAJOR, R_MAJOR,
    R_CAPTAIN, R_CAPTAIN, R_CAPTAIN, R_CAPTAIN,
    R_LIEUTENANT, R_LIEUTENANT, R_LIEUTENANT, R_LIEUTENANT,
    R_SERGEANT, R_SERGEANT, R_SERGEANT, R_SERGEANT,
    R_MINER, R_MINER, R_MINER, R_MINER, R_MINER,
    R_SCOUT, R_SCOUT, R_SCOUT, R_SCOUT,
    R_SCOUT, R_SCOUT, R_SCOUT, R_SCOUT,
    R_SPY,
    R_BOMB, R_BOMB, R_BOMB, R_BOMB, R_BOMB, R_BOMB,
    R_FLAG
};

void game_setup_player_random(GameState *g)
{
    s8 cells[NPIECES];
    s8 i, k;

    for (i = 0; i < NPIECES; i++) cells[i] = i;      /* rows 6..9, 40 cells */

    for (i = (s8)(NPIECES - 1); i > 0; i--) {        /* Fisher-Yates */
        s8 j = (s8)rng_range((u8)(i + 1));
        s8 t = cells[i]; cells[i] = cells[j]; cells[j] = t;
    }

    for (i = 0; i < NPIECES; i++) {
        k = cells[i];
        piece_set(&g->play[i], k_army[i], (s8)(k % BOARD_N), (s8)(6 + k / BOARD_N));
    }
}

/* ------------------------------------------------------------------ */

void game_new(GameState *g, u16 seed)
{
    s8 i;

    rng_seed(seed);

    for (i = 0; i < NPIECES; i++) {
        g->known[i]  = 0;
        g->emoved[i] = 0;
        g->moved[i]  = 0;
    }
    g->pleft    = NPIECES;
    g->guard_id = -1;
    g->gx = g->gy = 0;
    g->mdflag = 0;

    game_setup_computer(g);
    game_setup_player_random(g);
    game_rebuild_grid(g);
}

/* ------------------------------------------------------------------ */
/* Legality                                                           */
/* ------------------------------------------------------------------ */

u8 game_legal(GameState *g, u8 side, s8 fc, s8 fr, s8 tc, s8 tr)
{
    u8  from, to;
    s8  pv, step, k;
    Piece *own;

    if (!ON_BOARD(fc, fr) || !ON_BOARD(tc, tr)) return 0;
    if (fc == tc && fr == tr) return 0;

    from = CELL(g, fc, fr);
    to   = CELL(g, tc, tr);

    if (side == SIDE_COMP) {
        if (!IS_COMP(from)) return 0;
        if (IS_COMP(to)) return 0;
        own = g->comp;
    } else {
        if (!IS_PLAY(from)) return 0;
        if (IS_PLAY(to)) return 0;
        own = g->play;
    }
    if (IS_LAKE(to)) return 0;

    pv = own[CELL_IDX(from)].value;
    if (pv < R_SPY || pv > R_MARSHAL) return 0;      /* bombs and flags */

    if (fc != tc && fr != tr) return 0;              /* no diagonals */

    if (pv != R_SCOUT) {
        s8 d = (s8)((fc == tc) ? (tr - fr) : (tc - fc));
        return (u8)(d == 1 || d == -1);
    }

    /* Scout: straight line, every intermediate cell open. */
    if (fc == tc) {
        step = (s8)((tr > fr) ? 1 : -1);
        for (k = (s8)(fr + step); k != tr; k = (s8)(k + step))
            if (!IS_OPEN(CELL(g, fc, k))) return 0;
    } else {
        step = (s8)((tc > fc) ? 1 : -1);
        for (k = (s8)(fc + step); k != tc; k = (s8)(k + step))
            if (!IS_OPEN(CELL(g, k, fr))) return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* Combat and move application                                        */
/* ------------------------------------------------------------------ */

static u8 combat_outcome(s8 apv, s8 dpv)
{
    if (dpv == R_BOMB && apv != R_MINER) return BO_DEFENDER_WINS;
    if (dpv == R_BOMB && apv == R_MINER) return BO_ATTACKER_WINS;
    if (dpv == apv)                      return BO_BOTH_DIE;
    if (apv > dpv || (apv == R_SPY && dpv == R_MARSHAL) || dpv == R_FLAG)
        return BO_ATTACKER_WINS;
    return BO_DEFENDER_WINS;
}

void game_apply(GameState *g, u8 side, s8 fc, s8 fr, s8 tc, s8 tr, Combat *ci)
{
    u8    from = CELL(g, fc, fr);
    u8    to   = CELL(g, tc, tr);
    s8    aid  = CELL_IDX(from);
    Piece *att = (side == SIDE_COMP) ? g->comp : g->play;
    Piece *def = (side == SIDE_COMP) ? g->play : g->comp;

    ci->fought     = 0;
    ci->flag_taken = 0;
    ci->result     = BO_ATTACKER_WINS;
    ci->att_value  = att[aid].value;
    ci->def_value  = R_DEAD;
    ci->att_id     = aid;
    ci->def_id     = -1;

    if (side == SIDE_PLAY) g->emoved[aid] = 1;

    if (IS_OPEN(to)) {
        CELL(g, fc, fr) = CELL_EMPTY;
        att[aid].col = tc;
        att[aid].row = tr;
        CELL(g, tc, tr) = from;
        return;
    }

    {
        s8 did = CELL_IDX(to);
        s8 apv = att[aid].value;
        s8 dpv = def[did].value;

        ci->fought    = 1;
        ci->def_value = dpv;
        ci->def_id    = did;
        ci->result    = combat_outcome(apv, dpv);

        /* Reveal, then clear the reveal if that piece died. SPEC 2.3. */
        if (side == SIDE_COMP) g->known[did] = 1;
        else                   g->known[aid] = 1;

        if (dpv == R_FLAG) ci->flag_taken = 1;

        /* SPEC 8.1: the original tests the rank *after* zeroing it, so it can
         * never fire and the Spy stays frozen all game. Test it here, before
         * the pieces below are removed. mdflag means "the player's Marshal is
         * dead", which is what makes the Spy expendable. */
        if (g_ai.fix_mdflag) {
            if (side == SIDE_COMP && dpv == R_MARSHAL &&
                (ci->result == BO_ATTACKER_WINS || ci->result == BO_BOTH_DIE))
                g->mdflag = 1;
            if (side == SIDE_PLAY && apv == R_MARSHAL &&
                (ci->result == BO_DEFENDER_WINS || ci->result == BO_BOTH_DIE))
                g->mdflag = 1;
        }

        CELL(g, fc, fr) = CELL_EMPTY;

        if (ci->result == BO_ATTACKER_WINS) {
            def[did].value  = R_DEAD;
            att[aid].col    = tc;
            att[aid].row    = tr;
            CELL(g, tc, tr) = from;
            if (side == SIDE_COMP) { g->pleft--; g->known[did] = 0; }
        } else if (ci->result == BO_DEFENDER_WINS) {
            att[aid].value  = R_DEAD;
            CELL(g, tc, tr) = to;
            if (side == SIDE_PLAY) { g->pleft--; g->known[aid] = 0; }
        } else {
            att[aid].value  = R_DEAD;
            def[did].value  = R_DEAD;
            CELL(g, tc, tr) = CELL_EMPTY;
            g->pleft--;
            if (side == SIDE_COMP) g->known[did] = 0;
            else                   g->known[aid] = 0;
        }
    }
}

u8 game_check_loss(GameState *g, u8 side)
{
    const Piece *p = (side == SIDE_COMP) ? g->comp : g->play;
    s8 i;

    for (i = 0; i < NPIECES; i++)
        if (p[i].value >= R_SPY && p[i].value <= R_MARSHAL) return 0;
    return 1;
}

s8 game_count_alive(GameState *g, u8 side)
{
    const Piece *p = (side == SIDE_COMP) ? g->comp : g->play;
    s8 i, n = 0;

    for (i = 0; i < NPIECES; i++)
        if (p[i].value != R_DEAD) n++;
    return n;
}
