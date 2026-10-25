;----------------------------------------------------------------------------

	INCLUDE "strateg0.inc"
	INCLUDE "core/core.inc"

;----------------------------------------------------------------------------

	OUTPUT "strateg1.bin"
	ORG	STRATCOD1_START

	CALL ShowIntro
	CALL ClearScreen
	CALL PrepareBoard
	CALL DrawField
	CALL DrawLakes
	CALL DrawRulers
	JP MainLoop

;----------------------------------------------------------------------------
; Game start
;----------------------------------------------------------------------------

; Colors = palette indexes made from the planes E000h (bit 0) and C000h (bit 1)
BOARD_N	EQU 10
NPIECES		EQU 40
CELL_LAKE	EQU 1

COL_BLACK	EQU 0
COL_BLUE	EQU 1			; plane E000h only (palette index bit 0)
COL_RED		EQU 2			; plane C000h only (palette index bit 1)
COL_WHITE	EQU 3			; both planes
; The plane at A000h is index bit 2 (palette 4..7): never drawn on.

RndSeed:	DW 1234h		; seed of the next game
RevealFlag:	DB 0			; non-zero: the board shows the computer's ranks

; Set up a new game: both armies and the grid are made by the core.
; O: all registers destroyed
NewGame:
	ld hl,g_state
	push hl
	ld hl,(RndSeed)
	push hl
	call game_new		; game_new(&g_state, seed)
	pop bc			; caller cleans the stack
	pop bc
	call ai_reset
	xor a
	ld (RevealFlag),a
	inc a
	ld (RoundNo),a		; round 1
	dec a
	ld (RoundNo+1),a
	ret

;----------------------------------------------------------------------------
; Keyboard. KEYINT (strateg0.asm) keeps the matrix rows in KeyLine0..KeyLine7
; (bit = 0: key pressed; row 1 is not scanned).
;----------------------------------------------------------------------------

KEY_BS		EQU 08h			; Backspace (ZAB)
KEY_TAB		EQU 09h
KEY_LF		EQU 0Ah			; PS
KEY_CR		EQU 0Dh			; Enter (VK)

KeyHeld:	DB 0			; key code that has been returned and is still down
KeyPrev:	DB 0			; key code seen in the previous frame

; Wait for a new key press and return its code. A key counts when it is seen
; in two frames in a row and was not the key still held from the last call,
; so there is no auto-repeat. Every frame of waiting advances RndSeed.
; Enables interrupts (the matrix is scanned by KEYINT).
; O: A = key code (see KeyTable); all other registers destroyed
GetKey:
	ei
.gk_wait:
	halt			; one frame
	ld hl,(RndSeed)
	inc hl
	ld (RndSeed),hl
	call ScanKey
	or a
	jp nz,.gk_key
	ld (KeyHeld),a		; nothing pressed: forget the held key
	ld (KeyPrev),a
	jp .gk_wait
.gk_key:
	ld hl,KeyHeld
	cp (hl)
	jp z,.gk_wait		; still the key we have already returned
	ld hl,KeyPrev
	cp (hl)
	jp z,.gk_got		; stable for two frames
	ld (hl),a
	jp .gk_wait
.gk_got:
	ld (KeyHeld),a
	ret

; Code of the first pressed key in the matrix (lowest row, lowest bit)
; O: A = key code, 0 if none; all other registers destroyed
ScanKey:
	ld de,KeyLine0
	ld hl,KeyTable
	ld b,8			; rows
.sk_row:
	ld a,(de)
	cpl			; 1 = pressed
	ld c,8			; bits
.sk_bit:
	rra
	jp nc,.sk_next
	push af
	ld a,(hl)
	or a
	jp nz,.sk_hit
	pop af
.sk_next:
	inc hl
	dec c
	jp nz,.sk_bit
	inc de
	dec b
	jp nz,.sk_row
	xor a
	ret
.sk_hit:
	pop de			; drop the saved bits
	ret

; Key codes by matrix position: row * 8 + bit (bit 0 first), 0 = no key.
; Letters are upper case ASCII whatever the RUS/LAT state.
KeyTable:
	DB KEY_TAB,KEY_LF,KEY_CR,KEY_BS,0,0,0,0	; row 0: the four arrow keys are not mapped
	DB 0,0,0,0,0,0,0,0			; row 1: not scanned
	DB "01234567"				; row 2
	DB "89:;,=./"				; row 3
	DB "@ABCDEFG"				; row 4
	DB "HIJKLMNO"				; row 5
	DB "PQRSTUVW"				; row 6
	DB "XYZ[",5Ch,"]^ "			; row 7 (5Ch = backslash)

	INCLUDE "strategc.asm"
	INCLUDE "strategi.asm"

;----------------------------------------------------------------------------
; Computer (RED) move
;----------------------------------------------------------------------------

FromId:		DB 0			; ai_choose_move: index of the moving piece
MoveBuf:	DS MV_SIZE		; ai_choose_move: the chosen move
CombatBuf:	DS CB_SIZE		; game_apply: the result of the move

; The computer makes its move, then the board and the statistics are redrawn.
; O: A = 0 if the computer has no move (resigns), else 1; other registers destroyed
ComputerTurn:
	call CompMove
	or a
	ret z
	call RedrawMove
	ld a,1
	ret

; Choose the computer's move with the AI and apply it to g_state
; O: A = 0 if the computer has no move, else 1; other registers destroyed
CompMove:
	ld hl,g_state
	push hl
	ld hl,FromId
	push hl
	ld hl,MoveBuf
	push hl
	call ai_choose_move	; ai_choose_move(&g_state, &from_id, &move) -> L, 0 = resign
	pop bc
	pop bc
	pop bc
	ld a,l
	or a
	ret z
	ld a,(FromId)		; HL = &g_state.comp[from_id]
	ld e,a
	add a,a
	add a,e			; * sizeof(Piece)
	ld e,a
	ld d,0
	ld hl,g_state+GS_comp+PIECE_col
	add hl,de
	ld c,(hl)		; from column
	inc hl
	ld b,(hl)		; from row
	ld a,c			; remember the move for AddHistory
	ld (LmFc),a
	ld a,b
	ld (LmFr),a
	ld a,(MoveBuf+MV_col)
	ld (LmTc),a
	ld a,(MoveBuf+MV_row)
	ld (LmTr),a
	ld a,COL_RED
	ld (LmColor),a
	call AnimateMove
	ld hl,g_state
	push hl
	ld hl,SIDE_COMP
	push hl
	ld a,(LmFc)		; AnimateMove destroyed the registers: from LmFc.. again
	ld l,a
	ld h,0
	push hl			; fc
	ld a,(LmFr)
	ld l,a
	push hl			; fr (H is still 0)
	ld a,(LmTc)
	ld l,a
	push hl			; tc
	ld a,(LmTr)
	ld l,a
	push hl			; tr
	ld hl,CombatBuf
	push hl
	call game_apply		; game_apply(&g_state, SIDE_COMP, fc, fr, tc, tr, &ci)
	ld hl,14		; caller cleans 7 words
	add hl,sp
	ld sp,hl
	call AddHistory
	ld a,1
	ret

