/* api.ld - short upper-case aliases of the C core entry points.
 *
 * MACRO-11 symbols are RAD50: A-Z 0-9 $ . only, folded to upper case, and the
 * RT-11 OBJ format carries 6 characters.  C symbols (_game_setup_player_random)
 * fit none of that, so STRAT1.MAC calls the aliases below.  EXTERN() keeps the
 * target alive under --gc-sections (an alias alone is not a reference).
 */
EXTERN(_rng_seed _rng_next _rng_range _ai_reset _ai_choose_move
       _game_new _game_legal _game_apply _game_check_loss _game_count_alive
       _game_setup_computer _game_setup_player_random _game_rebuild_grid
       _g_state _g_ai _g_stack)

RNGSED = _rng_seed;
RNGNXT = _rng_next;
RNGRNG = _rng_range;
AIRST  = _ai_reset;
AICHMV = _ai_choose_move;
GMNEW  = _game_new;
GMLEGL = _game_legal;
GMAPLY = _game_apply;
GMCHLS = _game_check_loss;
GMCNTA = _game_count_alive;
GMSTCP = _game_setup_computer;
GMSTPL = _game_setup_player_random;
GMRBGR = _game_rebuild_grid;
GSTATE = _g_state;
GAI    = _g_ai;
GSTACK = _g_stack;
