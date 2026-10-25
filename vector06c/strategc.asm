;----------------------------------------------------------------------------
; Command line and game flow
;
; Bottom of the screen: row 29 = prompt "> " + the typed keys + "_" cursor,
; row 30 = hints and questions. A move is four keys (no Enter): from column
; A-J, from row 0-9, to column, to row, e.g. E6E5. N = new game, R = resign
; (both ask Y/N), Backspace deletes the last key.
;----------------------------------------------------------------------------

ROW_PROMPT	EQU 29
ROW_HINT	EQU 30

	MACRO PUSHB addr		; push a byte variable as a 16-bit argument
	ld a,(addr)
	ld l,a
	ld h,0
	push hl
	ENDM

CmdBuf:		DS 4			; typed move: from col, from row, to col, to row
CmdLen:		DB 0

BlankRow:	DB "                                ",0	; 32 blanks
PromptStr:	DB "> ",0
HintFirst:	DB "Use A-J,N,R keys",0
HintCol:	DB "Column A-J",0
HintRow:	DB "Row 0-9",0
TxtIllegal:	DB "Illegal move",0
TxtNew:		DB "New game? Y/N",0
TxtResign:	DB "Resign? Y/N",0
TxtAnyKey:	DB "Press any key",0
TxtWin:		DB "YOU WIN!",0
TxtLost:	DB "YOU LOST",0
TxtResigned:	DB "RESIGNED",0
GameOverTab:	DW TxtLost,TxtWin,TxtResigned	; indexed by the GameOver code

; The game: a new game, then commands until the end of time
MainLoop:
	call GameStart
.ml_cmd:
	call ReadCommand
	or a
	jp z,.ml_move
	cp 'N'
	jp z,.ml_new
	ld hl,TxtResign		; R
	call Confirm
	or a
	jp z,.ml_cmd
	ld a,2
	call GameOver
	jp .ml_cmd
.ml_new:
	ld hl,TxtNew
	call Confirm
	or a
	jp z,.ml_cmd
	call GameStart
	jp .ml_cmd
.ml_move:
	call DoMove
	jp .ml_cmd

; Start a new game: set up, draw, the computer opens
; O: all registers destroyed
GameStart:
	call NewGame
	ld c,ROW_PROMPT
	call ClearRow
	call ClearHint
	call HistClear
	call DrawBoard
	call DrawStats
	jp ComputerReply

; Clear a text row
; I: C = row
; O: all registers destroyed
ClearRow:
	ld b,0
	call SetCursor
	ld hl,BlankRow
	jp PrintString

ClearHint:
	ld c,ROW_HINT
	jp ClearRow

; Show a message on the hint row
; I: HL = string
; O: all registers destroyed
ShowHint:
	push hl
	call ClearHint
	ld a,COL_WHITE
	call SetColor
	ld b,0
	ld c,ROW_HINT
	call SetCursor
	pop hl
	jp PrintString

; Ask a question on the hint row and wait for a key
; I: HL = question
; O: A = 1 if the answer is Y, else 0; other registers destroyed
Confirm:
	call ShowHint
	call GetKey
	push af
	call ClearHint
	pop af
	cp 'Y'
	ld a,0			; (does not change the flags)
	ret nz
	inc a
	ret

; Draw the prompt, the typed keys and the cursor
; O: all registers destroyed
DrawCmdLine:
	ld a,COL_BLUE
	call SetColor
	ld b,0
	ld c,ROW_PROMPT
	call SetCursor
	ld hl,PromptStr
	call PrintString
	ld a,(CmdLen)
	or a
	jp z,.dcl_cur
	ld b,a
	ld hl,CmdBuf
.dcl_key:
	push bc
	push hl
	ld a,(hl)
	call PrintChar
	pop hl
	pop bc
	inc hl
	dec b
	jp nz,.dcl_key
.dcl_cur:
	ld a,'_'
	call PrintChar
	ld a,(CmdLen)
	cpl
	add a,5			; 4 - length: blank the rest of the field
	ld b,a
	ret z