;----------------------------------------------------------------------------
; Move history, right of the board under the statistics: the last HIST_N moves,
; oldest on top, two rows each, in the mover's color:
;   E6E3 2>7	the move and the mover's rank; for an attack also ">" + defender's rank
;          lost	only for an attack: the outcome for the mover, right aligned
; A record is made of LmFc..LmColor (the move) and CombatBuf (game_apply's
; result) by AddHistory, which the move routines call right after game_apply.
;----------------------------------------------------------------------------

HIST_N		EQU 6
HIST_ROW0	EQU 17			; first text row of the history
HE_SIZE		EQU 9			; record: color (0 = empty), from col/row, to col/row,
					; mover rank, fought, defender rank, result

LmFc:		DB 0			; the move just made: from column/row, to column/row,
LmFr:		DB 0
LmTc:		DB 0
LmTr:		DB 0
LmColor:	DB 0			; color of the mover

Hist:		DS HIST_N*HE_SIZE	; oldest first
RecBuf:					; the record being drawn
RecColor:	DB 0
RecFc:		DB 0
RecFr:		DB 0
RecTc:		DB 0
RecTr:		DB 0
RecRank:	DB 0
RecFought:	DB 0
RecDef:		DB 0
RecResult:	DB 0
HRow:		DB 0			; DrawHistory scratch
HCount:		DB 0

BlankMsg:	DB "          ",0	; 10 characters
ResultTab:	DW ResTie,ResWon,ResLost	; indexed by Combat.result (BO_*)
ResTie:		DB "       tie",0	; padded to 10 characters: right aligned
ResWon:		DB "       won",0
ResLost:	DB "      lost",0

; Forget all moves (a new game)
; O: all registers destroyed
HistClear:
	ld hl,Hist
	ld b,HIST_N*HE_SIZE
	xor a
.hc_l:	ld (hl),a
	inc hl
	dec b
	jp nz,.hc_l
	ret

; Append the move just made; the oldest record falls out
; O: all registers destroyed
AddHistory:
	ld hl,Hist+HE_SIZE
	ld de,Hist
	ld b,(HIST_N-1)*HE_SIZE
.ah_l:	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	dec b
	jp nz,.ah_l
	ld a,(LmColor)		; DE = the last record
	ld (de),a
	inc de
	ld a,(LmFc)
	ld (de),a
	inc de
	ld a,(LmFr)
	ld (de),a
	inc de
	ld a,(LmTc)
	ld (de),a
	inc de
	ld a,(LmTr)
	ld (de),a
	inc de
	ld a,(CombatBuf+CB_att_value)
	ld (de),a
	inc de
	ld a,(CombatBuf+CB_fought)
	ld (de),a
	inc de
	ld a,(CombatBuf+CB_def_value)
	ld (de),a
	inc de
	ld a,(CombatBuf+CB_result)
	ld (de),a
	ret

; Draw all the records
; O: all registers destroyed
DrawHistory:
	ld hl,Hist
	ld a,HIST_ROW0
	ld (HRow),a
	ld a,HIST_N
	ld (HCount),a
.dh_l:	push hl
	call PrintRecord
	ld hl,HRow
	inc (hl)
	inc (hl)
	pop hl
	ld de,HE_SIZE
	add hl,de
	ld a,(HCount)
	dec a
	ld (HCount),a
	jp nz,.dh_l
	ret

; Draw one record on rows HRow, HRow+1 (blank rows for an empty record)
; I: HL = record
; O: all registers destroyed
PrintRecord:
	ld de,RecBuf
	ld b,HE_SIZE
.pr_c:	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	dec b
	jp nz,.pr_c
	ld a,(HRow)
	ld c,a
	ld b,STAT_COL
	call SetCursor
	ld hl,BlankMsg
	call PrintString
	ld a,(HRow)
	inc a
	ld c,a
	ld b,STAT_COL
	call SetCursor
	ld hl,BlankMsg
	call PrintString
	ld a,(RecColor)
	or a
	ret z			; empty record
	call SetColor
	ld a,(HRow)
	ld c,a
	ld b,STAT_COL
	call SetCursor
	ld a,(RecFc)
	add a,'A'
	call PrintChar
	ld a,(RecFr)
	add a,'0'
	call PrintChar
	ld a,(RecTc)
	add a,'A'
	call PrintChar
	ld a,(RecTr)
	add a,'0'
	call PrintChar
	ld a,' '
	call PrintChar
	ld a,(RecRank)
	call RankChar
	call PrintChar
	ld a,(RecFought)
	or a
	ret z
	ld a,'>'
	call PrintChar
	ld a,(RecDef)
	call RankChar
	call PrintChar
	ld a,(HRow)		; the outcome, right aligned on the next row
	inc a
	ld c,a
	ld b,STAT_COL
	call SetCursor
	ld a,(RecResult)
	add a,a
	ld e,a
	ld d,0
	ld hl,ResultTab
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	jp PrintString

;----------------------------------------------------------------------------
; Board output. Cell (c,r): c = 0..9 left to right, r = 0..9 top to bottom
; (row 0 = computer back rank). Each piece is a 16x16 face (strategp.asm) in
; the 16x20 cell: player pieces blue, computer pieces red. A computer piece
; is a plain red block (DrawBlock) until RevealFlag is set.
;----------------------------------------------------------------------------

; Draw all 100 cells from g_state.grid
; O: all registers destroyed
DrawBoard:
	ld hl,g_state+GS_grid
	ld c,0			; row
.db_row:
	ld b,0			; column
