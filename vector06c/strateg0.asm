;----------------------------------------------------------------------------

	EXPORT KeyLineEx
	EXPORT KeyLine0		; KeyLine0..KeyLine7: keyboard matrix rows, bit = 0 when pressed
	EXPORT KeyLine7		; (KeyLine1 is not scanned and always reads 0FFh)
	EXPORT JoystickP	; F200DULR
	;EXPORT BorderColor
	EXPORT dzx0
	EXPORT STRATCOD0_END
	EXPORT STRATCOD1_START

	INCLUDE "core/core.inc"

;----------------------------------------------------------------------------

	OUTPUT "strateg0.bin"
	ORG	100h

	di
	xor A
	out (10h),A			; turn off the quasi-disk
	ld sp,0100h
	ld hl,0C3F3h
	ld (0),HL
	ld A,H
	ld HL,RestartInt
	ld (2),HL
	ld (38h),A
	ld HL,KEYINT			; interrupt handler address
	ld (38h+1),HL

	call SetPaletteGame		; changing palette only once
	di

; Move encoded block from STRATCOD0_END to memory end
	ld DE,STRATCOD0_END		; source addr
	ld BC,0FFFFh-LZSIZE1-LZSIZE2  ; destination addr
	ld HL,LZSIZE1+LZSIZE2	; size
	inc H
Init_1:
	ld A,(DE)
	inc DE
	ld (BC),A
	inc BC
	dec L
	jp nz,Init_1
	dec H
	jp nz,Init_1
; Decompress stratego1.asm code from memory end to STRATCOD0_END
	ld DE,0FFFFh-LZSIZE1-LZSIZE2	; source addr
	ld BC,STRATCOD1_START		; destination addr
	call dzx0
; Decompress game core from memory end to STRATCOD0_END
	ld DE,0FFFFh-LZSIZE2  		; source addr
	ld BC,CORE_ORG			; destination addr
	call dzx0

RestartInt:
	ld SP,100h
	ld A,88h
	out (4),A			; initialize R-Sound 2
; Joystick init
	ld A,83h			; control byte
	out (4),A			; initialize the I/O controller
	ld A,9Fh			; bits to check Joystick-P, both P1 and P2
	out (5),A			; set Joystick-P query bits
	in A,(6)			; read Joystick-P initial value
	ld (KEYINT_J+1),A		; store as XOR instruction parameter
;
; Start STRATCOD1
	jp	STRATCOD1_START

;----------------------------------------------------------------------------

KEYINT:
	push AF
	ld A,8Ah
	out (0),A
; Keyboard scan
	in A,(1)
	or 00011111b
	ld (KeyLineEx),A
	ld A,0FEh
	out (3),A
	in A,(2)
	ld (KeyLine0),A
;	ld A,0FDh		; row 1 is not scanned
;	out (3),A
;	in A,(2)
;	ld (KeyLine1),A
	ld A,0FBh
	out (3),A
	in A,(2)
	ld (KeyLine2),A
	ld A,0F7h
	out (3),A
	in A,(2)
	ld (KeyLine3),A
	ld A,0EFh
	out (3),A
	in A,(2)
	ld (KeyLine4),A
	ld A,0DFh
	out (3),A
	in A,(2)
	ld (KeyLine5),A
	ld A,0BFh
	out (3),A
	in A,(2)
	ld (KeyLine6),A
	ld A,07Fh
	out (3),A
	in A,(2)
	ld (KeyLine7),A
; Joystick scan
	in A,(6)		; read Joystick-P
KEYINT_J:
	xor 0			; XOR with initial value - mutable param!
	cpl
	ld (JoystickP),A	; save to analyze later

; Scrolling, screen mode, border
	ld A,88h
	out (0),A
	ld A,2
	out (1),A
	ld A,0FFh
	out (3),A		; scrolling
	xor A	;ld A,(BorderColor)
		;and 0Fh
	out (2),A		; screen mode and border
;
	pop AF
	ei
	ret

