/* state.c - the one GameState instance, owned by the core.
 *
 * strateg1.asm never lays out this struct; it reads/writes the board through
 * the exported address g_state plus the GS_* field offsets in core.inc.
 */
#include "stratego.h"

GameState g_state;