.db_col:
	ld a,(hl)
	inc hl
	push hl
	push bc
	call DrawCell
	pop bc
	pop hl
	inc b
	ld a,b
	cp BOARD_N
	jp nz,.db_col
	inc c
	ld a,c
	cp BOARD_N
	jp nz,.db_row
	ret

; Move animation: a bar in the mover's color grows 1 px per frame from 2 px
; inside the source cell, across its edge, to 4 px inside the target cell (a
; scout's bar runs over every cell in between). The grid line pixels are
; skipped. Horizontal bars are 5 rows thick, vertical bars 4 px wide, centered
; in the cell. Call it before game_apply: the move is in LmFc..LmTr, the color
; in LmColor. RedrawMove erases the bar afterwards by redrawing the cells.
; O: all registers destroyed
AnimateMove:
	ld a,(LmColor)
	call SetColor
	ld a,(LmFc)
	ld b,a
	ld a,(LmTc)
	sub b
	jp z,.am_vert
	ld c,a			; C = tc - fc
	ld a,1
	ld (AnHoriz),a
	ld a,(LmFr)
	call RowTop
	sub 11			; 5 rows around the middle of the cell
	ld (AnBase),a
	ld a,c
	or a
	jp m,.am_left
	ld a,(LmFc)		; right: from X = 16 fc + 22 to 16 tc + 12
	call Mul16
	add a,22
	ld (AnPos),a
	ld b,a
	ld a,(LmTc)
	call Mul16
	add a,12
	sub b
	inc a
	ld (AnCount),a
	ld a,1
	jp .am_step
.am_left:
	ld a,(LmFc)		; left: from X = 16 fc + 10 down to 16 tc + 20
	call Mul16
	add a,10
	ld (AnPos),a
	ld b,a
	ld a,(LmTc)
	call Mul16
	add a,20
	ld c,a
	ld a,b
	sub c
	inc a
	ld (AnCount),a
	ld a,0FFh
	jp .am_step
.am_vert:
	xor a
	ld (AnHoriz),a
	ld a,(LmFc)
	add a,a
	add a,0A1h		; the xbyte of the left half of the 4 px wide bar
	ld (AnBase),a
	ld a,(LmFr)
	ld b,a
	ld a,(LmTr)
	sub b
	ret z			; no move
	jp m,.am_up
	ld a,(LmFr)		; down: from y = top(fr) - 17 down to top(tr) - 3
	call RowTop
	sub 17
	ld (AnPos),a
	ld b,a
	ld a,(LmTr)
	call RowTop
	sub 3
	ld c,a
	ld a,b
	sub c
	inc a
	ld (AnCount),a
	ld a,0FFh
	jp .am_step
.am_up:
	ld a,(LmFr)		; up: from y = top(fr) - 1 up to top(tr) - 15
	call RowTop
	dec a
	ld (AnPos),a
	ld b,a
	ld a,(LmTr)
	call RowTop
	sub 15
	sub b
	inc a
	ld (AnCount),a
	ld a,1
.am_step:
	ld (AnStep),a
	ei
.am_loop:
	call DrawBarPixel
	ld a,(AnPos)
	ld hl,AnStep
	add a,(hl)
	ld (AnPos),a
	halt			; one pixel per frame
	ld a,(AnCount)
	dec a
	ld (AnCount),a
	jp nz,.am_loop
	ld b,ANIM_HOLD		; hold the finished bar so the move can be followed
.am_hold:
	halt
	dec b
	jp nz,.am_hold
	ret

ANIM_HOLD	EQU 38			; frames (50 per second)

AnHoriz:	DB 0			; 1: the bar moves along x
AnPos:		DB 0			; its current position along the move: X pixel
				; (board x + 8) or screen y
AnStep:		DB 0			; +1 / -1
AnCount:	DB 0			; pixels left
AnBase:		DB 0			; horizontal: lowest y of the bar; vertical: hi byte
				; of the left xbyte (A000h plane address)
AnMask:		DB 0

; A = row 0..9 -> A = y of the cell's top row
; O: A; DE, HL destroyed
RowTop:
	ld e,a
	ld d,0
	ld hl,BoardRowY
	add hl,de
	ld a,(hl)
	ret

; A = A * 16
Mul16:
	add a,a
	add a,a
	add a,a
	add a,a
	ret

; Draw the cross-section of the bar at AnPos (nothing on a grid line)
; O: A, BC, DE destroyed
DrawBarPixel:
	ld a,(AnHoriz)
	or a
	jp z,.dbp_vert
	ld a,(AnPos)
	and 15
	cp 8			; X = 8 + 16 k is a vertical grid line
	ret z
	ld a,(AnPos)
	and 7
	ld b,a
	ld c,80h
.dbp_sh:
	ld a,b
	or a
	jp z,.dbp_m
	ld a,c
	rrca
	ld c,a
	dec b
	jp .dbp_sh
.dbp_m:
	ld a,c
	ld (AnMask),a
	ld a,(AnPos)
	rrca
	rrca
	rrca
	and 1Fh
	add a,0A0h
	ld d,a			; the xbyte
	ld a,(AnBase)
	ld e,a
	ld b,5
.dbp_row:
	push bc
	ld a,(AnMask)
	call PutByteT
	pop bc
	inc e
	dec b
	jp nz,.dbp_row
	ret
.dbp_vert:
	ld a,(AnPos)
	sub 47			; y = 47 + 20 k is a horizontal grid line
.dbp_mod:
	cp 20
	jp c,.dbp_chk
	sub 20
	jp .dbp_mod
.dbp_chk:
	or a
	ret z
	ld a,(AnBase)
	ld d,a
	ld a,(AnPos)
	ld e,a
	ld a,03h		; x offsets 6, 7 of the cell
	call PutByteT
	inc d
	ld a,0C0h		; x offsets 8, 9
	jp PutByteT

; Draw a cell from the grid
; I: B = column, C = row
; O: all registers destroyed
DrawCellAt:
	ld a,c
	add a,a
	ld e,a			; 2 * row
	add a,a
	add a,a			; 8 * row
	add a,e			; 10 * row
	add a,b
	ld e,a
	ld d,0
	ld hl,g_state+GS_grid
	add hl,de
	ld a,(hl)
	jp DrawCell

RmC:	DB 0			; RedrawMove scratch: the cell being drawn, the step
RmR:	DB 0
RmDc:	DB 0
RmDr:	DB 0

; A = signed byte -> A = -1, 0 or 1
Sign:
	or a
	ret z
	ld a,1
	ret p
	ld a,0FFh
	ret

; Draw what a move changed: the cells from the from-cell to the to-cell, the piece counts after
; a battle, and the history. The move is in LmFc..LmTr, the combat in CombatBuf.
; O: all registers destroyed
RedrawMove:
	ld a,(LmFc)		; the cells along the way, the from-cell and the
	ld (RmC),a		; to-cell included (a scout passes over several)
	ld a,(LmFr)
	ld (RmR),a
	ld a,(LmTc)
	ld hl,LmFc
	sub (hl)
	call Sign
	ld (RmDc),a
	ld a,(LmTr)
	ld hl,LmFr
	sub (hl)
	call Sign
	ld (RmDr),a
.rm_cell:
	ld a,(RmC)
	ld b,a
	ld a,(RmR)
	ld c,a
	call DrawCellAt
	ld a,(RmC)
	ld hl,LmTc
	cp (hl)
	jp nz,.rm_next
	ld a,(RmR)
	ld hl,LmTr
	cp (hl)
	jp z,.rm_done
.rm_next:
	ld a,(RmC)
	ld hl,RmDc
	add a,(hl)
	ld (RmC),a
	ld a,(RmR)
	ld hl,RmDr
	add a,(hl)
	ld (RmR),a
	jp .rm_cell
.rm_done:
	ld a,(CombatBuf+CB_fought)
	or a
	call nz,DrawCounts
	jp DrawHistory

; Draw one cell: the field background first, then the piece or the closed
; piece block on top of it (only the set pixels replace the background)
; I: A = grid cell value, B = column, C = row
; O: all registers destroyed
DrawCell:
	cp CELL_LAKE
	ret z			; lakes never change
	push af
	call RestoreCell	; HL = the cell's top row
	pop af
	or a
	ret z			; empty cell
	dec l			; the face / block starts one row lower
	push hl			; screen address
	ld c,a			; C = cell value
	and 3Fh
	ld e,a
	add a,a
	add a,e			; 3 * piece index
	ld e,a
	ld d,0
	ld a,c
	and 80h
	jp z,.dc_comp
	ld hl,g_state+GS_play	; player piece, always shown
	add hl,de
	ld a,(hl)		; rank
	push af
	ld a,c
	and 3Fh
	ld e,a
	ld d,0
	ld hl,g_state+GS_known
	add hl,de
	ld a,(hl)
	ld (MarkFlag),a		; non-zero: the computer knows this piece
	pop af
	ld b,COL_BLUE
	jp .dc_draw
.dc_comp:
	xor a
	ld (MarkFlag),a
	ld hl,g_state+GS_comp
	add hl,de
	ld a,(RevealFlag)
	or a
	jp z,.dc_hidden
	ld b,COL_RED
	ld a,(hl)
.dc_draw:			; A = rank, B = color
	push af
	ld a,b
	call SetColor
	pop af
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl		; rank * 32
	ld de,PieceGfx-32	; faces start at rank 1
	add hl,de
	ex de,hl		; DE = face data
	pop hl			; screen address
	call DrawFace
	ld a,(MarkFlag)
	or a
	ret z
	ld a,l			; exposed marker: a 12 px line under the face,
	sub 16			; 2 px margin each side (x = 2..13)
	ld l,a
	ld d,h
	ld e,l
	ld hl,MarkGfx
	push de
	ld b,1
	call PutColumnT
	pop de
	inc d
	ld b,1
	jp PutColumnT
.dc_hidden:			; closed computer piece: red block
	ld a,COL_RED
	call SetColor
	pop hl
	jp DrawBlock

; Screen address of a cell's top row (the first row between the grid lines)
; I: B = column, C = row
; O: HL = address; A, DE destroyed
CellAddr:
	ld a,c
	ld e,a
	ld d,0
	ld hl,BoardRowY
	add hl,de
	ld a,(hl)
	ld e,a			; E = y of the cell's top row
	ld a,b
	add a,a			; 2 xbytes per cell
	add a,0A1h		; board starts at xbyte 1
	ld h,a
	ld l,e
	ret

; Y of the cell's top row for each board row: cell bottom line + 19, the cell
; has 19 free rows between the grid lines; cell bottom line = 47 + (9 - r) * 20.
; Faces and the closed-piece block start one row lower (1 spare row above the
; 16-row face, 2 below).
BoardRowY:
	DB 246,226,206,186,166,146,126,106,86,66

; Put the field background on the screen. Palette indexes: bit 2 (plane A000h)
; set = field colors 4..7, the 2-bit color k = bit 1 (plane C000h), bit 0
; (plane E000h). The grid mask that PrepareBoard drew on plane A000h turns into
; white (A000h = 0, C000h = E000h = 1) over the field. The lines outside the
; picture (top and right edge) are white on black.
; O: all registers destroyed
DrawField:
	ld hl,(0A1h<<8)+246	; xbyte 1, row 0 of the picture = y 246
	ld bc,FieldImage	; C000h plane
	ld de,FieldImage+FIELD_PLANE	; E000h plane
	ld a,20
	ld (FldCols),a
.df_col:
	ld a,200
	ld (FldRows),a
.df_row:
	ld a,(hl)		; the grid mask: 1 = line pixel
	ld (FldMask),a
	cpl
	ld (hl),a		; A000h plane: field, except under the lines
	ld a,h
	add a,20h
	ld h,a			; plane C000h
	ld a,(bc)
	inc bc
	ld (hl),a
	ld a,(FldMask)
	or (hl)
	ld (hl),a
	ld a,h
	add a,20h
	ld h,a			; plane E000h
	ld a,(de)
	inc de
	ld (hl),a
	ld a,(FldMask)
	or (hl)
	ld (hl),a
	ld a,h
	sub 40h
	ld h,a			; back to A000h
	dec l
	ld a,(FldRows)
	dec a
	ld (FldRows),a
	jp nz,.df_row
	ld l,246
	inc h			; next xbyte
	ld a,(FldCols)
	dec a
	ld (FldCols),a
	jp nz,.df_col
	ld h,0B5h		; the right line, xbyte 21: y = 47..247
	ld l,47
.df_right:
	call WhiteMask
	inc l
	ld a,l
	cp 248
	jp nz,.df_right
	ld h,0A1h		; the top line, y = 247: xbytes 1..20
	ld l,247
.df_top:
	call WhiteMask
	inc h
	ld a,h
	cp 0B5h
	jp nz,.df_top
	ret

FldCols:	DB 0
FldRows:	DB 0
FldMask:	DB 0

; Turn the grid mask byte into white pixels on black
; I: HL = address on plane A000h
; O: HL preserved; A, C destroyed
WhiteMask:
	ld c,(hl)
	ld (hl),0
	ld a,h
	add a,20h
	ld h,a
	ld (hl),c
	add a,20h
	ld h,a
	ld (hl),c
	sub 40h
	ld h,a
	ret

; Draw a 16x16 piece face in the current color: the set pixels replace the
; screen, the clear ones leave it as it is
; I: HL = screen address of the face's top row (the cell's top row - 1)
; I: DE = face data, 32 bytes: left column top->bottom, right column
; O: HL preserved; A, BC, DE destroyed
DrawFace:
	push hl
	ex de,hl		; HL = data, DE = screen
	push de
	ld b,16
	call PutColumnT
	pop de
	inc d			; right xbyte
	ld b,16
	call PutColumnT
	pop hl
	ret