.dcl_blank:
	push bc
	ld a,' '
	call PrintChar
	pop bc
	dec b
	jp nz,.dcl_blank
	ret

; Read a command line
; O: A = 0 when a move has been typed (in CmdBuf), or 'N' / 'R' for a command;
;    all other registers destroyed
ReadCommand:
	xor a
	ld (CmdLen),a
.rc_loop:
	call DrawCmdLine
	call GetKey
	cp KEY_BS
	jp z,.rc_bs
	ld c,a			; C = key
	ld a,(CmdLen)
	ld b,a			; B = number of keys typed so far
	or a
	jp nz,.rc_class
	ld a,c			; the first key may also be a command
	cp 'N'
	jp z,.rc_cmd
	cp 'R'
	jp z,.rc_cmd
.rc_class:
	ld a,b
	and 1
	jp nz,.rc_digit
	ld a,c			; columns: A-J
	cp 'A'
	jp c,.rc_bad
	cp 'K'
	jp nc,.rc_bad
	jp .rc_ok
.rc_digit:
	ld a,c			; rows: 0-9
	cp '0'
	jp c,.rc_bad
	cp ':'
	jp nc,.rc_bad
.rc_ok:
	ld hl,CmdBuf
	ld e,b
	ld d,0
	add hl,de
	ld (hl),c
	ld a,b
	inc a
	ld (CmdLen),a
	call ClearHint
	ld a,(CmdLen)
	cp 4
	jp nz,.rc_loop
	call DrawCmdLine	; show the whole move
	xor a
	ret
.rc_bs:
	ld a,(CmdLen)
	or a
	jp z,.rc_loop
	dec a
	ld (CmdLen),a
	jp .rc_loop
.rc_bad:
	ld a,b			; a hint for what is expected here
	or a
	ld hl,HintFirst
	jp z,.rc_hint
	ld a,b
	and 1
	ld hl,HintCol
	jp z,.rc_hint
	ld hl,HintRow
.rc_hint:
	call ShowHint
	jp .rc_loop
.rc_cmd:
	ld a,c
	ret

; Play the typed move, then the computer's reply, then check for the end
; I: CmdBuf = four typed keys
; O: all registers destroyed
DoMove:
	call ClearHint
	ld a,(CmdBuf)
	sub 'A'
	ld (LmFc),a
	ld a,(CmdBuf+1)
	sub '0'
	ld (LmFr),a
	ld a,(CmdBuf+2)
	sub 'A'
	ld (LmTc),a
	ld a,(CmdBuf+3)
	sub '0'
	ld (LmTr),a
	ld hl,g_state
	push hl
	ld hl,SIDE_PLAY
	push hl
	PUSHB LmFc
	PUSHB LmFr
	PUSHB LmTc
	PUSHB LmTr
	call game_legal		; game_legal(&g_state, SIDE_PLAY, fc, fr, tc, tr) -> L
	ld a,l
	ld hl,12		; caller cleans 6 words
	add hl,sp
	ld sp,hl
	or a
	jp nz,.dm_ok
	ld hl,TxtIllegal
	jp ShowHint
.dm_ok:
	ld a,COL_BLUE
	ld (LmColor),a
	call AnimateMove
	ld hl,g_state
	push hl
	ld hl,SIDE_PLAY
	push hl
	PUSHB LmFc
	PUSHB LmFr
	PUSHB LmTc
	PUSHB LmTr
	ld hl,CombatBuf
	push hl
	call game_apply		; game_apply(&g_state, SIDE_PLAY, fc, fr, tc, tr, &ci)
	ld hl,14		; caller cleans 7 words
	add hl,sp
	ld sp,hl
	ld a,COL_BLUE
	ld (LmColor),a
	call AddHistory
	call RedrawMove
	ld a,(CombatBuf+CB_flag_taken)
	or a
	jp z,.dm_red
	ld a,1			; the player took the flag
	jp GameOver
