;
;   Minimal z88dk crt0 for the Stratego game core, built as a callable blob
;   that strateg1.asm (sjasmplus) links against by address.
;
;   No interrupt setup, no palette, no heap, no _main loop - strateg0.asm
;   already owns all of that. The core exports plain C functions; the build
;   turns the link map into core.inc for the asm side.
;

    module  core_crt0

    defc    crt0 = 1
    INCLUDE "zcc_opt.def"

    PUBLIC  __Exit
    PUBLIC  l_dcal

    EXTERN  _rng_seed
    EXTERN  _game_new
    EXTERN  _ai_reset
    EXTERN  _ai_choose_move
    EXTERN  _game_legal
    EXTERN  _game_apply
    EXTERN  _game_check_loss
    EXTERN  _game_count_alive
    EXTERN  _game_setup_computer
    EXTERN  _game_setup_player_random
    EXTERN  _game_rebuild_grid

    defc    TAR__register_sp = 0            ; core never sets SP; caller owns it
    defc    TAR__crt_on_exit = 0x10001
    defc    __CPU_CLOCK = 3000000

    INCLUDE "crt/classic/crt_rules.inc"

    ; Single knob for the core's load/run address. strateg1 UI lives below
    ; this (01EFh..CRT_ORG_CODE-1); the core must end below A000h (screen).
    ; Raise or lower once strateg1's real size is known.
    defc    CRT_ORG_CODE = 0x4000
    org     CRT_ORG_CODE

;   Jump table - stable entry point at CORE_ORG regardless of link order.
;   strateg1.asm may call these fixed slots instead of the C symbols.
core_vectors:
    jp      _rng_seed
    jp      _game_new
    jp      _ai_reset
    jp      _ai_choose_move
    jp      _game_legal
    jp      _game_apply
    jp      _game_check_loss
    jp      _game_count_alive
    jp      _game_setup_computer
    jp      _game_setup_player_random
    jp      _game_rebuild_grid

_main:
    ret

__Exit:
    ret

l_dcal:
    jp      (hl)                ; function-pointer calls

;   Console I/O stubs. The core does no I/O; these only satisfy the runtime
;   selection glue that crt_runtime_selection.inc always references.
    PUBLIC  fputc_cons_native
    PUBLIC  fgetc_cons
fputc_cons_native:
fgetc_cons:
    ret

    INCLUDE "crt/classic/crt_runtime_selection.inc"