; Draw the closed-piece block: 11x18 in the current color, 3 px left margin
; (x = 3..13 of the cell, rows face top .. face top - 17)
; I: HL = screen address of the face's top row (the cell's top row - 1)
; O: HL preserved; A, BC, DE destroyed
DrawBlock:
	push hl
	ld d,h
	ld e,l
	ld hl,BlockGfx
	push de
	ld b,18
	call PutColumnT
	pop de
	inc d			; right xbyte
	ld b,18
	call PutColumnT
	pop hl
	ret

MarkGfx:
	DB 3Fh,0FCh		; left xbyte: x = 2..7, right xbyte: x = 8..13
MarkFlag:
	DB 0			; DrawCell scratch

BlockGfx:
	DUP 18
	DB 1Fh			; left xbyte: x = 3..7
	EDUP
	DUP 18
	DB 0FCh			; right xbyte: x = 8..13
	EDUP

; Put a 32x40 1-bit bitmap (2x2 cells) in the current color: the set pixels
; replace the screen, the clear ones leave it as it is (so the grid lines stay).
; I: HL = screen address of the top row of the left xbyte (A000h plane address),
;    DE = data: four xbyte columns left to right, each 40 bytes from the top row down
; O: all registers destroyed
PutBitmap2x2:
	ex de,hl		; HL = data, DE = screen
	ld a,4
	ld (BmpCol),a