KeyLineEx:	DB 11111111b
; Keyboard matrix, one byte per row, in row order (indexable from KeyLine0)
KeyLine0:	DB 11111111b
KeyLine1:	DB 11111111b		; not scanned
KeyLine2:	DB 11111111b
KeyLine3:	DB 11111111b
KeyLine4:	DB 11111111b
KeyLine5:	DB 11111111b
KeyLine6:	DB 11111111b
KeyLine7:	DB 11111111b
JoystickP:	DB 11111111b

;BorderColor:	DB 0		; border color number 0..15

;----------------------------------------------------------------------------

; ZX0 decompressor code by Ivan Gorodetsky
; https://github.com/ivagorRetrocomp/DeZX/blob/main/ZX0/8080/OLD_V1/dzx0_CLASSIC.asm
; input:	de=compressed data start
;		bc=uncompressed destination start
;NOTE: FORWARD decompression only
dzx0:
		ld hl,0FFFFh
		push HL
		inc HL
		ld A,080h
dzx0_literals:
		call dzx0_elias
		call dzx0_ldir
		jp c,dzx0_new_offset
		call dzx0_elias
dzx0_copy:
		ex DE,HL
		ex (SP),HL
		push HL
		add HL,BC
		ex DE,HL
		call dzx0_ldir
		ex DE,HL
		pop HL
		ex (SP),HL
		ex DE,HL
		jp NC,dzx0_literals
dzx0_new_offset:
		call dzx0_elias
		ld H,A
		pop AF
		xor A
		sub L
		ret z
		push HL
		rra
		ld H,A
		ld A,(DE)
		rra
		ld L,A
		inc de
		ex (SP),HL
		ld A,H
		ld HL,1
		call nc,dzx0_elias_backtrack
		inc HL
		jp dzx0_copy
dzx0_elias:
		inc L
dzx0_elias_loop:
		add A,A
		jp NZ,dzx0_elias_skip
		ld A,(de)
		inc DE
		rla
dzx0_elias_skip:
		ret C
dzx0_elias_backtrack:
		add HL,HL
		add A,A
		jp NC,dzx0_elias_loop
		jp dzx0_elias

dzx0_ldir:
		push AF
dzx0_ldir1:
		ld A,(DE)
		ld (BC),A
		inc DE
		inc BC
		dec HL
		ld A,H
		or L
		jp nz,dzx0_ldir1
		pop AF
		add A,A
		ret

;----------------------------------------------------------------------------
STRATCOD1_START
;WARN: Code below this point will be erased after the main code unpack

ColorNone  EQU 00000000b   ; Color for empty bits  - black
ColorBlue  EQU 11110011b   ; Color for plane 0 only - blue
ColorRed   EQU 01000110b   ; Color for plane 1 only - red
ColorWhite EQU 10101101b   ; Color for both planes  - white (dimmed)
; Field background colors (tools\mkfield.py -> strategb.inc), indexes 4..7
FieldBlack  EQU 00h
FieldBrown  EQU 13h
FieldYellow EQU 1Ch
FieldGreen  EQU 12h
; Palette colors, game. Index bit 2 (plane A000h) set = the field background;
; index bit 3 (the invisible plane 8000h) is never set, 8..15 repeat 0..7.
PaletteGame:		; Palette
	DB	ColorNone, ColorBlue, ColorRed, ColorWhite	; 0..3
	DB	FieldBlack, FieldBrown, FieldYellow, FieldGreen	; 4..7
	DB	ColorNone, ColorBlue, ColorRed, ColorWhite	; 8..11
	DB	FieldBlack, FieldBrown, FieldYellow, FieldGreen	; 12..15

; Set game palette
SetPaletteGame:
	ld HL,PaletteGame+15
; Programming the Palette
SetPalette:
	ei
	halt
	ld DE,100Fh
PaletLoop:
	ld A,E
	out (2),A
	ld A,(HL)
	out (0Ch),A
	out (0Ch),A
	out (0Ch),A
	out (0Ch),A
	out (0Ch),A
	dec HL
	out (0Ch),A
	dec E
	out (0Ch),A
	dec D
	out (0Ch),A
	jp nz,PaletLoop
	ret

;----------------------------------------------------------------------------
STRATCOD0_END
	OUTEND
	END