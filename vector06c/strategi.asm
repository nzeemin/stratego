;----------------------------------------------------------------------------
; Intro screens. Each page is a zero-terminated string for PrintString, at most
; 31 characters per line (32 would wrap on its own), 0Dh = new line,
; 01h/02h/03h = blue / red / white text.
;----------------------------------------------------------------------------

; Show the pages, each until a key is pressed (the time spent seeds the game)
; O: all registers destroyed
ShowIntro:
	ld hl,IntroTab
.si_page:
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl			; DE = page, HL = next table entry
	ld a,d
	or e
	ret z
	push hl
	push de
	call ClearScreen
	xor a
	ld (CurCol),a
	ld (CurRow),a
	ld a,COL_WHITE
	call SetColor
	pop hl
	call PrintString
	call GetKey
	pop hl
	jp .si_page

IntroTab:
	DW Intro1,Intro2,Intro3,Intro4,0

Intro1:
	DB 0Dh
	DB 2,"      S T R A T E G O",3,0Dh
	DB 0Dh
	DB "   June 18, 1815 - Waterloo",0Dh
	DB 0Dh
	DB "Napoleon has escaped from exile",0Dh
	DB "and marches on the British and",0Dh
	DB "Prussian army of the Duke of",0Dh
	DB "Wellington. They meet near the",0Dh
	DB "town of Waterloo. The fate of",0Dh
	DB "Europe depends on the battle.",0Dh
	DB 0Dh
	DB "You are Napoleon, the ",1,"BLUE",3," army",0Dh
	DB "at the bottom of the board.",0Dh
	DB "The computer is Wellington,",0Dh
	DB "the ",2,"RED",3," army.",0Dh
	DB 0Dh
	DB "GOAL: capture the enemy flag.",0Dh
	DB 0Dh
	DB "Game AI based on BASIC code for",0Dh
	DB "TI-99/4A by Walid Maalouli",0Dh
	DB "Ported by Nikita Zimin",0Dh
	DB 0Dh
	DB "      Press any key",0

Intro2:
	DB 2,"ARMY",3," (40 pieces each side):",0Dh
	DB "M Marshal 1   9 General 1",0Dh
	DB "8 Colonel 2   7 Major 3",0Dh
	DB "6 Captain 4   5 Lieut. 4",0Dh
	DB "4 Sergeant 4  3 Miner 5",0Dh
	DB "2 Scout 8     S Spy 1",0Dh
	DB "B Bomb 6      F Flag 1",0Dh
	DB "A higher number is stronger.",0Dh
	DB 0Dh
	DB 2,"MOVES",3,0Dh
	DB "Red moves first, then you.",0Dh
	DB "One piece, one square: forward,",0Dh
	DB "back or sideways, no diagonals,",0Dh
	DB "no lakes. Scouts (2) go any",0Dh
	DB "distance in a straight line",0Dh
	DB "over empty squares. Bombs and",0Dh
	DB "the Flag never move.",0Dh
	DB 0Dh
	DB "      Press any key",0

Intro3:
	DB 2,"BATTLE",3,0Dh
	DB "Move onto an enemy piece to",0Dh
	DB "attack. The higher rank wins,",0Dh
	DB "the other is lost. Equal ranks:",0Dh
	DB "both are lost.",0Dh
	DB 0Dh
	DB "The Spy beats the Marshal only",0Dh
	DB "when the Spy attacks.",0Dh
	DB 0Dh
	DB "A Miner defuses a Bomb; any",0Dh
	DB "other attacker is lost.",0Dh
	DB 0Dh
	DB 2,"WINNING",3,0Dh
	DB "You win by taking the enemy",0Dh
	DB "Flag or leaving it with no",0Dh
	DB "movable piece.",0Dh
	DB 0Dh
	DB "      Press any key",0

Intro4:
	DB 2,"CONTROLS",3,0Dh
	DB "To move, type four keys (no",0Dh
	DB "Enter): from column, from row,",0Dh
	DB "to column, to row.",0Dh
	DB "Example: E6E5 moves the piece",0Dh
	DB "on E6 to E5.",0Dh
	DB "Backspace deletes a key.",0Dh
	DB 0Dh
	DB "N  new game",0Dh
	DB "R  resign",0Dh
	DB 0Dh
	DB 2,"SCREEN",3,0Dh
	DB "Your blue pieces show their",0Dh
	DB "rank. Red pieces are hidden",0Dh
	DB "until the end of the game.",0Dh
	DB "A line under a blue piece means",0Dh
	DB "the computer has found it out.",0Dh
	DB "Right: pieces left, totals,",0Dh
	DB "move number, last moves.",0Dh
	DB 0Dh
	DB "Your army is placed at random.",0Dh
	DB 0Dh
	DB "   Press any key to play",0