.pbm_col:
	push de
	ld a,40
	ld (BmpRow),a
.pbm_row:
	ld a,(hl)
	inc hl
	call PutByteT
	dec e			; next row down
	ld a,(BmpRow)
	dec a
	ld (BmpRow),a
	jp nz,.pbm_row
	pop de
	inc d			; next xbyte
	ld a,(BmpCol)
	dec a
	ld (BmpCol),a
	jp nz,.pbm_col
	ret

BmpCol:	DB 0
BmpRow:	DB 0

; The two lakes (c4-d5 and g4-h5) in the blue plane. The bitmaps start one
; line above the cell face area: field.png row 80 = screen y 166.
LAKE_Y		EQU 166

DrawLakes:
	ld a,COL_BLUE
	call SetColor
	ld hl,(0A5h<<8)+LAKE_Y	; xbyte 5 = column 2
	ld de,Lake1Gfx
	call PutBitmap2x2
	ld hl,(0ADh<<8)+LAKE_Y	; xbyte 13 = column 6
	ld de,Lake2Gfx
	jp PutBitmap2x2

; Row numbers 0..9 left of the board, column letters A..J below it
; O: all registers destroyed
DrawRulers:
	ld a,COL_WHITE
	call SetColor
	ld b,0
.dr_row:
	push bc
	ld a,b
	ld e,a
	ld d,0
	ld hl,BoardRowY
	add hl,de
	ld a,(hl)
	sub 5			; cell top -> digit top (centered in the cell)
	ld l,a
	ld h,0A0h		; xbyte 0
	ld a,b
	add a,'0'
	call PutChar
	pop bc
	inc b
	ld a,b
	cp BOARD_N
	jp nz,.dr_row
	ld b,0
.dr_col:
	push bc
	ld a,b
	add a,a
	add a,0A1h
	ld h,a
	ld l,46			; just below the bottom grid line (y = 47)
	ld a,b
	add a,'A'
	call PutCharMid
	pop bc
	inc b
	ld a,b
	cp BOARD_N
	jp nz,.dr_col
	ret

; Restore a cell's background: the field image, with the grid's dotted left edge.
; The cell's top row is y = BoardRowY; the picture rows are 20 * row .. + 18 of
; the xbytes 2 * column and 2 * column + 1.
; I: B = column, C = row
; O: HL = the cell's top row (as CellAddr); all other registers destroyed
RestoreCell:
	call CellAddr
	push hl
	ld hl,FieldImage	; the C000h plane source: + 400 * column + 20 * row
	ld de,400
	ld a,b
	or a
	jp z,.rs_c0
.rs_cl:	add hl,de
	dec a
	jp nz,.rs_cl
.rs_c0:	ld de,20
	ld a,c
	or a
	jp z,.rs_r0
.rs_rl:	add hl,de
	dec a
	jp nz,.rs_rl
.rs_r0:	ld b,h
	ld c,l			; BC = C000h plane source
	ld hl,FIELD_PLANE
	add hl,bc
	ex de,hl		; DE = E000h plane source
	pop hl			; HL = screen
	push hl
	ld a,2			; two xbytes
	ld (RsCols),a
.rs_col:
	push hl
	ld a,19
	ld (RsRows),a
.rs_row:
	ld (hl),0FFh		; plane A000h: the field shows
	ld a,h
	add a,20h
	ld h,a
	ld a,(bc)
	inc bc
	ld (hl),a		; plane C000h
	ld a,h
	add a,20h
	ld h,a
	ld a,(de)
	inc de
	ld (hl),a		; plane E000h
	ld a,h
	sub 40h
	ld h,a
	dec l
	ld a,(RsRows)
	dec a
	ld (RsRows),a
	jp nz,.rs_row
	pop hl
	inc h			; next xbyte
	push hl
	ld hl,200-19		; the next column of the picture
	add hl,bc
	ld b,h
	ld c,l
	ld hl,200-19
	add hl,de
	ex de,hl
	pop hl
	ld a,(RsCols)
	dec a
	ld (RsCols),a
	jp nz,.rs_col
	pop hl
	jp DotEdge

