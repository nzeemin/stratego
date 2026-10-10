/* stratego.h - shared types and constants.
 *
 * Discipline for later 8/16-bit ports:
 *   - no int, no long, no float anywhere outside main.c
 *   - all state static, no malloc
 *   - flat arrays with manual indexing
 *   - s16 is assumed to be the natural machine word
 */
#ifndef STRATEGO_H
#define STRATEGO_H

#include <stdint.h>

typedef int8_t   s8;
typedef uint8_t  u8;
typedef int16_t  s16;
typedef uint16_t u16;

#define BOARD_N  10
#define NCELLS   100
#define NPIECES  40

/* Ranks. Higher wins, except spy-vs-marshal and miner-vs-bomb. */
#define R_DEAD        0
#define R_SPY         1
#define R_SCOUT       2
#define R_MINER       3
#define R_SERGEANT    4
#define R_LIEUTENANT  5
#define R_CAPTAIN     6
#define R_MAJOR       7
#define R_COLONEL     8
#define R_GENERAL     9
#define R_MARSHAL    10
#define R_BOMB       11
#define R_FLAG       12

#define SIDE_COMP 0
#define SIDE_PLAY 1

/* Grid cell encoding. Replaces the original's CALL GCHAR screen reads.
 * Piece index fits in 6 bits (0..39). */
#define CELL_EMPTY 0x00
#define CELL_LAKE  0x01
#define CELL_COMP  0x40
#define CELL_PLAY  0x80
#define CELL_MASK  0xC0

#define CELL_IDX(c) ((s8)((c) & 0x3F))
#define IS_COMP(c)  (((c) & CELL_MASK) == CELL_COMP)
#define IS_PLAY(c)  (((c) & CELL_MASK) == CELL_PLAY)
#define IS_LAKE(c)  ((c) == CELL_LAKE)
#define IS_OPEN(c)  ((c) == CELL_EMPTY)

typedef struct {
    s8 value;   /* rank, R_DEAD when removed from play */
    s8 col;     /* 0..9 */
    s8 row;     /* 0..9, row 0 = computer back rank */
} Piece;

typedef struct {
    Piece comp[NPIECES];
    Piece play[NPIECES];
    u8    known[NPIECES];   /* player piece revealed in combat            */
    u8    emoved[NPIECES];  /* player piece has moved -> not bomb or flag */
    u8    moved[NPIECES];   /* computer piece evaluated at least once     */
    u8    grid[NCELLS];
    s8    pleft;            /* surviving player pieces, gates seeking     */
    s8    guard_id;         /* computer major assigned to guard the flag  */
    s8    gx, gy;           /* its post                                   */
    u8    mdflag;           /* player marshal dead - see SPEC 8.1         */
} GameState;

#define CELL(g,c,r)   ((g)->grid[(s16)(r) * BOARD_N + (s16)(c)])
#define ON_BOARD(c,r) ((c) >= 0 && (c) < BOARD_N && (r) >= 0 && (r) < BOARD_N)

#endif
