/* Build-time check: uknc/STCORE.MAC offsets vs the real C layout. */
#include <stddef.h>
#include "stratego.h"
#include "ai.h"
#include "game.h"

#define CHK(name, off) _Static_assert(offsetof(GameState, name) == off, "GS_" #name)
CHK(comp, 0); CHK(play, 120); CHK(known, 240); CHK(emoved, 280); CHK(moved, 320);
CHK(grid, 360); CHK(pleft, 460); CHK(guard_id, 461); CHK(gx, 462); CHK(gy, 463);
CHK(mdflag, 464);
_Static_assert(sizeof(Piece) == 3, "PIECE_SIZE");
_Static_assert(offsetof(Move, score) == 0 && offsetof(Move, col) == 2 &&
               offsetof(Move, row) == 3 && offsetof(Move, attack) == 4 &&
               offsetof(Move, urgent) == 5, "MV_*");
_Static_assert(SIDE_COMP == 0 && SIDE_PLAY == 1, "SIDE_*");
_Static_assert(offsetof(Combat, fought) == 0 && offsetof(Combat, att_value) == 1 &&
               offsetof(Combat, def_value) == 2 && offsetof(Combat, result) == 5, "CB_FGT");
_Static_assert(BO_BOTH_DIE == 0 && BO_ATTACKER_WINS == 1 && BO_DEFENDER_WINS == 2, "BO_*");
_Static_assert(offsetof(Combat, flag_taken) == 6 && sizeof(Combat) <= 8, "CB_*");