RsCols:	DB 0
RsRows:	DB 0

; Redraw the dotted left edge of the cell over its 19 rows (white pixels)
; I: HL = the cell's top row
; O: HL preserved; A, B destroyed
DotEdge:
	push hl
	ld a,h
	add a,40h
	ld h,a			; the grid lives on plane E000h
	ld b,19
.de_row:
	ld a,l
	and 3
	cp 3			; the line is on y = 47 + 4k, i.e. y mod 4 = 3
	jp nz,.de_skip
	ld a,(hl)
	or 80h
	ld (hl),a
	ld a,h
	sub 20h
	ld h,a			; plane C000h
	ld a,(hl)
	or 80h
	ld (hl),a
	ld a,h
	sub 20h
	ld h,a			; plane A000h: the field does not show
	ld a,(hl)
	and 7Fh
	ld (hl),a
	ld a,h
	add a,40h
	ld h,a
.de_skip:
	dec l
	dec b
	jp nz,.de_row
	pop hl
	ret

; Rank to character
; I: A = rank (0..12)
; O: A = character; DE, HL destroyed
RankChar:
	ld e,a
	ld d,0
	ld hl,RankChars
	add hl,de
	ld a,(hl)
	ret

RankChars:
	DB "?S23456789MBF"	; R_DEAD, spy, 2..9, marshal, bomb, flag

; Set the text color
; I: A = color 0..3 (COL_*)
; O: A destroyed
SetColor:
	push bc
	ld c,a
	and 1
	jp z,.sc_p0
	ld a,0FFh
.sc_p0:	ld (ColP0),a
	ld a,c
	and 2
	jp z,.sc_p1
	ld a,0FFh
.sc_p1:	ld (ColP1),a
	pop bc
	ret

ColP0:	DB 0FFh			; glyph mask for E000h (blue) / C000h (red)
ColP1:	DB 0FFh

;----------------------------------------------------------------------------
; Statistics panel, right of the board (text columns 22..31, rows 1..15):
; surviving pieces per rank for the computer (red) and the player (blue).
;
;           RED BLU	row 1
;   M        1   1	rows 2..13: M 9 8 7 6 5 4 3 2 S B F
;   ...
;           40  40	row 14 (totals)
;----------------------------------------------------------------------------

STAT_COL	EQU 22
STAT_ROW0	EQU 2			; first rank row
STAT_ROWS	EQU 12
STAT_TOTROW	EQU 14

PanelRanks:
	DB 10,9,8,7,6,5,4,3,2,1,11,12	; marshal .. spy, bomb, flag

StatMove:	DB "MOVE ",0
RoundNo:	DW 1			; number of the current round (the computer opens it)
PdFlag:		DB 0			; PrintDec16: a digit has been printed

StatHdrRed:	DB "RED",0
StatHdrBlue:	DB "BLU",0

StatPtr:	DW 0			; DrawStats scratch
StatRow:	DB 0
StatRank:	DB 0
StatTotR:	DB 0
StatTotB:	DB 0

; Draw the whole panel
; O: all registers destroyed
DrawStats:
	call DrawCounts
	jp DrawMoveNo

; The piece counts: the rank rows and the totals
; O: all registers destroyed
DrawCounts:
	xor a
	ld (StatTotR),a
	ld (StatTotB),a
	ld a,COL_RED
	call SetColor
	ld b,STAT_COL+2
	ld c,1
	call SetCursor
	ld hl,StatHdrRed
	call PrintString
	ld a,COL_BLUE
	call SetColor
	ld b,STAT_COL+6
	ld c,1
	call SetCursor
	ld hl,StatHdrBlue
	call PrintString
	ld hl,PanelRanks
	ld (StatPtr),hl
	ld a,STAT_ROW0
	ld (StatRow),a
.ds_row:
	ld hl,(StatPtr)
	ld a,(hl)
	ld (StatRank),a
	ld a,COL_WHITE
	call SetColor
	ld a,(StatRow)
	ld c,a
	ld b,STAT_COL
	call SetCursor
	ld a,(StatRank)
	call RankChar
	call PrintChar
	ld a,COL_RED
	call SetColor
	ld a,(StatRow)
	ld c,a
	ld b,STAT_COL+3
	call SetCursor
	ld hl,g_state+GS_comp
	ld a,(StatRank)
	call CountRank
	ld c,a
	ld hl,StatTotR
	add a,(hl)
	ld (hl),a
	ld a,c
	call PrintDec2
	ld a,COL_BLUE
	call SetColor
	ld a,(StatRow)
	ld c,a
	ld b,STAT_COL+7
	call SetCursor
	ld hl,g_state+GS_play
	ld a,(StatRank)
	call CountRank
	ld c,a
	ld hl,StatTotB
	add a,(hl)
	ld (hl),a
	ld a,c
	call PrintDec2
	ld hl,(StatPtr)
	inc hl
	ld (StatPtr),hl
	ld a,(StatRow)
	inc a
	ld (StatRow),a
	cp STAT_ROW0+STAT_ROWS
	jp nz,.ds_row
	; totals
	ld a,COL_RED
	call SetColor
	ld b,STAT_COL+3
	ld c,STAT_TOTROW
	call SetCursor
	ld a,(StatTotR)
	call PrintDec2
	ld a,COL_BLUE
	call SetColor
	ld b,STAT_COL+7
	ld c,STAT_TOTROW
	call SetCursor
	ld a,(StatTotB)
	jp PrintDec2

; "MOVE n" under the totals
; O: all registers destroyed
DrawMoveNo:
	ld a,COL_WHITE
	call SetColor
	ld b,STAT_COL
	ld c,STAT_TOTROW+1
	call SetCursor
	ld hl,StatMove
	call PrintString
	ld hl,(RoundNo)
	jp PrintDec16