.dm_red:
	ld hl,(RoundNo)
	inc hl
	ld (RoundNo),hl
	call DrawMoveNo
	jp ComputerReply

; The computer moves, then the end of the game is checked: the computer has
; no move (the player wins), the computer took the flag or the player cannot
; move (the player loses). Also used for the computer's opening move.
; O: all registers destroyed
ComputerReply:
	call ComputerTurn
	or a
	jp nz,.cr_moved
	ld a,1			; the computer cannot move: the player wins
	jp GameOver
.cr_moved:
	ld a,(CombatBuf+CB_flag_taken)
	or a
	jp z,.cr_blue
	xor a			; the computer took the flag
	jp GameOver
.cr_blue:
	call BlueHasMove
	or a
	ret nz
	xor a			; the player cannot move
	jp GameOver

; Does the player have a legal move? Tries the four neighbours of every live
; piece (a scout's longer moves start with a one-step move).
; O: A = 1 if so, else 0; other registers destroyed
BlueHasMove:
	xor a
	ld (BmI),a
.bh_piece:
	ld a,(BmI)
	ld e,a
	add a,a
	add a,e			; * sizeof(Piece)
	ld e,a
	ld d,0
	ld hl,g_state+GS_play
	add hl,de
	ld a,(hl)
	or a
	jp z,.bh_next		; dead
	inc hl
	ld a,(hl)
	ld (BmC),a
	inc hl
	ld a,(hl)
	ld (BmR),a
	xor a
	ld (BmD),a
.bh_dir:
	ld a,(BmD)
	add a,a
	ld e,a
	ld d,0
	ld hl,BmDirs
	add hl,de
	ld a,(BmC)
	add a,(hl)
	ld (BmTc),a
	inc hl
	ld a,(BmR)
	add a,(hl)
	ld (BmTr),a
	ld hl,g_state
	push hl
	ld hl,SIDE_PLAY
	push hl
	PUSHB BmC
	PUSHB BmR
	PUSHB BmTc
	PUSHB BmTr
	call game_legal
	ld a,l
	ld hl,12
	add hl,sp
	ld sp,hl
	or a
	jp nz,.bh_yes
	ld a,(BmD)
	inc a
	ld (BmD),a
	cp 4
	jp nz,.bh_dir
.bh_next:
	ld a,(BmI)
	inc a
	ld (BmI),a
	cp NPIECES
	jp nz,.bh_piece
	xor a
	ret
.bh_yes:
	ld a,1
	ret

BmDirs:		DB 0,-1, 0,1, -1,0, 1,0	; neighbour offsets (dc,dr)
BmI:		DB 0			; BlueHasMove scratch
BmD:		DB 0
BmC:		DB 0
BmR:		DB 0
BmTc:		DB 0
BmTr:		DB 0

; The game is over: show the whole board and the signs, wait for a key, start
; again. The result sign is at the left in the winner's color (blue also for
; a resignation), "GAME OVER" in white at the right.
; I: A = 1 the player won, 0 the player lost, 2 the player resigned
GameOver:
	push af
	ld a,1
	ld (RevealFlag),a
	call DrawBoard
	ld c,ROW_PROMPT
	call ClearRow
	pop af
	ld e,a
	ld d,0
	ld hl,GameOverColor
	add hl,de
	ld a,(hl)
	call SetColor
	ld a,e
	add a,a
	ld e,a
	ld hl,GameOverTab
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	push hl
	ld b,0
	ld c,ROW_PROMPT
	call SetCursor
	pop hl
	call PrintString
	ld a,COL_WHITE
	call SetColor
	ld b,STAT_COL
	ld c,ROW_PROMPT
	call SetCursor
	ld hl,TxtGameOver
	call PrintString
	ld hl,TxtAnyKey
	call ShowHint
	call GetKey
	jp GameStart

GameOverColor:	DB COL_RED,COL_BLUE,COL_BLUE	; indexed by the GameOver code
TxtGameOver:	DB "GAME OVER",0