; Print a 16-bit number in decimal, no leading zeros, left aligned
; I: HL = number
; O: all registers destroyed
PrintDec16:
	xor a
	ld (PdFlag),a
	ld de,10000
	call PdDigit
	ld de,1000
	call PdDigit
	ld de,100
	call PdDigit
	ld de,10
	call PdDigit
	ld a,l			; units are always printed
	add a,'0'
	jp PrintChar

; Print one decimal digit of HL for the divisor DE, leaving the remainder in HL
PdDigit:
	ld c,0
.pdd_l:	ld a,l
	sub e
	ld a,h
	sbc a,d
	jp c,.pdd_d		; HL < DE
	ld a,l
	sub e
	ld l,a
	ld a,h
	sbc a,d
	ld h,a
	inc c
	jp .pdd_l
.pdd_d:	ld a,c
	or a
	jp nz,.pdd_p
	ld a,(PdFlag)		; a leading zero is skipped
	or a
	ret z
.pdd_p:	ld a,1
	ld (PdFlag),a
	ld a,c
	add a,'0'
	push hl
	call PrintChar
	pop hl
	ret

; Number of pieces of a rank
; I: HL = Piece[40] array (g_state+GS_comp or +GS_play), A = rank
; O: A = count; BC, D, HL destroyed
CountRank:
	ld c,a
	ld b,NPIECES
	ld d,0
.cr_l:	ld a,(hl)
	cp c
	jp nz,.cr_n
	inc d
.cr_n:	inc hl
	inc hl
	inc hl			; sizeof(Piece)
	dec b
	jp nz,.cr_l
	ld a,d
	ret

; Print a number 0..99 in two characters, right aligned
; I: A = number
; O: all registers destroyed
PrintDec2:
	ld b,0			; tens
.pd_t:	cp 10
	jp c,.pd_u
	sub 10
	inc b
	jp .pd_t
.pd_u:	push af
	ld a,b
	or a
	ld a,' '		; no leading zero
	jp z,.pd_p
	ld a,b
	add a,'0'
.pd_p:	call PrintChar
	pop af
	add a,'0'
	jp PrintChar

; Set the text output position
; I: B = column 0..31, C = row 0..31
; O: A destroyed
SetCursor:
	ld a,b
	ld (CurCol),a
	ld a,c
	ld (CurRow),a
	ret


;----------------------------------------------------------------------------

; Clear the whole screen
ClearScreen:
	ld hl,$A000
	ld bc,$6000
	xor a
.l10:	ld (hl),a
	inc hl
	dec c
	jp nz,.l10
	dec b
	jp nz,.l10
	ret

; Text output position: 32 columns x 32 rows of 8x8 cells, (0,0) = top-left
CurCol:	DB 0
CurRow:	DB 0

; Print a character at the current position and advance it. At the end of
; the line the column wraps to 0 and the row advances (row wraps 31 -> 0).
; I: A = character code, $20..$7F; 0Dh = new line, 01h..03h = set the color
; O: A, BC, DE, HL destroyed
PrintChar:
	cp 20h
	jp nc,.pch_char
	cp 0Dh
	jp z,.pch_nl
	jp SetColor		; 01h..03h: text color (COL_*)
.pch_nl:
	xor a			; 0Dh: new line
	ld (CurCol),a
	ld a,(CurRow)
	inc a
	and 1Fh
	ld (CurRow),a
	ret
.pch_char:
	push af
	call CalcScreenAddr
	pop af
	call PutChar
	ld a,(CurCol)
	inc a
	cp 32
	jp nz,.pch_col
	ld a,(CurRow)
	inc a
	and 1Fh
	ld (CurRow),a
	xor a
.pch_col:
	ld (CurCol),a
	ret

; Print a zero-terminated string at the current position
; I: HL = string address
; O: A, BC, DE, HL destroyed
PrintString:
	ld a,(hl)
	or a
	ret z
	inc hl
	push hl
	call PrintChar
	pop hl
	jp PrintString

; Screen address of the current text position (top row of the cell)
;   H = 0A0h + col, L = 255 - row*8
; O: HL = screen address; A destroyed
CalcScreenAddr:
	ld a,(CurRow)
	add a,a
	add a,a
	add a,a			; row*8
	cpl			; 255 - row*8
	ld l,a
	ld a,(CurCol)
	add a,0A0h
	ld h,a
	ret

; Put an 8x8 character in the current color (overwrites the 8 pixel rows
; on planes 0 and 1).
; I: HL = screen address of the glyph's top row (A000h + xbyte*256 + y)
; I: A = character code, $20..$7F
; O: HL preserved; A, BC, DE destroyed
PutChar:
	sub $20
	push hl
	ld d,h
	ld e,l			; DE = screen address
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl		; *8
	ld bc,FONT
	add hl,bc		; HL = glyph data
	ld b,8			; 8 rows
	call PutColumn
	pop hl
	ret

; Put a column of bytes in the current color: one xbyte, B rows downward
; I: HL = data (top row first), DE = screen address of the top row (A000h plane
;    address), B = number of rows
; O: HL = after the data, DE = address of the row below the last, A, BC destroyed
PutColumn:
.pc_row:
	ld a,(hl)
	inc hl
	call PutByte
	dec e			; next row down (y decreases)
	dec b
	jp nz,.pc_row
	ret

; Like PutColumn, but transparent: only the set pixels are drawn (see PutByteT)
; I: HL = data, DE = screen address of the top row, B = number of rows
; O: HL = after the data, DE = address of the row below the last, A, BC destroyed
PutColumnT:
	ld a,b
	ld (TRows),a
.pt_row:
	ld a,(hl)
	inc hl
	call PutByteT
	dec e			; next row down
	ld a,(TRows)
	dec a
	ld (TRows),a
	jp nz,.pt_row
	ret

TRows:	DB 0

; Put one screen byte in the current color, transparent: the set pixels get the
; color (and the field is cleared under them), the clear pixels stay as they are
; I: A = pixels, DE = screen address (A000h plane address)
; O: DE preserved; A, BC destroyed
PutByteT:
	ld c,a
	ld a,(de)		; plane A000h
	or c
	xor c
	ld (de),a
	ld a,(ColP0)
	and c
	ld b,a
	ld a,d
	add a,40h
	ld d,a			; plane E000h
	ld a,(de)
	or c
	xor c
	or b
	ld (de),a
	ld a,(ColP1)
	and c
	ld b,a
	ld a,d
	sub 20h
	ld d,a			; plane C000h
	ld a,(de)
	or c
	xor c
	or b
	ld (de),a
	ld a,d
	sub 20h
	ld d,a			; back to A000h
	ret

; Put one screen byte in the current color
; I: A = pixels, DE = screen address (A000h plane address)
; O: DE preserved; A, C destroyed. The pixels become opaque: the bits that are
; clear are black and the field is cleared under the set ones.
PutByte:
	ld c,a
	ld a,(de)		; plane A000h: no field under the pixels
	or c
	xor c
	ld (de),a
	ld a,d
	add a,40h
	ld d,a			; plane E000h
	ld a,(ColP0)
	and c
	ld (de),a
	ld a,d
	sub 20h
	ld d,a			; plane C000h
	ld a,(ColP1)
	and c
	ld (de),a
	ld a,d
	sub 20h
	ld d,a			; back to A000h
	ret

; Put an 8x8 character centered in a 16 px wide cell (shifted right by 4 px)
; I: HL = screen address of the cell's left xbyte, top row; A = character
; O: HL preserved; A, BC, DE destroyed
PutCharMid:
	sub $20
	push hl
	ld d,h
	ld e,l
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	ld bc,FONT
	add hl,bc
	ld b,8
.pm_row:
	push bc
	ld a,(hl)
	inc hl
	ld b,a
	rrca
	rrca
	rrca
	rrca
	and 0Fh			; left xbyte: high nibble moves down
	call PutByte
	inc d
	ld a,b
	rlca
	rlca
	rlca
	rlca
	and 0F0h		; right xbyte: low nibble moves up
	call PutByte
	dec d
	dec e
	pop bc
	dec b
	jp nz,.pm_row
	pop hl
	ret

;----------------------------------------------------------------------------
; PrepareBoard - draw the 10x10 cell grid: 11 vertical + 11 horizontal
; dotted lines ("ants"), then punch out the interior of the two lakes. The lines
; are only a mask here: they are drawn on plane A000h, which is empty at this
; point, and DrawField turns the mask into white pixels over the field.
; Bits OR'd in.
;
; addr = 0A000h + plane*2000h + xbyte*256 + y, y = 0 is the bottom line.
; Board is 160x200 px, 8 px margin from the top-left, cells 16x20 px:
;   x pixels 8..168        -> xbyte 1..21, line pixel is always bit7 (80h)
;   y pixels (from bottom)  -> 47..247
;
; Lakes: cells c4 c5 d4 d5 and g4 g5 h4 h5. The grid line *between* the two
; cells of each lake is erased; the lake perimeter stays.
;----------------------------------------------------------------------------
PrepareBoard:
; ---- 11 vertical dotted lines ----
	ld h,0A1h		; xbyte 1  (hi byte = 0A0h + xbyte)
.pb_vcol:
	ld l,47			; y = board bottom edge
.pb_vrow:
	ld a,(hl)
	or 80h			; bit7 = leftmost pixel of the byte
	ld (hl),a
	inc l
	inc l
	inc l
	inc l			; every 4th row -> dotted
	ld a,l
	cp 251			; past y = 247 (top edge)?
	jp nz,.pb_vrow
	ld a,h
	add a,2			; next line is 16 px = 2 xbytes to the right
	ld h,a
	cp 0B7h			; done after xbyte 21 (hi 0B5h)?
	jp nz,.pb_vcol
; ---- 11 horizontal dotted lines ----
	ld b,11			; line count
	ld c,47			; y of the first line (bottom edge)
.pb_hline:
	ld h,0A1h		; xbyte 1
	ld l,c
	ld d,20			; xbytes 1..20 lie fully inside the board
.pb_hcol:
	ld a,(hl)
	or 88h			; 10001000 -> every 4th pixel
	ld (hl),a
	inc h			; next xbyte (8 px to the right)
	dec d
	jp nz,.pb_hcol
	ld a,(hl)		; xbyte 21: only bit7 (x = 168) is on the board
	or 80h
	ld (hl),a
	ld a,c
	add a,20		; next line is 20 px up
	ld c,a
	dec b
	jp nz,.pb_hline
; ---- punch out the two lake interiors ----
	ld h,0A7h		; lake 1: interior vertical line (xbyte 7)
	call .pb_clr_vseg
	ld h,0AFh		; lake 2: interior vertical line (xbyte 15)
	call .pb_clr_vseg
	ld l,147		; interior horizontal line (row 4 / row 5 boundary)
	ld h,0A5h		; lake 1: xbyte 5 keeps bit7 (perimeter), clears the rest
	ld a,(hl)
	and 80h
	ld (hl),a
	ld h,0A6h		; lake 1: xbytes 6,7,8 cleared fully
	call .pb_clr_3
	ld l,147
	ld h,0ADh		; lake 2: xbyte 13 keeps bit7 (perimeter)
	ld a,(hl)
	and 80h
	ld (hl),a
	ld h,0AEh		; lake 2: xbytes 14,15,16 cleared fully
	call .pb_clr_3
	ret

.pb_clr_vseg:			; H = xbyte hi byte; clear bit7 for y = 128..166
	ld l,128
.pb_cv:	ld a,(hl)
	and 7Fh
	ld (hl),a
	inc l
	ld a,l
	cp 167
	jp nz,.pb_cv
	ret

.pb_clr_3:			; H = first xbyte hi byte, L = y; zero 3 xbytes across
	xor a
	ld (hl),a
	inc h
	ld (hl),a
	inc h
	ld (hl),a
	ret

;----------------------------------------------------------------------------

; FONT
	INCLUDE "strategf.asm"

; Piece faces (generated by tools\mkpieces.py)
	INCLUDE "strategp.asm"

; Lake bitmaps (generated by tools\mklakes.py)
	INCLUDE "strategt.asm"

;----------------------------------------------------------------------------
Strat1End:
	DISPLAY "Code end: ", /A, Strat1End

; Field background image (tools\mkfield.py): the C000h plane, then the E000h
; plane, 4000 bytes each, column oriented, byte (xbyte x, row j) at x*200 + j
FIELD_PLANE	EQU 4000
FieldImage:
	INCBIN "strategb.bin"
FieldEnd:
	DISPLAY "Top address: ", /A, FieldEnd
	DS CORE_ORG-FieldEnd
	OUTEND
	END