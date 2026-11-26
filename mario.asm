; =============================================================================
;  MARIO.ASM  -  SUPER MARIO ENGINE   (EL2003 COAL Semester Project, Fall 2026)
;  16-bit real-mode platform game for NASM (-f bin -> MARIO.COM) and DOSBox.
;
;  Files    : mario.asm (code + data), sprites.inc (artwork), level.inc (level)
;  Build    : nasm -f bin mario.asm -o MARIO.COM
;  Calling  : parameters are PUSHed left-to-right (last argument is nearest to
;             the return address, i.e. at [bp+4]); the callee removes them with
;             RET n.  Every procedure preserves every register it does not
;             return (results are returned in AX).
;  Modules  : see the MODULE banners below (1..15).
; =============================================================================
        bits 16
        cpu  386
        org  100h

; ----------------------------------------------------------------- MODULE 1
; Named constants (Appendix A)
; -----------------------------------------------------------------------------
SCREEN_W        equ 320
SCREEN_H        equ 200
TILE            equ 16
MAP_COLS        equ 60
MAP_ROWS        equ 12
MAP_SIZE        equ MAP_COLS*MAP_ROWS
LEVEL_W         equ MAP_COLS*TILE       ; 960 pixels
CAM_MAX         equ LEVEL_W-SCREEN_W    ; 640
MARIO_MAXX      equ LEVEL_W-16          ; 944
MARIO_START_X   equ 32
POLE_COL        equ 56                  ; map column of the flag pole
POLE_X          equ POLE_COL*TILE       ; its world x (896)
GROUND_TOP_Y    equ 160                 ; y of the first ground row (row 10)
VGA_SEG         equ 0A000h
FRAME_PARAS     equ 4000                ; 64000 bytes = 4000 paragraphs
PIT_DIV         equ 39773               ; 1193182 / 39773 = 30.0 Hz timer
TICKS_PER_SEC   equ 30
INVULN_TICKS    equ 60                  ; about 2 seconds
START_TIME      equ 300
START_LIVES     equ 3

; palette indices (own 16 colour palette, see Palette table)
COL_BLACK       equ 0
COL_SKY         equ 1
COL_RED         equ 2
COL_SKIN        equ 3
COL_BROWN       equ 4
COL_DARK        equ 5
COL_WHITE       equ 6
COL_BLUE        equ 7
COL_GREEN       equ 8
COL_DGREEN      equ 9
COL_ORANGE      equ 10
COL_TAN         equ 11
COL_YELLOW      equ 12
COL_GRAY        equ 13
COL_LGREEN      equ 14
COL_BRICK       equ 15

; keyboard scan codes (Appendix A.3)
SC_ESC          equ 01h
SC_P            equ 19h
SC_ENTER        equ 1Ch
SC_LSHIFT       equ 2Ah
SC_SPACE        equ 39h
SC_LEFT         equ 4Bh
SC_RIGHT        equ 4Dh
SC_UP           equ 48h
SC_DOWN         equ 50h
SC_F1           equ 3Bh                 ; debug: clock = 5 seconds
SC_F2           equ 3Ch                 ; debug: coins = 99
SC_F3           equ 3Dh                 ; debug: switch between level 1 and level 2

; game states (Section 5.12)
ST_TITLE        equ 0
ST_PLAYING      equ 1
ST_PAUSED       equ 2
ST_DYING        equ 3
ST_LIFELOST     equ 4
ST_WINSEQ       equ 5
ST_LEVELCOMP    equ 6
ST_GAMEOVER     equ 7
ST_EXIT         equ 8

; tile codes (Appendix A.2)
T_SKY           equ 0
T_GROUND        equ 1
T_BRICK         equ 2
T_QCOIN         equ 3
T_QMUSH         equ 4
T_EMPTY         equ 5
T_STAIR         equ 10
T_COIN          equ 11
T_POLE          equ 12

; physics, 8.8 fixed point (Appendix A.5)
ACCEL           equ 0020h
FRICTION        equ 0010h
WALK_MAX        equ 0180h
RUN_MAX         equ 0280h
GRAVITY         equ 0040h
JUMP_V          equ 0FA80h              ; -5.5
JUMP_CUT        equ 0FE00h              ; -2.0
FALL_MAX        equ 0400h
BOUNCE_V        equ 0FD00h              ; -3.0
BOUNCE_HI_V     equ 0FC80h              ; -3.5 (jump key held)
DEATH_HOP_V     equ 0FB00h              ; -5.0 (about 50 pixels)
GOOMBA_V        equ 0080h
KOOPA_V         equ 00C0h
SHELL_V         equ 0300h
MUSH_V          equ 0100h

; entity records (fixed size, Section 5.5)
E_TYPE          equ 0                   ; db
E_STATE         equ 1                   ; db
E_X             equ 2                   ; dw  world x (pixels)
E_XF            equ 4                   ; db  x fraction
E_GRACE         equ 5                   ; db  frames that ignore Mario (kick)
E_Y             equ 6                   ; dw  y, 8.8
E_VX            equ 8                   ; dw  8.8 signed
E_VY            equ 10                  ; dw  8.8 signed
E_TIMER         equ 12                  ; dw
E_AUX           equ 14                  ; dw
ENT_SIZE        equ 16
ENT_MAX         equ 12                  ; level 2 has 7 enemies + 5 free slots
LAST_LEVEL      equ 1                   ; levels are numbered from 0
MOON_CX         equ 250                 ; night sky: moon centre and top
MOON_Y          equ 22
NSTARS          equ 28
NHILLS          equ 5
NTREES          equ 6

ET_NONE         equ 0
ET_GOOMBA       equ 1
ET_KOOPA        equ 2
ET_SHELL        equ 3
ET_MUSH         equ 4
ES_WAIT         equ 0
ES_WALK         equ 1
ES_FLAT         equ 2
ES_STILL        equ 3
ES_SLIDE        equ 4

EFF_MAX         equ 8                   ; effect records (pop-ups, coin pops)
EFF_SIZE        equ 8

; =============================================================================
;  PROGRAM ENTRY  (Module 1, 5, 14, 15)
; =============================================================================
start:
        cld
        ; --- Module 5: give back unused memory, then allocate the frame buffer
        mov     ah,4Ah                  ; resize our block to 64 KB
        mov     bx,1000h
        int     21h
        jc      near .nomem
        mov     ah,48h                  ; allocate 4000 paragraphs (64000 bytes)
        mov     bx,FRAME_PARAS
        int     21h
        jc      near .nomem
        mov     [FrameSeg],ax

        call    InitLevel               ; characters -> tile codes
        call    InitFont                ; pointer to the ROM 8x8 font
        call    ParseCmdLine            ; AL = 1 when the T switch is given

        mov     bl,al
        mov     ax,0013h                ; VGA mode 13h
        int     10h
        call    SetPalette
        test    bl,bl
        jz      .normal
        call    ColorTestScreen         ; Module 2 test screen, then exit
        jmp     .exit

.normal:
        mov     ax,[FrameSeg]
        mov     [DrawSeg],ax            ; everything is drawn into the frame buffer
        call    InstallHandlers
        call    NewGame
        mov     byte [GameState],ST_TITLE
        mov     ax,[TickCount]
        mov     [LastTick],ax

.mainloop:                              ; --- Module 14: state machine ------
        call    WaitTick                ; step 1 of the frame order
%ifdef TESTMODE
        call    TestStep                ; test build only: scripted input
        test    al,al
        jnz     .mainloop               ; frozen frame: the screen keeps its picture
%endif
        xor     bh,bh
        mov     bl,[GameState]
        shl     bx,1
        call    word [StateTable+bx]    ; jump table indexed by the state
        cmp     byte [GameState],ST_EXIT
        jne     .mainloop

        call    RestoreHandlers         ; Module 15: clean exit
.exit:
        mov     ax,0003h                ; back to text mode
        int     10h
        mov     ax,4C00h                ; DOS exit
        int     21h

.nomem:
        mov     dx,MsgNoMem
        mov     ah,09h
        int     21h
        mov     ax,4C01h
        int     21h

; -----------------------------------------------------------------------------
; ParseCmdLine
; Purpose : looks for the switch T (or /T) in the DOS command tail.
; Inputs  : none (reads the PSP at offset 80h)
; Outputs : AL = 1 if the colour test screen was requested, else 0
; Changes : AL (all other registers preserved)
; -----------------------------------------------------------------------------
ParseCmdLine:
        push    bx
        push    cx
        xor     ch,ch
        mov     cl,[80h]                ; length of the command tail
        mov     bx,81h
        xor     al,al
.scan:  test    cl,cl
        jz      .done
        mov     ah,[bx]
        and     ah,0DFh                 ; to upper case
        cmp     ah,'T'
        jne     .next
        mov     al,1
        jmp     .done
.next:  inc     bx
        dec     cl
        jmp     .scan
.done:  pop     cx
        pop     bx
        ret

; =============================================================================
;  MODULE 2 : VIDEO MODE AND COLOURS
; =============================================================================

; -----------------------------------------------------------------------------
; SetPalette
; Purpose : loads the game's 16 colours into the VGA DAC (INT 10h, AX=1012h).
; Inputs  : none        Outputs : none        Changes : none
; -----------------------------------------------------------------------------
SetPalette:
        pusha
        push    es
        mov     ax,cs
        mov     es,ax
        xor     bx,bx
        mov     bl,[CurLevel]           ; level 1 = day palette, level 2 = night
        shl     bx,1
        mov     dx,[PaletteTbl+bx]
        mov     ax,1012h
        xor     bx,bx                   ; first colour register
        mov     cx,16                   ; number of registers
        int     10h
        pop     es
        popa
        ret

; -----------------------------------------------------------------------------
; PutPixel(x, y, colour)       push x ; push y ; push colour ; call PutPixel
; Purpose : plots one pixel into the current draw segment (clipped).
; Offset  : y*320 + x  computed with shifts  (y*256 + y*64 + x)
; Changes : none
; -----------------------------------------------------------------------------
PutPixel:
        push    bp
        mov     bp,sp
        push    ax
        push    bx
        push    di
        push    es
        mov     bx,[bp+8]               ; x
        mov     ax,[bp+6]               ; y
        cmp     bx,0
        jl      .out
        cmp     bx,SCREEN_W
        jge     .out
        cmp     ax,0
        jl      .out
        cmp     ax,SCREEN_H
        jge     .out
        mov     di,ax
        shl     di,8                    ; y*256
        shl     ax,6                    ; y*64
        add     di,ax
        add     di,bx
        mov     es,[DrawSeg]
        mov     al,[bp+4]
        mov     [es:di],al
.out:   pop     es
        pop     di
        pop     bx
        pop     ax
        pop     bp
        ret     6

; -----------------------------------------------------------------------------
; FillRect(x, y, w, h, colour)
; Purpose : fills a rectangle (clipped to the screen) using REP STOSB per row.
; Changes : none
; -----------------------------------------------------------------------------
FillRect:
        push    bp
        mov     bp,sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        mov     bx,[bp+12]              ; x
        mov     dx,[bp+10]              ; y
        mov     si,[bp+8]               ; w
        mov     cx,[bp+6]               ; h
        cmp     bx,0                    ; clip left
        jge     .xok
        add     si,bx
        xor     bx,bx
.xok:   mov     ax,SCREEN_W
        sub     ax,bx
        cmp     si,ax                   ; clip right
        jle     .wok
        mov     si,ax
.wok:   cmp     si,0
        jle     .exit
        cmp     dx,0                    ; clip top
        jge     .yok
        add     cx,dx
        xor     dx,dx
.yok:   mov     ax,SCREEN_H
        sub     ax,dx
        cmp     cx,ax                   ; clip bottom
        jle     .hok
        mov     cx,ax
.hok:   cmp     cx,0
        jle     .exit
        mov     di,dx
        shl     di,8
        mov     ax,dx
        shl     ax,6
        add     di,ax
        add     di,bx                   ; di = y*320 + x
        mov     es,[DrawSeg]
        mov     al,[bp+4]
        cld
.row:   push    cx
        mov     cx,si
        rep     stosb
        pop     cx
        add     di,SCREEN_W
        sub     di,si
        loop    .row
.exit:  pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret     10

; -----------------------------------------------------------------------------
; ColorTestScreen
; Purpose : Module 2 test screen: 16 swatches with their palette numbers.
;           Shown with  MARIO.COM T  ; waits for a key, then returns.
; -----------------------------------------------------------------------------
ColorTestScreen:
        pusha
        mov     word [DrawSeg],VGA_SEG
        xor     si,si                   ; colour number
.sw:    mov     ax,si
        and     ax,7
        mov     bx,ax
        shl     bx,5
        add     bx,32                   ; x = 32 + (n mod 8)*32
        mov     ax,si
        shr     ax,3
        mov     dx,ax
        shl     dx,6
        add     dx,50                   ; y = 50 + (n div 8)*64
        push    bx
        push    dx
        push    word 28
        push    word 28
        push    si
        call    FillRect
        push    bx                      ; palette number under each swatch
        add     dx,32
        push    dx
        push    word 0                  ; high word
        push    si                      ; low word
        push    word 0                  ; 0 = no leading zeros
        push    word COL_WHITE
        call    DrawNumber
        inc     si
        cmp     si,16
        jb      .sw
        push    word 40
        push    word 20
        push    word MsgTest
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        xor     ax,ax
        int     16h                     ; wait for any key (BIOS)
        popa
        ret

; =============================================================================
;  TEXT AND NUMBERS  (bitmap font from the BIOS ROM, drawn by our own code)
; =============================================================================

; -----------------------------------------------------------------------------
; InitFont
; Purpose : asks the BIOS (INT 10h AX=1130h BH=3) for the 8x8 ROM font and
;           remembers its far pointer in FontSeg:FontOff.
; Changes : none
; -----------------------------------------------------------------------------
InitFont:
        pusha
        push    es
        mov     ax,1130h
        mov     bh,03h
        int     10h                     ; returns ES:BP
        mov     [FontOff],bp
        mov     [FontSeg],es
        pop     es
        popa
        ret

; -----------------------------------------------------------------------------
; DrawBits8(x, y, address, colour, scale)
; Purpose : draws an 8x8 1-bit bitmap found at DS:address (msb = leftmost).
;           scale 1 writes pixels directly, bigger scales use FillRect.
; Changes : none
; -----------------------------------------------------------------------------
DrawBits8:
        push    bp
        mov     bp,sp
        pusha
        push    es
        mov     es,[DrawSeg]
        mov     si,[bp+8]               ; bitmap address
        xor     dx,dx                   ; row 0..7
.row:   mov     al,[si]
        inc     si
        mov     cx,8                    ; column counter
        xor     bx,bx                   ; column 0..7
.col:   shl     al,1
        jnc     .skip
        push    ax
        cmp     word [bp+4],1
        jne     .big
        ; scale 1: direct pixel
        ; FIX: clip to the screen (unsigned compares also reject negatives);
        ;      before, pop-ups / text near an edge wrote outside the buffer
        mov     ax,[bp+10]              ; y
        add     ax,dx
        cmp     ax,SCREEN_H
        jae     .done
        mov     di,ax
        shl     di,8
        shl     ax,6
        add     di,ax                   ; di = y*320
        mov     ax,[bp+12]              ; x
        add     ax,bx
        cmp     ax,SCREEN_W
        jae     .done
        add     di,ax
        mov     al,[bp+6]
        mov     [es:di],al
        jmp     .done
.big:   mov     ax,[bp+4]               ; scale
        push    ax
        imul    ax,bx
        add     ax,[bp+12]
        push    ax                      ; x
        mov     ax,[bp+4]
        imul    ax,dx
        add     ax,[bp+10]
        push    ax                      ; y
        push    word [bp+4]             ; w
        push    word [bp+4]             ; h
        push    word [bp+6]             ; colour
        call    FillRect
        pop     ax
.done:  pop     ax
.skip:  inc     bx
        loop    .col
        inc     dx
        cmp     dx,8
        jb      .row
        pop     es
        popa
        pop     bp
        ret     10

; -----------------------------------------------------------------------------
; DrawChar(x, y, ch, colour, scale)
; Purpose : copies the glyph of ch from the ROM font to CharBuf, then draws it.
; Changes : none
; -----------------------------------------------------------------------------
DrawChar:
        push    bp
        mov     bp,sp
        pusha
        push    es
        push    ds
        mov     bx,[bp+8]
        and     bx,7Fh
        shl     bx,3                    ; 8 bytes per glyph
        add     bx,[FontOff]
        mov     ax,[FontSeg]
        mov     si,bx
        mov     bx,cs
        mov     es,bx                   ; ES = CS (destination of MOVSB)
        mov     di,CharBuf
        mov     ds,ax                   ; DS = font segment
        mov     cx,8
        cld
        rep     movsb
        pop     ds
        pop     es
        push    word [bp+12]
        push    word [bp+10]
        push    word CharBuf
        push    word [bp+6]
        push    word [bp+4]
        call    DrawBits8
        popa
        pop     bp
        ret     10

; -----------------------------------------------------------------------------
; DrawString(x, y, address, colour, scale)   zero-terminated string
; Changes : none
; -----------------------------------------------------------------------------
DrawString:
        push    bp
        mov     bp,sp
        pusha
        mov     si,[bp+8]
        mov     bx,[bp+12]              ; current x
        mov     di,[bp+4]
        shl     di,3                    ; advance = 8*scale
.next:  xor     ax,ax
        mov     al,[si]
        test    al,al
        jz      .done
        push    bx
        push    word [bp+10]
        push    ax
        push    word [bp+6]
        push    word [bp+4]
        call    DrawChar
        add     bx,di
        inc     si
        jmp     .next
.done:  popa
        pop     bp
        ret     10

; -----------------------------------------------------------------------------
; DrawCentered(y, address, colour, scale)
; Purpose : draws a zero-terminated string centred horizontally.
; Changes : none
; -----------------------------------------------------------------------------
DrawCentered:
        push    bp
        mov     bp,sp
        pusha
        mov     si,[bp+8]
        xor     cx,cx                   ; length
.len:   cmp     byte [si],0
        je      .got
        inc     cx
        inc     si
        jmp     .len
.got:   mov     ax,[bp+4]
        shl     ax,3
        mul     cx                      ; pixel width = len*8*scale
        mov     bx,SCREEN_W
        sub     bx,ax
        sar     bx,1                    ; x = (320-width)/2   FIX: signed shift (wide text)
        push    bx
        push    word [bp+10]
        push    word [bp+8]
        push    word [bp+6]
        push    word [bp+4]
        call    DrawString
        popa
        pop     bp
        ret     8

; -----------------------------------------------------------------------------
; Div32By10
; Purpose : divides the 32-bit number DX:AX by 10 using two 16-bit DIVs.
; Inputs  : DX:AX        Outputs : DX:AX = quotient, CX = remainder
; Changes : AX, CX, DX (BX preserved)
; -----------------------------------------------------------------------------
Div32By10:
        push    bx
        mov     bx,ax                   ; keep low word
        mov     ax,dx
        xor     dx,dx
        mov     cx,10
        div     cx                      ; high word / 10
        xchg    ax,bx                   ; bx = high quotient, ax = low word
        div     cx                      ; (rem:low) / 10
        mov     cx,dx                   ; remainder
        mov     dx,bx                   ; quotient high
        pop     bx
        ret

; -----------------------------------------------------------------------------
; DrawNumber(x, y, high, low, digits, colour)
; Purpose : prints a 32-bit number in decimal.  digits > 0 -> zero padded to
;           that many digits, digits = 0 -> no leading zeros.  Remainders of
;           repeated division by 10 are pushed, then popped in reverse order.
; Changes : none
; -----------------------------------------------------------------------------
DrawNumber:
        push    bp
        mov     bp,sp
        pusha
        mov     dx,[bp+10]
        mov     ax,[bp+8]
        xor     si,si                   ; digit counter
.div:   call    Div32By10
        push    cx                      ; remainder
        inc     si
        mov     bx,[bp+6]
        test    bx,bx
        jz      .auto
        cmp     si,bx
        jb      .div
        jmp     .print
.auto:  mov     bx,ax
        or      bx,dx
        jnz     .div
.print: mov     bx,[bp+14]              ; x
.pl:    pop     ax
        add     al,'0'
        push    bx
        push    word [bp+12]
        push    ax
        push    word [bp+4]
        push    word 1
        call    DrawChar
        add     bx,8
        dec     si
        jnz     .pl
        popa
        pop     bp
        ret     12

; =============================================================================
;  SPRITES  (Module 4)
; =============================================================================

; -----------------------------------------------------------------------------
; DrawSprite(x, y, address, height, flags)
; Purpose : draws a 16-wide sprite (colour 0 = transparent) into the draw
;           segment.  flags bit 0 = mirror horizontally.  The sprite may be
;           partly or completely off screen on any side (clipped per pixel).
;           A fast path handles the common unmirrored, fully visible case.
; Changes : none
; -----------------------------------------------------------------------------
DrawSprite:
        push    bp
        mov     bp,sp
        pusha
        push    es
        mov     es,[DrawSeg]
        mov     si,[bp+8]               ; sprite data
        cmp     word [bp+6],0           ; FIX: height 0 / negative = nothing to draw
        jle     near .out
        cld
        ; ---- try the fast path: no mirror, fully inside the screen
        test    word [bp+4],1
        jnz     .slow
        mov     ax,[bp+12]
        cmp     ax,0
        jl      .slow
        cmp     ax,SCREEN_W-16
        jg      .slow
        mov     bx,[bp+10]
        cmp     bx,0
        jl      .slow
        mov     cx,bx
        add     cx,[bp+6]
        cmp     cx,SCREEN_H
        jg      .slow
        mov     di,bx                   ; di = y*320 + x
        shl     di,8
        shl     bx,6
        add     di,bx
        add     di,ax
        mov     dx,[bp+6]               ; rows
.frow:  mov     cx,16
.fpix:  lodsb
        test    al,al
        jz      .fz
        mov     [es:di],al
.fz:    inc     di
        loop    .fpix
        add     di,SCREEN_W-16
        dec     dx
        jnz     .frow
        jmp     .out
        ; ---- general path with clipping and mirroring
.slow:  xor     dx,dx                   ; row counter
.row:   mov     ax,[bp+10]
        add     ax,dx                   ; screen y of this row
        cmp     ax,0
        jl      .nextrow
        cmp     ax,SCREEN_H
        jge     .nextrow
        mov     di,ax
        shl     di,8
        shl     ax,6
        add     di,ax                   ; di = y*320
        xor     bx,bx                   ; column
.col:   mov     cx,[bp+12]
        add     cx,bx                   ; screen x
        cmp     cx,0
        jl      .nextcol
        cmp     cx,SCREEN_W
        jge     .nextcol
        mov     ax,bx
        test    word [bp+4],1
        jz      .nf
        mov     ax,15
        sub     ax,bx
.nf:    push    bx
        mov     bx,ax
        mov     al,[si+bx]
        pop     bx
        test    al,al
        jz      .nextcol
        push    di
        add     di,cx
        mov     [es:di],al
        pop     di
.nextcol:
        inc     bx
        cmp     bx,16
        jb      .col
.nextrow:
        add     si,16
        inc     dx
        cmp     dx,[bp+6]
        jb      .row
.out:   pop     es
        popa
        pop     bp
        ret     10

; -----------------------------------------------------------------------------
; DrawTileOpaque(x, y, address)
; Purpose : fast copy of a 16x16 tile that has no transparent pixels, using
;           REP MOVSW per row.  Falls back to DrawSprite if the tile is not
;           completely inside the screen.
; Changes : none
; -----------------------------------------------------------------------------
DrawTileOpaque:
        push    bp
        mov     bp,sp
        pusha
        push    es
        mov     ax,[bp+8]               ; x
        mov     bx,[bp+6]               ; y
        cmp     ax,0
        jl      .clip
        cmp     ax,SCREEN_W-16
        jg      .clip
        cmp     bx,0                    ; FIX: y must be fully inside as well
        jl      .clip
        cmp     bx,SCREEN_H-16
        jg      .clip
        mov     es,[DrawSeg]
        mov     si,[bp+4]
        mov     di,bx
        shl     di,8
        shl     bx,6
        add     di,bx
        add     di,ax
        mov     dx,16
        cld
.row:   mov     cx,8
        rep     movsw
        add     di,SCREEN_W-16
        dec     dx
        jnz     .row
        jmp     .out
.clip:  push    ax
        push    bx
        push    word [bp+4]
        push    word 16
        push    word 0
        call    DrawSprite
.out:   pop     es
        popa
        pop     bp
        ret     6

; =============================================================================
;  MODULE 3 : LEVEL MAP AND TILE DRAWING
; =============================================================================

; -----------------------------------------------------------------------------
; InitLevel
; Purpose : converts the readable character map (level.inc) into the original
;           byte table of tile codes (OrigMap), then copies it to WorkMap.
; Changes : none
; -----------------------------------------------------------------------------
InitLevel:
        pusha
        push    es
        mov     ax,cs
        mov     es,ax
        xor     bx,bx
        mov     bl,[CurLevel]
        shl     bx,1
        mov     si,[LevelTextTbl+bx]    ; character map of the current level
        mov     di,OrigMap
        mov     cx,MAP_SIZE
        cld
.ch:    lodsb
        xor     bx,bx
.find:  cmp     al,[TileChars+bx]       ; based-indexed look-up of the code
        je      .found
        inc     bx
        cmp     bx,13
        jb      .find
        xor     bx,bx                   ; unknown character = sky
.found: mov     [di],bl
        inc     di
        loop    .ch
        pop     es
        popa
        call    ResetMap
        ret

; -----------------------------------------------------------------------------
; LoadLevel
; Purpose : builds the map of level CurLevel and loads that level's palette
;           (level 1 = day colours, level 2 = night colours).
; Changes : none
; -----------------------------------------------------------------------------
LoadLevel:
        call    InitLevel
        call    SetPalette
        ret

; -----------------------------------------------------------------------------
; ResetMap
; Purpose : restores the working map from the untouched original with one
;           block-move instruction (REP MOVSW).
; Changes : none
; -----------------------------------------------------------------------------
ResetMap:
        pusha
        push    es
        mov     ax,cs
        mov     es,ax
        mov     si,OrigMap
        mov     di,WorkMap
        mov     cx,MAP_SIZE/2
        cld
        rep     movsw
        pop     es
        popa
        ret

; -----------------------------------------------------------------------------
; GetTile(px, py)
; Purpose : converts a world pixel position to the tile code stored there.
; Outputs : AX = tile code.  Outside the level to the left/right the result is
;           "ground" (an invisible wall); above or below the map it is sky.
; Changes : AX only
; -----------------------------------------------------------------------------
GetTile:
        push    bp
        mov     bp,sp
        push    bx
        mov     ax,[bp+6]               ; px
        cmp     ax,0
        jl      .wall
        cmp     ax,LEVEL_W
        jge     .wall
        mov     bx,[bp+4]               ; py
        cmp     bx,0
        jl      .sky
        cmp     bx,MAP_ROWS*TILE-0      ; rows 0..11 = pixels 0..191
        jge     .sky
        shr     ax,4                    ; column
        shr     bx,4                    ; row
        imul    bx,bx,MAP_COLS
        add     bx,ax
        xor     ax,ax
        mov     al,[WorkMap+bx]
        jmp     .out
.wall:  mov     ax,T_GROUND
        jmp     .out
.sky:   xor     ax,ax
.out:   pop     bx
        pop     bp
        ret     4

; -----------------------------------------------------------------------------
; IsSolid(px, py)
; Purpose : AX = 1 when the tile at that world position is solid (codes 1..10).
; Changes : AX only
; -----------------------------------------------------------------------------
IsSolid:
        push    bp
        mov     bp,sp
        push    word [bp+6]
        push    word [bp+4]
        call    GetTile
        cmp     ax,T_GROUND
        jb      .no
        cmp     ax,T_STAIR
        ja      .no
        mov     ax,1
        pop     bp
        ret     4
.no:    xor     ax,ax
        pop     bp
        ret     4

; -----------------------------------------------------------------------------
; SetTile(col, row, code)
; Purpose : writes a tile code into the WORKING map only.
; Changes : none
; -----------------------------------------------------------------------------
SetTile:
        push    bp
        mov     bp,sp
        push    ax
        push    bx
        mov     bx,[bp+6]               ; row
        cmp     bx,MAP_ROWS             ; FIX: never write outside the map
        jae     .out
        cmp     word [bp+8],MAP_COLS
        jae     .out
        imul    bx,bx,MAP_COLS
        add     bx,[bp+8]               ; + column
        mov     al,[bp+4]
        mov     [WorkMap+bx],al
.out:   pop     bx
        pop     ax
        pop     bp
        ret     6

; -----------------------------------------------------------------------------
; DrawMap
; Purpose : draws the visible part of the working map: 20 columns plus one
;           partial column.  First column = camera_x / 16 (shift), first
;           column x = -(camera_x mod 16) (mask).
; Changes : none
; -----------------------------------------------------------------------------
DrawMap:
        pusha
        mov     ax,[CamX]
        mov     dx,ax
        shr     ax,4                    ; first world column
        and     dx,15                   ; pixel offset
        mov     [TmpCol0],ax
        mov     [TmpOffs],dx
        mov     si,1                    ; row (row 0 is the HUD)
.row:   xor     di,di                   ; screen column 0..20
.col:   mov     ax,[TmpCol0]
        add     ax,di                   ; world column
        cmp     ax,MAP_COLS
        jae     .next
        mov     bx,si
        imul    bx,bx,MAP_COLS
        add     bx,ax
        xor     cx,cx
        mov     cl,[WorkMap+bx]         ; tile code
        test    cl,cl
        jz      .next
        mov     bx,cx
        shl     bx,1
        mov     bx,[TileAddr+bx]        ; sprite address for this code
        mov     ax,di
        shl     ax,4
        sub     ax,[TmpOffs]            ; screen x
        mov     dx,si
        shl     dx,4                    ; screen y
        cmp     cx,T_COIN
        je      .coin
        cmp     cx,T_POLE
        je      .pole
        push    ax
        push    dx
        push    bx
        call    DrawTileOpaque
        jmp     .next
.coin:  push    ax
        push    dx
        push    word SprCoin
        push    word 16
        push    word 0
        call    DrawSprite
        jmp     .next
.pole:  cmp     si,2                    ; top of the pole gets the flag
        jne     .body
        mov     bx,TilePoleTop
.body:  push    ax
        push    dx
        push    bx
        push    word 16
        push    word 0
        call    DrawSprite
.next:  inc     di
        cmp     di,21
        jb      .col
        inc     si
        cmp     si,MAP_ROWS
        jb      .row
        popa
        ret

; -----------------------------------------------------------------------------
; DrawCloud(x, y)
; Purpose : a cloud made of two white rectangles (bonus background art).
; Changes : none
; -----------------------------------------------------------------------------
DrawCloud:
        push    bp
        mov     bp,sp
        push    ax
        mov     ax,[bp+6]
        add     ax,8
        push    ax                      ; x + 8
        push    word [bp+4]             ; y
        push    word 24
        push    word 8
        push    word COL_WHITE
        call    FillRect
        push    word [bp+6]             ; x
        mov     ax,[bp+4]
        add     ax,8
        push    ax                      ; y + 8
        push    word 40
        push    word 8
        push    word COL_WHITE
        call    FillRect
        pop     ax
        pop     bp
        ret     4

; -----------------------------------------------------------------------------
; DrawBush(x)
; Purpose : a green bush standing on the ground (x is a screen position).
; Changes : none
; -----------------------------------------------------------------------------
DrawBush:
        push    bp
        mov     bp,sp
        push    ax
        mov     ax,[bp+4]
        add     ax,16
        push    ax
        push    word 142
        push    word 16
        push    word 6
        push    word COL_GREEN
        call    FillRect
        mov     ax,[bp+4]
        add     ax,8
        push    ax
        push    word 148
        push    word 32
        push    word 6
        push    word COL_GREEN
        call    FillRect
        push    word [bp+4]
        push    word 154
        push    word 48
        push    word 6
        push    word COL_GREEN
        call    FillRect
        mov     ax,[bp+4]
        add     ax,20
        push    ax
        push    word 146
        push    word 6
        push    word 3
        push    word COL_LGREEN
        call    FillRect
        pop     ax
        pop     bp
        ret     2

; -----------------------------------------------------------------------------
; DrawBackground
; Purpose : bonus parallax: clouds scroll at half the camera speed, bushes and
;           the castle scroll together with the world.
; Changes : none
; -----------------------------------------------------------------------------
DrawBackground:
        pusha
        cmp     byte [CurLevel],0
        je      .day
        call    DrawNightScenery        ; level 2: moon, stars, hills and pines
        jmp     .castle
.day:   xor     si,si                   ; cloud index * 2
.cloud: mov     ax,[CloudX+si]
        mov     dx,[CamX]
        shr     dx,1                    ; half speed
        sub     ax,dx
        cmp     ax,-48
        jl      .nc
        cmp     ax,SCREEN_W
        jge     .nc
        push    ax
        push    word [CloudY+si]
        call    DrawCloud
.nc:    add     si,2
        cmp     si,12
        jb      .cloud
        xor     si,si                   ; bushes (world coordinates)
.bush:  mov     ax,[BushX+si]
        sub     ax,[CamX]
        cmp     ax,-48
        jl      .nb
        cmp     ax,SCREEN_W
        jge     .nb
        push    ax
        call    DrawBush
.nb:    add     si,2
        cmp     si,8
        jb      .bush
        ; castle behind the flag pole (world x 928..959)
.castle: mov    ax,928
        sub     ax,[CamX]
        cmp     ax,SCREEN_W
        jge     near .done
        push    ax
        push    word 112
        push    word 32
        push    word 48
        push    word COL_BRICK
        call    FillRect
        mov     bx,ax
        push    bx                      ; battlements
        push    word 104
        push    word 8
        push    word 8
        push    word COL_BRICK
        call    FillRect
        add     bx,12
        push    bx
        push    word 104
        push    word 8
        push    word 8
        push    word COL_BRICK
        call    FillRect
        add     bx,12
        push    bx
        push    word 104
        push    word 8
        push    word 8
        push    word COL_BRICK
        call    FillRect
        add     ax,10                   ; door
        push    ax
        push    word 136
        push    word 12
        push    word 24
        push    word COL_BLACK
        call    FillRect
        cmp     byte [CurLevel],0
        je      .done
        sub     ax,8                    ; night: two lit castle windows
        push    ax
        push    word 120
        push    word 4
        push    word 6
        push    word COL_YELLOW
        call    FillRect
        add     ax,24
        push    ax
        push    word 120
        push    word 4
        push    word 6
        push    word COL_YELLOW
        call    FillRect
.done:  popa
        ret

; -----------------------------------------------------------------------------
; DrawNightScenery
; Purpose : level 2 backdrop.  Twinkling stars (slow parallax), a crescent moon
;           (fixed on the screen), far hills (quarter speed) and pine trees
;           (scroll with the world).  Everything is made of FillRect/PutPixel.
; Changes : none
; -----------------------------------------------------------------------------
DrawNightScenery:
        pusha
        ; ---- stars: x moves at 1/8 of the camera speed and wraps around
        xor     si,si
.star:  mov     cx,[StarX+si]
        mov     dx,[CamX]
        shr     dx,3
        sub     cx,dx
        jge     .sx
        add     cx,SCREEN_W
.sx:    mov     dx,[StarY+si]
        mov     bx,[TickCount]
        shr     bx,4                    ; twinkle: colour depends on time and index
        add     bx,si
        and     bx,6
        shr     bx,1
        xor     ax,ax
        mov     al,[StarCol+bx]
        test    si,6
        jnz     .small
        push    cx                      ; every 4th star is a bigger 2x2 one
        push    dx
        push    word 2
        push    word 2
        push    ax
        call    FillRect
        jmp     .ns
.small: push    cx
        push    dx
        push    ax
        call    PutPixel
.ns:    add     si,2
        cmp     si,2*NSTARS
        jb      .star
        ; ---- far hills
        xor     si,si
.hill:  mov     ax,[HillX+si]
        mov     dx,[CamX]
        shr     dx,2
        sub     ax,dx
        cmp     ax,-96
        jle     .nh
        cmp     ax,SCREEN_W
        jge     .nh
        push    ax
        call    DrawHill
.nh:    add     si,2
        cmp     si,2*NHILLS
        jb      .hill
        ; ---- crescent moon: one white row per line, the right part cut away
        xor     si,si
.moon:  xor     ax,ax
        mov     al,[MoonHW+si]          ; half width of this row of the disc
        mov     bx,MOON_CX
        sub     bx,ax                   ; left end
        mov     dx,MOON_CX
        add     dx,ax                   ; right end
        mov     di,si
        add     di,3                    ; second disc: 7 right, 3 up
        cmp     di,25
        jae     .nocut
        xor     ax,ax
        mov     al,[MoonHW+di]
        mov     cx,MOON_CX+7
        sub     cx,ax
        dec     cx                      ; last pixel before the cut-out disc
        cmp     cx,dx
        jge     .nocut
        mov     dx,cx
.nocut: cmp     dx,bx
        jl      .nm
        push    bx                      ; x
        mov     ax,MOON_Y
        add     ax,si
        push    ax                      ; y
        mov     ax,dx
        sub     ax,bx
        inc     ax
        push    ax                      ; width
        push    word 1
        push    word COL_WHITE
        call    FillRect
.nm:    inc     si
        cmp     si,25
        jb      .moon
        ; ---- pine trees (world coordinates)
        xor     si,si
.tree:  mov     ax,[TreeX+si]
        sub     ax,[CamX]
        cmp     ax,-24
        jle     .nt
        cmp     ax,SCREEN_W
        jge     .nt
        push    ax
        call    DrawPine
.nt:    add     si,2
        cmp     si,2*NTREES
        jb      .tree
        popa
        ret

; DrawHill(x) : dark rounded hill, 96 px wide, standing on the ground line.
DrawHill:
        push    bp
        mov     bp,sp
        push    ax
        mov     ax,[bp+4]
        push    ax
        push    word 150
        push    word 96
        push    word 10
        push    word COL_DGREEN
        call    FillRect
        add     ax,10
        push    ax
        push    word 140
        push    word 76
        push    word 10
        push    word COL_DGREEN
        call    FillRect
        add     ax,14
        push    ax
        push    word 130
        push    word 48
        push    word 10
        push    word COL_DGREEN
        call    FillRect
        add     ax,14
        push    ax
        push    word 122
        push    word 20
        push    word 8
        push    word COL_DGREEN
        call    FillRect
        pop     ax
        pop     bp
        ret     2

; DrawPine(x) : small pine tree (4 stacked layers and a trunk), 18 px wide.
DrawPine:
        push    bp
        mov     bp,sp
        push    ax
        mov     ax,[bp+4]
        add     ax,8
        push    ax
        push    word 150
        push    word 2
        push    word 10
        push    word COL_DARK
        call    FillRect
        sub     ax,7                    ; layer 1: x+1, 16 wide
        push    ax
        push    word 142
        push    word 16
        push    word 8
        push    word COL_GREEN
        call    FillRect
        add     ax,2                    ; layer 2: x+3, 12 wide
        push    ax
        push    word 134
        push    word 12
        push    word 8
        push    word COL_GREEN
        call    FillRect
        add     ax,2                    ; layer 3: x+5, 8 wide
        push    ax
        push    word 126
        push    word 8
        push    word 8
        push    word COL_GREEN
        call    FillRect
        add     ax,2                    ; layer 4 (tip): x+7, 4 wide
        push    ax
        push    word 118
        push    word 4
        push    word 8
        push    word COL_GREEN
        call    FillRect
        pop     ax
        pop     bp
        ret     2

; =============================================================================
;  MODULE 13 helpers : SCORE, COINS, LIVES, EFFECTS
; =============================================================================

; -----------------------------------------------------------------------------
; AddScore(points)
; Purpose : the one scoring procedure.  32-bit score kept in two words and
;           added with ADD/ADC; clamped to 999,999 (0F423Fh).
; Changes : none
; -----------------------------------------------------------------------------
AddScore:
        push    bp
        mov     bp,sp
        push    ax
        mov     ax,[bp+4]
        add     [ScoreLo],ax
        adc     word [ScoreHi],0
        cmp     word [ScoreHi],0Fh
        jb      .ok
        ja      .clamp
        cmp     word [ScoreLo],423Fh
        jbe     .ok
.clamp: mov     word [ScoreHi],0Fh
        mov     word [ScoreLo],423Fh
.ok:    pop     ax
        pop     bp
        ret     2

; AddLife : lives + 1 (never above 99).           Changes: none
AddLife:
        cmp     byte [Lives],99
        jae     .r
        inc     byte [Lives]
.r:     ret

; AddCoin : coins + 1; the 100th coin gives a life and resets the counter.
AddCoin:
        inc     byte [Coins]
        cmp     byte [Coins],100
        jb      .r
        mov     byte [Coins],0
        call    AddLife
.r:     ret

; -----------------------------------------------------------------------------
; SpawnEffect(kind, x, y, value)
; Purpose : starts a short visual effect (kind 1 = score pop-up showing value,
;           kind 2 = coin hopping out of a block).  x, y are world pixels.
; Changes : none
; -----------------------------------------------------------------------------
SpawnEffect:
        push    bp
        mov     bp,sp
        pusha
        mov     si,EffTbl
        mov     cx,EFF_MAX
.f:     cmp     byte [si],0
        je      .got
        add     si,EFF_SIZE
        loop    .f
        jmp     .out
.got:   mov     ax,[bp+10]
        mov     [si],al                 ; kind
        mov     byte [si+1],30          ; timer
        cmp     al,2
        jne     .t
        mov     byte [si+1],14
.t:     mov     ax,[bp+8]
        mov     [si+2],ax               ; x
        mov     ax,[bp+6]
        mov     [si+4],ax               ; y
        mov     ax,[bp+4]
        mov     [si+6],ax               ; value
.out:   popa
        pop     bp
        ret     8

; UpdateEffects : moves every effect upwards and removes finished ones.
UpdateEffects:
        pusha
        mov     si,EffTbl
        mov     cx,EFF_MAX
.l:     mov     al,[si]
        test    al,al
        jz      .n
        mov     bx,1                    ; pop-up rises 1 px per frame
        cmp     al,2
        jne     .mv
        mov     bx,3                    ; coin hops faster
.mv:    sub     [si+4],bx
        dec     byte [si+1]
        jnz     .n
        mov     byte [si],0
.n:     add     si,EFF_SIZE
        loop    .l
        popa
        ret

; DrawEffects : draws pop-up numbers and hopping coins.
DrawEffects:
        pusha
        mov     si,EffTbl
        mov     cx,EFF_MAX
.l:     mov     al,[si]
        test    al,al
        jz      .n
        mov     bx,[si+2]
        sub     bx,[CamX]               ; screen x
        mov     dx,[si+4]               ; y
        cmp     al,2
        je      .coin
        push    cx
        push    bx
        push    dx
        push    word 0
        push    word [si+6]
        push    word 0
        push    word COL_WHITE
        call    DrawNumber
        pop     cx
        jmp     .n
.coin:  push    cx
        push    bx
        push    dx
        push    word SprCoin
        push    word 16
        push    word 0
        call    DrawSprite
        pop     cx
.n:     add     si,EFF_SIZE
        loop    .l
        popa
        ret

; =============================================================================
;  MODULE 6 : CAMERA AND SCROLLING (Section 5.3)
; =============================================================================

; -----------------------------------------------------------------------------
; UpdateCamera
; Purpose : follow Mario once screen_x passes 160, clamp to 0..640, never move
;           left, keep Mario inside the level and behind the left screen edge.
; Changes : none
; -----------------------------------------------------------------------------
UpdateCamera:
        pusha
        mov     ax,[MarioXPix]
        sub     ax,[CamX]               ; 1. screen_x
        cmp     ax,160                  ; 2. only follow past the middle
        jle     .left
        mov     ax,[MarioXPix]
        sub     ax,160                  ;    new_camera
        cmp     ax,CAM_MAX              ; 3. clamp at the end of the level
        jle     .c1
        mov     ax,CAM_MAX
.c1:    cmp     ax,[CamX]               ; 4. never decrease
        jle     .left
        mov     [CamX],ax
.left:  mov     ax,[MarioXPix]          ; 5. left wall = left screen edge
        cmp     ax,[CamX]
        jge     .right
        mov     ax,[CamX]
        mov     [MarioXPix],ax
        mov     word [MarioXFr],0
        mov     word [MarioVX],0
.right: mov     ax,[MarioXPix]          ; right end of the level
        cmp     ax,MARIO_MAXX
        jle     .done
        mov     word [MarioXPix],MARIO_MAXX
        mov     word [MarioXFr],0
        mov     word [MarioVX],0
.done:  popa
        ret

; =============================================================================
;  MODULE 9 : PLAYER MOVEMENT AND PHYSICS      MODULE 10 : COLLISION
; =============================================================================

; MarioHeight : AX = 16 (Small) or 32 (Super).      Changes: AX
MarioHeight:
        mov     ax,16
        cmp     byte [Form],0
        je      .r
        mov     ax,32
.r:     ret

; -----------------------------------------------------------------------------
; RectOverlap(ax0,ay0,ax1,ay1, bx0,by0,bx1,by1)
; Purpose : AX = 1 when the two rectangles (end coordinates exclusive) overlap.
; Changes : AX only
; -----------------------------------------------------------------------------
RectOverlap:
        push    bp
        mov     bp,sp
        mov     ax,[bp+18]
        cmp     ax,[bp+6]
        jge     .no
        mov     ax,[bp+10]
        cmp     ax,[bp+14]
        jge     .no
        mov     ax,[bp+16]
        cmp     ax,[bp+4]
        jge     .no
        mov     ax,[bp+8]
        cmp     ax,[bp+12]
        jge     .no
        mov     ax,1
        pop     bp
        ret     16
.no:    xor     ax,ax
        pop     bp
        ret     16

; -----------------------------------------------------------------------------
; UpdateMario
; Purpose : Section 5.2 : acceleration, friction, run, jump (ground only),
;           variable jump height, gravity, then tile collision one axis at a
;           time (horizontal first, vertical second).
; Changes : none
; -----------------------------------------------------------------------------
UpdateMario:
        pusha
        call    MarioHeight
        mov     si,ax                   ; si = Mario height for this frame
        mov     bx,[MarioY]
        shr     bx,8
        add     bx,si
        mov     [PrevFeet],bx           ; feet position before moving

        ; ---------------------------------------------- horizontal speed
        mov     ax,[MarioVX]
        mov     bx,WALK_MAX
        cmp     byte [KeyTbl+SC_LSHIFT],0
        je      .nr
        mov     bx,RUN_MAX              ; Left Shift = run
.nr:    mov     cl,[KeyTbl+SC_LEFT]
        mov     ch,[KeyTbl+SC_RIGHT]
        cmp     cl,ch
        je      .friction               ; none or both keys
        test    cl,cl
        jnz     .left
.right: mov     byte [Facing],0
        cmp     ax,bx
        jg      .r_over
        mov     cx,ACCEL
        test    ax,ax
        jge     .r_a
        mov     cx,ACCEL*2              ; braking is faster
.r_a:   add     ax,cx
        cmp     ax,bx
        jle     .store
        mov     ax,bx
        jmp     .store
.r_over:sub     ax,FRICTION
        cmp     ax,bx
        jge     .store
        mov     ax,bx
        jmp     .store
.left:  mov     byte [Facing],1
        mov     dx,bx
        neg     dx                      ; dx = -max
        cmp     ax,dx
        jl      .l_over
        mov     cx,ACCEL
        test    ax,ax
        jle     .l_a
        mov     cx,ACCEL*2
.l_a:   sub     ax,cx
        cmp     ax,dx
        jge     .store
        mov     ax,dx
        jmp     .store
.l_over:add     ax,FRICTION
        cmp     ax,dx
        jle     .store
        mov     ax,dx
        jmp     .store
.friction:
        test    ax,ax
        jz      .store
        js      .fneg
        sub     ax,FRICTION
        jns     .store
        xor     ax,ax
        jmp     .store
.fneg:  add     ax,FRICTION
        js      .store
        xor     ax,ax
.store: mov     [MarioVX],ax

        ; ---------------------------------------------- jump and gravity
        cmp     byte [JumpBuf],0
        je      .nojump
        dec     byte [JumpBuf]
        cmp     byte [OnGround],0
        je      .nojump                 ; no double jump
        mov     word [MarioVY],JUMP_V
        mov     byte [OnGround],0
        mov     byte [JumpBuf],0
.nojump:
        mov     ax,[MarioVY]
        test    ax,ax
        jge     .grav
        cmp     byte [KeyTbl+SC_SPACE],0
        jne     .grav                   ; Space still held: full jump
        cmp     ax,JUMP_CUT
        jge     .grav
        mov     word [MarioVY],JUMP_CUT ; released early: cut the jump short
.grav:  mov     ax,[MarioVY]
        add     ax,GRAVITY
        cmp     ax,FALL_MAX
        jle     .gs
        mov     ax,FALL_MAX
.gs:    mov     [MarioVY],ax

        ; ---------------------------------------------- move horizontally
        mov     ax,[MarioXFr]
        add     ax,[MarioVX]
        mov     dx,ax
        sar     dx,8                    ; whole pixels moved (signed)
        and     ax,0FFh
        mov     [MarioXFr],ax
        add     [MarioXPix],dx
        mov     ax,[MarioVX]
        test    ax,ax
        jz      .vert
        mov     bx,[MarioXPix]
        js      .lside
        add     bx,13                   ; right edge of the hit box
        jmp     .hscan
.lside: add     bx,2                    ; left edge of the hit box
.hscan: mov     ax,[MarioY]
        shr     ax,8
        mov     di,ax
        shr     di,4                    ; first row covered
        add     ax,si
        dec     ax
        shr     ax,4
        mov     dx,ax                   ; last row covered
.hrow:  mov     ax,di
        shl     ax,4
        push    bx
        push    ax
        call    IsSolid
        test    ax,ax
        jnz     .hhit
        inc     di
        cmp     di,dx
        jle     .hrow
        jmp     .vert
.hhit:  mov     ax,bx
        sar     ax,4                    ; column of the wall   FIX: signed (x may be < 0)
        cmp     word [MarioVX],0
        jl      .hl
        shl     ax,4
        sub     ax,14                   ; stand against the wall (right side)
        jmp     .hset
.hl:    inc     ax
        shl     ax,4
        sub     ax,2
.hset:  mov     [MarioXPix],ax
        mov     word [MarioXFr],0
        mov     word [MarioVX],0

        ; ---------------------------------------------- move vertically
.vert:  mov     ax,[MarioY]
        mov     dx,[MarioVY]
        test    dx,dx
        js      .vup
        add     ax,dx
        jnc     .vset
        mov     ax,0FF00h               ; FIX: Y never wraps past the bottom ...
        jmp     .vset
.vup:   add     ax,dx
        jc      .vset                   ; carry = result still >= 0
        xor     ax,ax                   ; FIX: ... or above the top of the screen
        mov     word [MarioVY],0
.vset:  mov     [MarioY],ax
        mov     ax,[MarioVY]
        test    ax,ax
        jz      near .probe
        js      .rising
        mov     bx,[MarioY]             ; falling: look at the feet
        shr     bx,8
        add     bx,si
        dec     bx                      ; y of the lowest pixel row
        mov     di,[MarioXPix]
        add     di,2
        push    di
        push    bx
        call    IsSolid
        test    ax,ax
        jnz     .land
        mov     di,[MarioXPix]
        add     di,13
        push    di
        push    bx
        call    IsSolid
        test    ax,ax
        jz      .probe
.land:  shr     bx,4
        shl     bx,4                    ; top of the tile row under the feet
        sub     bx,si                   ; Mario's top = tile top - height
        shl     bx,8
        mov     [MarioY],bx
        mov     word [MarioVY],0
        jmp     .probe
.rising:mov     bx,[MarioY]             ; rising: look at the head
        shr     bx,8
        mov     di,[MarioXPix]
        add     di,8                    ; centre of the head first (Section 5.9)
        push    di
        push    bx
        call    IsSolid
        test    ax,ax
        jnz     .headhit
        mov     di,[MarioXPix]
        add     di,2
        push    di
        push    bx
        call    IsSolid
        test    ax,ax
        jnz     .headhit
        mov     di,[MarioXPix]
        add     di,13
        push    di
        push    bx
        call    IsSolid
        test    ax,ax
        jz      .probe
.headhit:
        mov     cx,di
        shr     cx,4                    ; column of the block that was hit
        mov     ax,bx
        shr     ax,4                    ; its row
        push    cx
        push    ax
        call    TriggerBlock            ; Module 12
        mov     ax,bx
        shr     ax,4
        inc     ax
        shl     ax,4                    ; just below the block
        shl     ax,8
        mov     [MarioY],ax
        mov     word [MarioVY],0

        ; ---------------------------------------------- on-ground probe
.probe: mov     byte [OnGround],0
        cmp     word [MarioVY],0
        jl      .pose
        mov     bx,[MarioY]
        shr     bx,8
        add     bx,si                   ; pixel row just below the feet
        mov     di,[MarioXPix]
        add     di,2
        push    di
        push    bx
        call    IsSolid
        test    ax,ax
        jnz     .gnd
        mov     di,[MarioXPix]
        add     di,13
        push    di
        push    bx
        call    IsSolid
        test    ax,ax
        jz      .pose
.gnd:   mov     byte [OnGround],1
        mov     byte [StompChain],0     ; landing resets the stomp chain

        ; ---------------------------------------------- pose
.pose:  mov     byte [Pose],2           ; jumping sprite in the air
        cmp     byte [OnGround],0
        je      .done
        mov     byte [Pose],0           ; standing
        cmp     word [MarioVX],0
        je      .done
        mov     byte [Pose],1           ; running (alternates with standing)
        test    byte [TickCount],4
        jz      .done
        mov     byte [Pose],0
.done:  popa
        ret

; =============================================================================
;  MODULE 12 : BLOCKS, COINS AND POWER-UPS (Section 5.9)
; =============================================================================

; -----------------------------------------------------------------------------
; TriggerBlock(col, row)
; Purpose : Mario's head hit this tile from below: brick (breaks for Super
;           Mario), "?" with coin, "?" with mushroom.  Works on the WORKING map.
; Changes : none
; -----------------------------------------------------------------------------
TriggerBlock:
        push    bp
        mov     bp,sp
        pusha
        mov     bx,[bp+4]
        cmp     bx,MAP_ROWS             ; FIX: row / column must be inside the map
        jae     near .out
        cmp     word [bp+6],MAP_COLS
        jae     near .out
        imul    bx,bx,MAP_COLS
        add     bx,[bp+6]
        mov     al,[WorkMap+bx]
        cmp     al,T_BRICK
        je      .brick
        cmp     al,T_QCOIN
        je      .qcoin
        cmp     al,T_QMUSH
        je      .qmush
        jmp     .out
.brick: cmp     byte [Form],0
        je      near .out                    ; Small Mario: the brick stays
        push    word [bp+6]
        push    word [bp+4]
        push    word T_SKY
        call    SetTile
        push    word 50
        call    AddScore
        mov     ax,[bp+6]
        shl     ax,4
        mov     cx,[bp+4]
        shl     cx,4
        push    word 1
        push    ax
        push    cx
        push    word 50
        call    SpawnEffect
        jmp     .out
.qcoin: push    word [bp+6]
        push    word [bp+4]
        push    word T_EMPTY
        call    SetTile
        call    AddCoin
        push    word 200
        call    AddScore
        mov     ax,[bp+6]
        shl     ax,4
        mov     cx,[bp+4]
        shl     cx,4
        sub     cx,16
        push    word 2                  ; the coin hops out
        push    ax
        push    cx
        push    word 0
        call    SpawnEffect
        sub     cx,12
        push    word 1                  ; and shows +200
        push    ax
        push    cx
        push    word 200
        call    SpawnEffect
        jmp     .out
.qmush: push    word [bp+6]
        push    word [bp+4]
        push    word T_EMPTY
        call    SetTile
        push    word [bp+6]
        push    word [bp+4]
        call    SpawnMushroom
.out:   popa
        pop     bp
        ret     4

; -----------------------------------------------------------------------------
; SpawnMushroom(col, row)
; Purpose : puts a mushroom on top of the block at (col,row) into a free slot
;           of the entity table; it starts moving right at 1 px/frame.
; Changes : none
; -----------------------------------------------------------------------------
SpawnMushroom:
        push    bp
        mov     bp,sp
        pusha
        mov     si,EntTbl
        mov     cx,ENT_MAX
.f:     cmp     byte [si+E_TYPE],ET_NONE
        je      .got
        add     si,ENT_SIZE
        loop    .f
        jmp     .out
.got:   mov     byte [si+E_TYPE],ET_MUSH
        mov     byte [si+E_STATE],ES_WALK
        mov     ax,[bp+6]
        shl     ax,4
        mov     [si+E_X],ax
        mov     byte [si+E_XF],0
        mov     byte [si+E_GRACE],0
        mov     ax,[bp+4]
        dec     ax
        shl     ax,4
        shl     ax,8
        mov     [si+E_Y],ax
        mov     word [si+E_VX],MUSH_V
        mov     word [si+E_VY],0
        mov     word [si+E_TIMER],0
        mov     word [si+E_AUX],0
.out:   popa
        pop     bp
        ret     4

; =============================================================================
;  MODULE 11 : ENEMIES, SHELLS AND MUSHROOMS (Section 5.5)
;  Entities live in a table of fixed-size records (see E_xxx offsets) and are
;  reached with indexed addressing: [si+E_X], [si+E_VX] ...
; =============================================================================

; EntMoveX(rec) : adds the horizontal speed (8.8) to the record's x position.
EntMoveX:
        push    bp
        mov     bp,sp
        push    ax
        push    dx
        push    si
        mov     si,[bp+4]
        xor     ax,ax
        mov     al,[si+E_XF]
        add     ax,[si+E_VX]
        mov     dx,ax
        sar     dx,8
        mov     [si+E_XF],al            ; fraction = low byte
        add     [si+E_X],dx
        pop     si
        pop     dx
        pop     ax
        pop     bp
        ret     2

; EntWallHit(rec) : AX = 1 when a solid tile is in front of the entity.
EntWallHit:
        push    bp
        mov     bp,sp
        push    bx
        push    si
        mov     si,[bp+4]
        mov     bx,[si+E_X]
        cmp     word [si+E_VX],0
        jl      .l
        add     bx,13
        jmp     .t
.l:     add     bx,2
.t:     mov     ax,[si+E_Y]
        shr     ax,8
        add     ax,8                    ; middle of the sprite
        push    bx
        push    ax
        call    IsSolid
        pop     si
        pop     bx
        pop     bp
        ret     2

; EntOnGround(rec) : AX = 1 when the entity stands on a solid tile.
EntOnGround:
        push    bp
        mov     bp,sp
        push    bx
        push    si
        mov     si,[bp+4]
        mov     bx,[si+E_Y]
        shr     bx,8
        add     bx,16
        mov     ax,[si+E_X]
        add     ax,2
        push    ax
        push    bx
        call    IsSolid
        test    ax,ax
        jnz     .out
        mov     ax,[si+E_X]
        add     ax,13
        push    ax
        push    bx
        call    IsSolid
.out:   pop     si
        pop     bx
        pop     bp
        ret     2

; EntGroundAhead(rec) : AX = 1 when there is floor under the front part of a
;                       walking entity (used by the Koopa to turn at ledges).
EntGroundAhead:
        push    bp
        mov     bp,sp
        push    bx
        push    si
        mov     si,[bp+4]
        mov     ax,[si+E_X]
        cmp     word [si+E_VX],0
        jl      .l
        add     ax,12
        jmp     .t
.l:     add     ax,4
.t:     mov     bx,[si+E_Y]
        shr     bx,8
        add     bx,16
        push    ax
        push    bx
        call    IsSolid
        pop     si
        pop     bx
        pop     bp
        ret     2

; EntFall(rec) : gravity, vertical move and landing on solid tiles.
EntFall:
        push    bp
        mov     bp,sp
        pusha
        mov     si,[bp+4]
        mov     ax,[si+E_VY]
        add     ax,GRAVITY
        cmp     ax,FALL_MAX
        jle     .g
        mov     ax,FALL_MAX
.g:     mov     [si+E_VY],ax
        add     [si+E_Y],ax
        mov     bx,[si+E_Y]
        shr     bx,8
        add     bx,15                   ; lowest pixel row of the sprite
        mov     ax,[si+E_X]
        add     ax,2
        push    ax
        push    bx
        call    IsSolid
        test    ax,ax
        jnz     .land
        mov     ax,[si+E_X]
        add     ax,13
        push    ax
        push    bx
        call    IsSolid
        test    ax,ax
        jz      .out
.land:  shr     bx,4
        shl     bx,4
        sub     bx,16                   ; stand on top of the tile
        shl     bx,8
        mov     [si+E_Y],bx
        mov     word [si+E_VY],0
.out:   popa
        pop     bp
        ret     2

; EntHitsOther(rec) : AX = 1 when this entity touches another walking enemy or
;                     shell (so it can turn around).
EntHitsOther:
        push    bp
        mov     bp,sp
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        mov     si,[bp+4]
        mov     di,EntTbl
        mov     cx,ENT_MAX
.l:     cmp     di,si
        je      .n
        mov     al,[di+E_TYPE]
        cmp     al,ET_GOOMBA
        jb      .n
        cmp     al,ET_SHELL
        ja      .n
        cmp     byte [di+E_STATE],ES_WALK
        jb      .n
        cmp     byte [di+E_STATE],ES_FLAT
        je      .n
        mov     ax,[si+E_X]
        sub     ax,[di+E_X]
        jns     .a1
        neg     ax
.a1:    cmp     ax,12
        jge     .n
        mov     ax,[si+E_Y]
        sub     ax,[di+E_Y]
        sar     ax,8
        jns     .a2
        neg     ax
.a2:    cmp     ax,12
        jge     .n
        mov     ax,1
        jmp     .out
.n:     add     di,ENT_SIZE
        loop    .l
        xor     ax,ax
.out:   pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     bp
        ret     2

; ShellKills(rec) : a sliding shell removes every Goomba / Koopa it touches
;                   (+500 each, Section 5.4).
ShellKills:
        push    bp
        mov     bp,sp
        pusha
        mov     si,[bp+4]
        mov     di,EntTbl
        mov     cx,ENT_MAX
.l:     mov     al,[di+E_TYPE]
        cmp     al,ET_GOOMBA
        je      .chk
        cmp     al,ET_KOOPA
        jne     .n
.chk:   cmp     byte [di+E_STATE],ES_WALK
        jne     .n
        mov     ax,[si+E_X]
        sub     ax,[di+E_X]
        jns     .a1
        neg     ax
.a1:    cmp     ax,14
        jge     .n
        mov     ax,[si+E_Y]
        sub     ax,[di+E_Y]
        sar     ax,8
        jns     .a2
        neg     ax
.a2:    cmp     ax,12
        jge     .n
        mov     byte [di+E_TYPE],ET_NONE
        push    word 500
        call    AddScore
        push    word 1
        push    word [di+E_X]
        mov     ax,[di+E_Y]
        shr     ax,8
        push    ax
        push    word 500
        call    SpawnEffect
.n:     add     di,ENT_SIZE
        loop    .l
        popa
        pop     bp
        ret     2

; -----------------------------------------------------------------------------
; UpdateOneEntity(rec)
; Purpose : one frame of Goomba / Koopa / shell / mushroom behaviour:
;           removal far left, activation near the screen, walking, turning at
;           walls (and Koopa ledges), falling, flat timer, shell sliding.
; Changes : none
; -----------------------------------------------------------------------------
UpdateOneEntity:
        push    bp
        mov     bp,sp
        pusha
        mov     si,[bp+4]
        mov     ax,[si+E_X]
        sub     ax,[CamX]               ; screen x
        cmp     ax,-48
        jge     .keep
        mov     byte [si+E_TYPE],ET_NONE        ; left far behind: removed
        jmp     .out
.keep:  cmp     byte [si+E_STATE],ES_WAIT
        jne     .act
        cmp     ax,SCREEN_W+16          ; wait until within one tile of the screen
        jge     near .out
        mov     byte [si+E_STATE],ES_WALK
        mov     ax,[GoombaSpd]          ; speeds depend on the level
        cmp     byte [si+E_TYPE],ET_KOOPA
        jne     .setv
        mov     ax,[KoopaSpd]
.setv:  neg     ax
        mov     [si+E_VX],ax
        jmp     .out
.act:   mov     al,[si+E_TYPE]
        cmp     al,ET_GOOMBA
        je      .walker
        cmp     al,ET_KOOPA
        je      .walker
        cmp     al,ET_SHELL
        je      .shell
        cmp     al,ET_MUSH
        je      near .mush
        jmp     .out

.walker:cmp     byte [si+E_STATE],ES_FLAT
        jne     .wmove
        dec     word [si+E_TIMER]       ; flat Goomba disappears after ~1 s
        jnz     near .out
        mov     byte [si+E_TYPE],ET_NONE
        jmp     .out
.wmove: mov     bx,[si+E_X]
        mov     cl,[si+E_XF]            ; remember the old position
        push    si
        call    EntMoveX
        push    si
        call    EntWallHit
        test    ax,ax
        jnz     .turn
        push    si
        call    EntHitsOther
        test    ax,ax
        jnz     .turn
        cmp     byte [si+E_TYPE],ET_KOOPA
        jne     .wfall
        push    si
        call    EntOnGround
        test    ax,ax
        jz      .wfall
        push    si
        call    EntGroundAhead
        test    ax,ax
        jnz     .wfall                  ; the Koopa turns at platform edges
.turn:  mov     [si+E_X],bx
        mov     [si+E_XF],cl
        neg     word [si+E_VX]
.wfall: push    si
        call    EntFall
        jmp     .below

.shell: cmp     byte [si+E_GRACE],0
        je      .sg
        dec     byte [si+E_GRACE]
.sg:    cmp     byte [si+E_STATE],ES_SLIDE
        jne     .sfall
        mov     bx,[si+E_X]
        mov     cl,[si+E_XF]
        push    si
        call    EntMoveX
        push    si
        call    EntWallHit
        test    ax,ax
        jz      .skill
        mov     [si+E_X],bx             ; bounce off the wall
        mov     [si+E_XF],cl
        neg     word [si+E_VX]
.skill: push    si
        call    ShellKills
.sfall: push    si
        call    EntFall
        jmp     .below

.mush:  mov     bx,[si+E_X]
        mov     cl,[si+E_XF]
        push    si
        call    EntMoveX
        push    si
        call    EntWallHit
        test    ax,ax
        jz      .mfall
        mov     [si+E_X],bx
        mov     [si+E_XF],cl
        neg     word [si+E_VX]
.mfall: push    si
        call    EntFall

.below: mov     ax,[si+E_Y]             ; fell below the map: removed
        shr     ax,8
        cmp     ax,SCREEN_H-8
        jb      .out
        mov     byte [si+E_TYPE],ET_NONE
.out:   popa
        pop     bp
        ret     2

; UpdateEntities : runs UpdateOneEntity for every used record of the table.
UpdateEntities:
        pusha
        mov     si,EntTbl
        mov     cx,ENT_MAX
.l:     cmp     byte [si+E_TYPE],ET_NONE
        je      .n
        push    si
        call    UpdateOneEntity
.n:     add     si,ENT_SIZE
        loop    .l
        popa
        ret

; -----------------------------------------------------------------------------
; StompScore(x, y)
; Purpose : stomp chain (Section 5.4): the chain counter indexes a word table;
;           the 11th and later stomp in one jump give a life instead.
; Changes : none
; -----------------------------------------------------------------------------
StompScore:
        push    bp
        mov     bp,sp
        pusha
        xor     bx,bx
        mov     bl,[StompChain]
        cmp     bl,10
        jae     .oneup
        shl     bx,1
        mov     ax,[ChainTbl+bx]
        push    ax
        call    AddScore
        push    word 1
        push    word [bp+6]
        push    word [bp+4]
        push    ax
        call    SpawnEffect
        jmp     .inc
.oneup: call    AddLife
.inc:   cmp     byte [StompChain],200
        jae     .out
        inc     byte [StompChain]
.out:   popa
        pop     bp
        ret     4

; -----------------------------------------------------------------------------
; BounceMario(enemy_top)
; Purpose : Mario bounces off an enemy; higher if the jump key is held.  His
;           feet are placed on the enemy's top so he is not inside it.
; Changes : none
; -----------------------------------------------------------------------------
BounceMario:
        push    bp
        mov     bp,sp
        pusha
        mov     word [MarioVY],BOUNCE_V
        cmp     byte [KeyTbl+SC_SPACE],0
        je      .b
        mov     word [MarioVY],BOUNCE_HI_V
.b:     mov     byte [OnGround],0
        call    MarioHeight
        mov     bx,[bp+4]
        sub     bx,ax                   ; top = enemy top - height
        jns     .bok
        xor     bx,bx                   ; FIX: never above the top of the screen
.bok:   shl     bx,8
        mov     [MarioY],bx
        popa
        pop     bp
        ret     2

; HurtMario : Section 5.7.  Super -> Small (feet fixed, 2 s invulnerable);
;             Small -> dies.  Ignored while invulnerable.
HurtMario:
        cmp     word [InvulnT],0
        jne     .r
        cmp     byte [Form],0
        je      .die
        mov     byte [Form],0
        mov     byte [HP],1
        add     word [MarioY],16*256    ; keep the feet where they are
        mov     word [InvulnT],INVULN_TICKS
        ret
.die:   push    word 1
        call    StartDeath
.r:     ret

; -----------------------------------------------------------------------------
; ResolveOne(rec)
; Purpose : Section 5.6 for one entity: rectangle overlap, stomp test, kick,
;           hurt or collect.
; Changes : none
; -----------------------------------------------------------------------------
ResolveOne:
        push    bp
        mov     bp,sp
        pusha
        mov     si,[bp+4]
        mov     al,[si+E_STATE]
        cmp     al,ES_WAIT
        je      near .out
        cmp     al,ES_FLAT
        je      near .out
        call    MarioHeight
        mov     di,ax                   ; di = Mario height
        mov     bx,[MarioY]
        shr     bx,8                    ; bx = Mario top
        mov     dx,[si+E_Y]
        shr     dx,8                    ; dx = enemy top
        mov     cx,[si+E_X]
        mov     ax,[MarioXPix]
        add     ax,2
        push    ax                      ; Mario hit box x0
        push    bx                      ;                y0
        add     ax,12
        push    ax                      ;                x1
        mov     ax,bx
        add     ax,di
        push    ax                      ;                y1
        mov     ax,cx
        add     ax,2
        push    ax                      ; entity hit box x0
        push    dx                      ;                y0
        add     ax,12
        push    ax                      ;                x1
        mov     ax,dx
        add     ax,16
        push    ax                      ;                y1
        call    RectOverlap
        test    ax,ax
        jz      near .out
        mov     al,[si+E_TYPE]
        cmp     al,ET_MUSH
        je      near .mush
        cmp     al,ET_SHELL
        je      .shell
        ; ---- Goomba or Koopa
        call    StompTest               ; AX = 1 if this is a stomp (dx = enemy top)
        test    ax,ax
        jz      .hurt
        push    word [si+E_X]
        push    dx
        call    StompScore
        push    dx
        call    BounceMario
        cmp     byte [si+E_TYPE],ET_KOOPA
        je      .toshell
        mov     byte [si+E_STATE],ES_FLAT       ; flattened Goomba, about 1 s
        mov     word [si+E_TIMER],TICKS_PER_SEC
        mov     word [si+E_VX],0
        jmp     .out
.toshell:
        mov     byte [si+E_TYPE],ET_SHELL
        mov     byte [si+E_STATE],ES_STILL
        mov     word [si+E_VX],0
        mov     byte [si+E_GRACE],8
        jmp     .out
.hurt:  call    HurtMario
        jmp     .out

.shell: cmp     byte [si+E_GRACE],0
        jne     near .out                    ; just kicked: ignores Mario
        cmp     byte [si+E_STATE],ES_STILL
        je      .kick
        call    StompTest               ; sliding shell
        test    ax,ax
        jz      .hurt
        push    word [si+E_X]
        push    dx
        call    StompScore
        push    dx
        call    BounceMario
        mov     byte [si+E_STATE],ES_STILL      ; stomped: stops
        mov     word [si+E_VX],0
        mov     byte [si+E_GRACE],8
        jmp     .out
.kick:  push    word 400
        call    AddScore
        push    word 1
        push    word [si+E_X]
        push    dx
        push    word 400
        call    SpawnEffect
        call    StompTest
        test    ax,ax
        jz      .nobounce
        push    dx
        call    BounceMario
.nobounce:
        mov     word [si+E_VX],SHELL_V          ; slide away from Mario
        mov     ax,[si+E_X]
        cmp     ax,[MarioXPix]
        jge     .kgo
        mov     word [si+E_VX],-SHELL_V
.kgo:   mov     byte [si+E_STATE],ES_SLIDE
        mov     byte [si+E_GRACE],8
        jmp     .out

.mush:  push    word 1000
        call    AddScore
        push    word 1
        push    word [si+E_X]
        push    dx
        push    word 1000
        call    SpawnEffect
        cmp     byte [Form],0
        jne     .mgone
        mov     byte [Form],1           ; Small -> Super, HP 2, feet fixed
        mov     byte [HP],2
        sub     word [MarioY],16*256
        jnc     .mgone
        mov     word [MarioY],0         ; FIX: clamp at the top of the screen
.mgone: mov     byte [si+E_TYPE],ET_NONE
.out:   popa
        pop     bp
        ret     2

; StompTest : AX = 1 when Mario is moving down and, in the previous frame, his
;             feet were above the upper half of the enemy (DX = enemy top).
StompTest:
        xor     ax,ax
        cmp     word [MarioVY],0
        jle     .r
        mov     ax,dx
        add     ax,8
        cmp     [PrevFeet],ax
        jle     .yes
        xor     ax,ax
        ret
.yes:   mov     ax,1
.r:     ret

; ResolveMario : runs ResolveOne for every entity (stop if the state changes).
ResolveMario:
        pusha
        mov     si,EntTbl
        mov     cx,ENT_MAX
.l:     cmp     byte [GameState],ST_PLAYING
        jne     .out
        cmp     byte [si+E_TYPE],ET_NONE
        je      .n
        push    si
        call    ResolveOne
.n:     add     si,ENT_SIZE
        loop    .l
.out:   popa
        ret

; -----------------------------------------------------------------------------
; ScanMarioTiles(mode)
; Purpose : looks at every tile covered by Mario's hit box.  mode 0: collect
;           coin tiles (+200, coins +1).  mode 1: report the flag pole.
; Outputs : AX = 1 (mode 1) when Mario overlaps a pole tile
; -----------------------------------------------------------------------------
ScanMarioTiles:
        push    bp
        mov     bp,sp
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        call    MarioHeight
        mov     si,ax
        mov     ax,[MarioY]
        shr     ax,8
        mov     dx,ax
        shr     ax,4
        mov     di,ax                   ; first row
        add     dx,si
        dec     dx
        shr     dx,4                    ; last row
        mov     ax,[MarioXPix]
        add     ax,2
        shr     ax,4
        mov     [TmpC0],ax              ; first column
        mov     cx,[MarioXPix]
        add     cx,13
        shr     cx,4                    ; last column
        mov     word [TmpFlag],0
        cmp     dx,MAP_ROWS-1           ; FIX: keep the scan inside the map
        jbe     .rok                    ;      (falling into a pit gave rows 12-13)
        mov     dx,MAP_ROWS-1
.rok:   cmp     cx,MAP_COLS-1
        jbe     .cok
        mov     cx,MAP_COLS-1
.cok:   cmp     di,dx
        ja      .fin                    ; no map row covered at all
        mov     ax,[TmpC0]
        cmp     ax,cx
        ja      .fin                    ; no map column covered at all
.r:     mov     si,[TmpC0]
.c:     mov     bx,di
        imul    bx,bx,MAP_COLS
        add     bx,si
        mov     al,[WorkMap+bx]
        cmp     word [bp+4],0
        jne     .fl
        cmp     al,T_COIN
        jne     .nx
        push    si
        push    di
        push    word T_SKY
        call    SetTile
        call    AddCoin
        push    word 200
        call    AddScore
        push    word 1
        mov     ax,si
        shl     ax,4
        push    ax
        mov     ax,di
        shl     ax,4
        push    ax
        push    word 200
        call    SpawnEffect
        jmp     .nx
.fl:    cmp     al,T_POLE
        jne     .nx
        mov     word [TmpFlag],1
.nx:    inc     si
        cmp     si,cx
        jle     .c
        inc     di
        cmp     di,dx
        jle     .r
.fin:   mov     ax,[TmpFlag]
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     bp
        ret     2

; =============================================================================
;  MODULE 15 : DEATH, WIN, RESTART
; =============================================================================

; -----------------------------------------------------------------------------
; StartDeath(kind)
; Purpose : Section 5.8 step 1-2: freeze the game and enter the DYING state.
;           kind 0 = pit (no upward hop), kind 1 = enemy / clock (hop up).
; Changes : none
; -----------------------------------------------------------------------------
StartDeath:
        push    bp
        mov     bp,sp
        mov     byte [GameState],ST_DYING
        mov     word [DeathTimer],45    ; about 1.5 s
        mov     word [MarioVX],0
        mov     word [MarioVY],0
        cmp     word [bp+4],0
        je      .pit
        mov     word [MarioVY],DEATH_HOP_V
.pit:   mov     byte [Pose],2
        mov     byte [OnGround],0
        pop     bp
        ret     2

; -----------------------------------------------------------------------------
; StartWin
; Purpose : Section 5.11 step 1: flag points by the height of contact (the map
;           row of Mario's feet), snap Mario to the pole, enter WINSEQ.
; Changes : none
; -----------------------------------------------------------------------------
StartWin:
        pusha
        call    MarioHeight
        mov     bx,[MarioY]
        shr     bx,8
        add     bx,ax
        dec     bx
        shr     bx,4                    ; row of the feet
        mov     ax,5000
        cmp     bx,3
        jbe     .pts
        mov     ax,2000
        cmp     bx,4
        je      .pts
        mov     ax,800
        cmp     bx,5
        je      .pts
        mov     ax,400
        cmp     bx,7
        jbe     .pts
        mov     ax,100
.pts:   push    ax
        call    AddScore
        mov     dx,bx
        shl     dx,4
        push    word 1
        push    word POLE_X+16
        push    dx
        push    ax
        call    SpawnEffect
        mov     byte [GameState],ST_WINSEQ
        mov     byte [WinPhase],0
        mov     word [WinTimer],0
        mov     word [MarioXPix],POLE_X-6
        mov     word [MarioXFr],0
        mov     word [MarioVX],0
        mov     word [MarioVY],0
        mov     byte [Facing],0
        mov     byte [Pose],0
        popa
        ret

; NewGame : score, coins, lives and everything else back to their start values.
NewGame:
        mov     word [ScoreLo],0
        mov     word [ScoreHi],0
        mov     byte [Coins],0
        mov     byte [Lives],START_LIVES
        call    ResetLevel
        ret

; -----------------------------------------------------------------------------
; ResetLevel
; Purpose : map (block move from the original), enemies, mushrooms, effects,
;           clock, camera and Mario go back to the start of the level.  Score,
;           coins and lives are NOT touched.
; Changes : none
; -----------------------------------------------------------------------------
ResetLevel:
        pusha
        push    es
        call    ResetMap
        mov     ax,cs
        mov     es,ax
        xor     bx,bx
        mov     bl,[CurLevel]
        shl     bx,1                    ; word index of the current level
        mov     si,[EntInitTbl+bx]
        mov     di,EntTbl
        mov     cx,ENT_MAX*ENT_SIZE/2
        cld
        rep     movsw                   ; enemies back to their start positions
        mov     di,EffTbl
        mov     cx,EFF_MAX*EFF_SIZE/2
        xor     ax,ax
        rep     stosw                   ; no effects
        mov     word [MarioXPix],MARIO_START_X
        mov     word [MarioXFr],0
        mov     word [MarioY],(GROUND_TOP_Y-16)*256
        mov     word [MarioVX],0
        mov     word [MarioVY],0
        mov     byte [Facing],0
        mov     byte [OnGround],1
        mov     byte [Form],0
        mov     byte [HP],1
        mov     byte [Pose],0
        mov     byte [HideMario],0
        mov     byte [StompChain],0
        mov     byte [JumpBuf],0
        mov     word [InvulnT],0
        mov     word [CamX],0
        mov     ax,[LevelTimeTbl+bx]
        mov     [Time],ax
        mov     ax,[GoombaSpdTbl+bx]
        mov     [GoombaSpd],ax
        mov     ax,[KoopaSpdTbl+bx]
        mov     [KoopaSpd],ax
        mov     word [ClockAcc],0
        pop     es
        popa
        ret

; UpdateTimers : clock (one unit per real second, from timer ticks) and the
;                invulnerability counter (Section 5.10, 5.7).
UpdateTimers:
        push    ax
        mov     ax,[TickDelta]
        add     [ClockAcc],ax
.l:     cmp     word [ClockAcc],TICKS_PER_SEC
        jb      .inv
        sub     word [ClockAcc],TICKS_PER_SEC
        cmp     word [Time],0
        je      .l
        dec     word [Time]
        jmp     .l
.inv:   cmp     word [InvulnT],0
        je      .r
        dec     word [InvulnT]
.r:     pop     ax
        ret

; CheckDeathAndFlag : step 7 of the frame order: pit, clock, flag pole.
CheckDeathAndFlag:
        push    ax
        mov     ax,[MarioY]
        shr     ax,8
        cmp     ax,192
        jb      .time
        push    word 0                  ; pit: no hop
        call    StartDeath
        jmp     .r
.time:  cmp     word [Time],0
        ja      .flag
        push    word 1                  ; clock reached 0
        call    StartDeath
        jmp     .r
.flag:  push    word 1
        call    ScanMarioTiles
        test    ax,ax
        jz      .r
        call    StartWin
.r:     pop     ax
        ret

; =============================================================================
;  RENDERING  (Module 5 frame buffer, Module 13 HUD)
; =============================================================================

; ClearFrame : fills the frame buffer with sky (REP STOSW) and the unused
;              bottom 8 rows with black.
ClearFrame:
        pusha
        push    es
        mov     es,[DrawSeg]
        xor     di,di
        mov     ax,(COL_SKY<<8)|COL_SKY
        mov     cx,192*SCREEN_W/2
        cld
        rep     stosw
        xor     ax,ax
        mov     cx,8*SCREEN_W/2
        rep     stosw
        pop     es
        popa
        ret

; FlipFrame : copies the frame buffer to video memory with one REP MOVSW.
FlipFrame:
        pusha
        push    ds
        push    es
        mov     ax,VGA_SEG
        mov     es,ax
        mov     ds,[FrameSeg]
        xor     si,si
        xor     di,di
        mov     cx,32000
        cld
        rep     movsw
        pop     es
        pop     ds
        popa
        ret

; DrawEntities : draws every active record that is on the screen.
DrawEntities:
        pusha
        mov     si,EntTbl
        mov     cx,ENT_MAX
.l:     mov     al,[si+E_TYPE]
        test    al,al
        jz      .n
        mov     bx,[si+E_X]
        sub     bx,[CamX]
        cmp     bx,-16
        jle     .n
        cmp     bx,SCREEN_W
        jge     .n
        mov     dx,[si+E_Y]
        shr     dx,8
        xor     di,di                   ; flags (mirror)
        cmp     al,ET_GOOMBA
        je      .goomba
        cmp     al,ET_KOOPA
        je      .koopa
        cmp     al,ET_SHELL
        je      .shell
        mov     ax,SprMushroom
        jmp     .draw
.goomba:mov     ax,SprGoomba
        cmp     byte [si+E_STATE],ES_FLAT
        jne     .gw
        mov     ax,SprGoombaFlat
        jmp     .draw
.gw:    test    byte [TickCount],8      ; walking animation: mirror every 8 ticks
        jz      .draw
        mov     di,1
        jmp     .draw
.koopa: mov     ax,SprKoopa
        cmp     word [si+E_VX],0
        jle     .draw
        mov     di,1
        jmp     .draw
.shell: mov     ax,SprShell
.draw:  push    cx
        push    bx
        push    dx
        push    ax
        push    word 16
        push    di
        call    DrawSprite
        pop     cx
.n:     add     si,ENT_SIZE
        loop    .l
        popa
        ret

; DrawMario : picks the sprite from form + pose, mirrors it by facing and
;             blinks (draws every other 2 frames) while invulnerable.
DrawMario:
        pusha
        cmp     byte [HideMario],0
        jne     .out
        cmp     word [InvulnT],0
        je      .draw
        test    byte [InvulnT],2
        jnz     .out
.draw:  xor     bx,bx
        mov     bl,[Pose]
        shl     bx,1
        mov     dx,16
        mov     ax,[MarioSmallTbl+bx]
        cmp     byte [Form],0
        je      .go
        mov     ax,[MarioSuperTbl+bx]
        mov     dx,32
.go:    xor     di,di
        cmp     byte [Facing],0
        je      .f
        mov     di,1
.f:     mov     bx,[MarioXPix]
        sub     bx,[CamX]
        push    bx
        mov     bx,[MarioY]
        shr     bx,8
        push    bx
        push    ax
        push    dx
        push    di
        call    DrawSprite
.out:   popa
        ret

; DrawHUD : black strip + SCORE, COINS, WORLD, TIME, LIVES, HEALTH (Section 5.14)
DrawHUD:
        pusha
        push    word 0
        push    word 0
        push    word SCREEN_W
        push    word 16
        push    word COL_BLACK
        call    FillRect
        ; labels (row 1), values (row 2)
        push    word 8
        push    word 0
        push    word StrScore
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        push    word 72
        push    word 0
        push    word StrCoins
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        push    word 120
        push    word 0
        push    word StrWorld
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        mov     bx,COL_YELLOW           ; "hurry" blink when the time is below 100
        cmp     word [Time],100
        jae     .t
        test    byte [TickCount],8
        jz      .t
        mov     bx,COL_RED
.t:     push    word 168
        push    word 0
        push    word StrTime
        push    bx
        push    word 1
        call    DrawString
        push    word 216
        push    word 0
        push    word StrLives
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        push    word 264
        push    word 0
        push    word StrHealth
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        ; values
        push    word 8
        push    word 8
        push    word [ScoreHi]
        push    word [ScoreLo]
        push    word 6
        push    word COL_WHITE
        call    DrawNumber
        push    word 72
        push    word 8
        push    word 'x'
        push    word COL_WHITE
        push    word 1
        call    DrawChar
        xor     ax,ax
        mov     al,[Coins]
        push    word 80
        push    word 8
        push    word 0
        push    ax
        push    word 2
        push    word COL_WHITE
        call    DrawNumber
        push    bx
        xor     bx,bx
        mov     bl,[CurLevel]
        shl     bx,1
        mov     bx,[WorldNoTbl+bx]      ; "1-1" or "1-2"
        push    word 120
        push    word 8
        push    bx
        push    word COL_WHITE
        push    word 1
        call    DrawString
        pop     bx
        push    word 168
        push    word 8
        push    word 0
        push    word [Time]
        push    word 3
        push    word COL_WHITE
        call    DrawNumber
        push    word 216
        push    word 8
        push    word 'x'
        push    word COL_WHITE
        push    word 1
        call    DrawChar
        xor     ax,ax
        mov     al,[Lives]
        push    word 224
        push    word 8
        push    word 0
        push    ax
        push    word 0
        push    word COL_WHITE
        call    DrawNumber
        ; hearts: first always filled; second filled only as Super Mario
        push    word 264
        push    word 8
        push    word HeartMask
        push    word COL_RED
        push    word 1
        call    DrawBits8
        mov     bx,COL_RED
        cmp     byte [HP],2
        jae     .h2
        mov     bx,COL_GRAY
.h2:    push    word 276
        push    word 8
        push    word HeartMask
        push    bx
        push    word 1
        call    DrawBits8
        popa
        ret

; RenderWorld : steps 9 of the frame order: clear, background, tiles, items,
;               enemies, Mario, effects, HUD.
RenderWorld:
        call    ClearFrame
        call    DrawBackground
        call    DrawMap
        call    DrawEntities
        call    DrawMario
        call    DrawEffects
        call    DrawHUD
%ifdef TESTMODE
        call    TestOverlay             ; test build only: numbers in the black bottom strip
%endif
        ret

; =============================================================================
;  MODULE 14 : GAME STATES, SCREENS AND MENUS
; =============================================================================

; GetKey : AL = next make code from the keyboard queue (0 if empty).
GetKey:
        push    bx
        xor     ax,ax
        mov     bl,[KeyHead]
        cmp     bl,[KeyTail]
        je      .r
        xor     bh,bh
        mov     al,[KeyQueue+bx]
        inc     bl
        and     bl,15
        mov     [KeyHead],bl
.r:     pop     bx
        ret

; FlushKeys : throws away every queued key press.
FlushKeys:
        push    ax
        mov     al,[KeyTail]
        mov     [KeyHead],al
        pop     ax
        ret

; WaitTick : step 1 of the frame: sleep until the timer interrupt has counted
;            at least one new tick; TickDelta = ticks since the last frame.
WaitTick:
        push    ax
        push    dx
.w:     mov     ax,[TickCount]
        cmp     ax,[LastTick]
        jne     .got
        sti
        hlt
        jmp     .w
.got:   mov     dx,ax
        sub     dx,[LastTick]
        cmp     dx,6
        jbe     .ok
        mov     dx,6                    ; never jump more than 6 ticks
.ok:    mov     [TickDelta],dx
        mov     [LastTick],ax
        pop     dx
        pop     ax
        ret

; ------------------------------------------------------------ TITLE (state 0)
HandleTitle:
        pusha
        cmp     byte [CurLevel],0
        je      .keys
        mov     byte [CurLevel],0       ; coming back from level 2: day palette again
        call    LoadLevel
.keys:  call    GetKey
        test    al,al
        jz      .draw
        cmp     al,SC_UP
        jne     .d
        mov     byte [TitleSel],0
        jmp     .keys
.d:     cmp     al,SC_DOWN
        jne     .e
        mov     byte [TitleSel],1
        jmp     .keys
.e:     cmp     al,SC_ESC
        jne     .en
        mov     byte [GameState],ST_EXIT
        jmp     .out
.en:    cmp     al,SC_ENTER
        jne     .keys
        cmp     byte [TitleSel],0
        jne     .quit
        call    NewGame
        call    FlushKeys
        mov     byte [GameState],ST_PLAYING
        jmp     .out
.quit:  mov     byte [GameState],ST_EXIT
        jmp     .out
.draw:  call    DrawTitleScreen
        call    FlipFrame
.out:   popa
        ret

; DrawTitleScreen : brick border, game name, START / EXIT box, team line.
DrawTitleScreen:
        pusha
        call    ClearFrame
        xor     si,si                   ; brick border, top and bottom rows
.bx:    mov     ax,si
        shl     ax,4
        push    ax
        push    word 0
        push    word TileBrick
        call    DrawTileOpaque
        push    ax
        push    word 176
        push    word TileBrick
        call    DrawTileOpaque
        inc     si
        cmp     si,20
        jb      .bx
        mov     si,1                    ; left and right columns
.by:    mov     ax,si
        shl     ax,4
        push    word 0
        push    ax
        push    word TileBrick
        call    DrawTileOpaque
        push    word 304
        push    ax
        push    word TileBrick
        call    DrawTileOpaque
        inc     si
        cmp     si,11
        jb      .by
        ; ground strip with Mario and a Goomba
        xor     si,si
.gr:    mov     ax,si
        shl     ax,4
        add     ax,16
        push    ax
        push    word 160
        push    word TileGround
        call    DrawTileOpaque
        inc     si
        cmp     si,18
        jb      .gr
        push    word 32
        push    word 144
        push    word SprMarioSmallStand
        push    word 16
        push    word 0
        call    DrawSprite
        push    word 272
        push    word 144
        push    word SprGoomba
        push    word 16
        push    word 1
        call    DrawSprite
        ; title text with a dark shadow
        push    word 31
        push    word 43
        push    word StrTitle
        push    word COL_DARK
        push    word 3
        call    DrawString
        push    word 28
        push    word 40
        push    word StrTitle
        push    word COL_RED
        push    word 3
        call    DrawString
        push    word 72
        push    word 76
        push    word StrEngine
        push    word COL_WHITE
        push    word 2
        call    DrawString
        ; menu box
        push    word 96
        push    word 104
        push    word 128
        push    word 44
        push    word COL_WHITE
        call    FillRect
        push    word 98
        push    word 106
        push    word 124
        push    word 40
        push    word COL_BLACK
        call    FillRect
        mov     bx,COL_YELLOW
        mov     dx,COL_WHITE
        cmp     byte [TitleSel],0
        je      .sel
        xchg    bx,dx
.sel:   push    word 112
        push    word 114
        push    word StrStart
        push    bx
        push    word 1
        call    DrawString
        push    word 112
        push    word 130
        push    word StrExit
        push    dx
        push    word 1
        call    DrawString
        mov     ax,114                  ; the > cursor
        cmp     byte [TitleSel],0
        je      .cur
        mov     ax,130
.cur:   push    word 104
        push    ax
        push    word '>'
        push    word COL_YELLOW
        push    word 1
        call    DrawChar
        push    word 166
        push    word StrTeam
        push    word COL_WHITE
        push    word 1
        call    DrawCentered
        popa
        ret

; ------------------------------------------------------------ PLAYING (state 1)
HandlePlaying:
        pusha
        ; ---- keys that are events: P, Esc and the two debug keys
.keys:  call    GetKey
        test    al,al
        jz      .upd
        cmp     al,SC_P
        jne     .esc
        mov     byte [GameState],ST_PAUSED
        jmp     .keys
.esc:   cmp     al,SC_ESC
        jne     .f1
        mov     byte [GameState],ST_TITLE
        call    FlushKeys
        jmp     .out
.f1:    cmp     al,SC_F1
        jne     .f2
        mov     word [Time],5           ; debug: clock = 5
        mov     word [ClockAcc],0
        jmp     .keys
.f2:    cmp     al,SC_F2
        jne     .f3
        mov     byte [Coins],99         ; debug: coins = 99
        jmp     .keys
.f3:    cmp     al,SC_F3
        jne     .keys
        xor     byte [CurLevel],1       ; debug: jump to the other level (1 <-> 2)
        call    LoadLevel               ; its map and palette
        call    ResetLevel              ; start of that level (score/coins/lives kept)
        jmp     .keys
.upd:   cmp     byte [GameState],ST_PLAYING
        jne     .out
        call    UpdateMario             ; step 3
        call    UpdateEntities          ; step 4
        call    ResolveMario            ; step 5
        cmp     byte [GameState],ST_PLAYING
        jne     .draw
        push    word 0
        call    ScanMarioTiles          ; collect coins
        call    UpdateTimers            ; step 6
        call    UpdateEffects
        call    CheckDeathAndFlag       ; step 7
        cmp     byte [GameState],ST_PLAYING
        jne     .draw
        call    UpdateCamera            ; step 8
.draw:  call    RenderWorld             ; step 9
        call    FlipFrame               ; step 10
.out:   popa
        ret

; ------------------------------------------------------------ PAUSED (state 2)
HandlePaused:
        pusha
.keys:  call    GetKey
        test    al,al
        jz      .draw
        cmp     al,SC_P
        jne     .esc
        mov     byte [GameState],ST_PLAYING
        call    FlushKeys
        jmp     .out
.esc:   cmp     al,SC_ESC
        jne     .keys
        mov     byte [GameState],ST_TITLE
        call    FlushKeys
        jmp     .out
.draw:  push    word 84                 ; the game picture stays; box on top
        push    word 68
        push    word 152
        push    word 56
        push    word COL_WHITE
        call    FillRect
        push    word 87
        push    word 71
        push    word 146
        push    word 50
        push    word COL_BLACK
        call    FillRect
        push    word 82
        push    word StrPaused
        push    word COL_YELLOW
        push    word 2
        call    DrawCentered
        push    word 106
        push    word StrResume
        push    word COL_WHITE
        push    word 1
        call    DrawCentered
        call    FlipFrame
.out:   popa
        ret

; ------------------------------------------------------------ DYING (state 3)
HandleDying:
        pusha
        call    FlushKeys               ; controls are disabled
        mov     ax,[MarioVY]
        add     ax,GRAVITY              ; falls with gravity, no collisions
        cmp     ax,FALL_MAX
        jle     .g
        mov     ax,FALL_MAX
.g:     mov     [MarioVY],ax
        test    ax,ax
        js      .dup
        add     [MarioY],ax
        jmp     .dok
.dup:   add     [MarioY],ax
        jc      .dok                    ; FIX: carry = still >= 0, no wrap
        mov     word [MarioY],0         ;      hop hit the top of the screen:
        mov     word [MarioVY],0        ;      stop rising and start falling
.dok:   mov     bx,[MarioY]
        shr     bx,8
        cmp     bx,230                  ; stay below the screen, never wrap
        jbe     .t
        cmp     word [MarioVY],0
        jl      .t
        mov     word [MarioY],230*256
.t:     call    UpdateEffects
        call    RenderWorld
        call    FlipFrame
        dec     word [DeathTimer]
        jnz     .out
        dec     byte [Lives]            ; Section 5.8 step 3
        jz      .over
        mov     word [LifeTimer],60     ; about 2 s
        mov     byte [GameState],ST_LIFELOST
        jmp     .out
.over:  mov     byte [GameState],ST_GAMEOVER
.out:   popa
        ret

; ------------------------------------------------------------ LIFE LOST (4)
HandleLifeLost:
        pusha
        call    FlushKeys
        push    word 0
        push    word 0
        push    word SCREEN_W
        push    word SCREEN_H
        push    word COL_BLACK
        call    FillRect
        xor     bx,bx
        mov     bl,[CurLevel]
        shl     bx,1
        mov     bx,[WorldBigTbl+bx]     ; "WORLD 1-1" or "WORLD 1-2"
        push    word 60
        push    bx
        push    word COL_WHITE
        push    word 3
        call    DrawCentered
        push    word 112
        push    word 104
        push    word SprMarioSmallStand
        push    word 16
        push    word 0
        call    DrawSprite
        push    word 152
        push    word 108
        push    word 'x'
        push    word COL_WHITE
        push    word 2
        call    DrawChar
        xor     ax,ax
        mov     al,[Lives]
        push    word 176
        push    word 108
        push    word 0
        push    ax
        push    word 0
        push    word COL_WHITE
        call    DrawNumber
        push    word 150
        push    word StrLivesLeft
        push    word COL_YELLOW
        push    word 2
        call    DrawCentered
        call    FlipFrame
        dec     word [LifeTimer]
        jnz     .out
        call    ResetLevel              ; restart the level (score and coins kept)
        mov     byte [GameState],ST_PLAYING
.out:   popa
        ret

; ------------------------------------------------------------ WIN SEQUENCE (5)
HandleWinSeq:
        pusha
        call    FlushKeys
        cmp     byte [WinPhase],0
        jne     .walk
        ; phase 0: slide down the pole, 3 px per frame, to the base block
        call    MarioHeight
        mov     bx,[MarioY]
        shr     bx,8
        add     bx,3
        mov     cx,9*16
        sub     cx,ax                   ; top when the feet touch the base block
        cmp     bx,cx
        jb      .slide
        mov     bx,cx
        mov     byte [WinPhase],1
        mov     word [WinTimer],0
.slide: shl     bx,8
        mov     [MarioY],bx
        jmp     .draw
.walk:  ; phase 1: hop down and walk to the castle door for about 1 second
        cmp     word [WinTimer],0
        jne     .w2
        call    MarioHeight
        mov     bx,GROUND_TOP_Y
        sub     bx,ax
        shl     bx,8
        mov     [MarioY],bx
        mov     word [MarioXPix],POLE_X+16
.w2:    add     word [MarioXPix],1
        mov     byte [Pose],1
        test    byte [TickCount],4
        jz      .w3
        mov     byte [Pose],0
.w3:    cmp     word [MarioXPix],POLE_X+38
        jb      .nh
        mov     byte [HideMario],1      ; he went through the castle door
.nh:    inc     word [WinTimer]
        cmp     word [WinTimer],40
        jb      .draw
        mov     byte [HideMario],1
        mov     ax,[Time]               ; Section 5.11 step 4: time bonus
        mov     bx,ax
        mov     cx,50
        mul     cx
        mov     [BonusPts],ax
        mov     ax,[ScoreLo]
        mov     [ScoreBefore],ax
        mov     ax,[ScoreHi]
        mov     [ScoreBeforeH],ax
        push    word [BonusPts]
        call    AddScore
        mov     byte [GameState],ST_LEVELCOMP
.draw:  call    UpdateEffects
        call    RenderWorld
        call    FlipFrame
        popa
        ret

; ------------------------------------------------------------ LEVEL COMPLETE (6)
HandleLevelComp:
        pusha
.keys:  call    GetKey
        test    al,al
        jz      .draw
        cmp     al,SC_ENTER
        jne     .keys
        cmp     byte [CurLevel],LAST_LEVEL
        jae     .title
        inc     byte [CurLevel]         ; next level: score, coins and lives are kept
        call    LoadLevel
        mov     word [LifeTimer],60     ; "WORLD 1-2" card, then ResetLevel + play
        mov     byte [GameState],ST_LIFELOST
        call    FlushKeys
        jmp     .out
.title: mov     byte [GameState],ST_TITLE
        call    FlushKeys
        jmp     .out
.draw:  push    word 0
        push    word 0
        push    word SCREEN_W
        push    word SCREEN_H
        push    word COL_BLACK
        call    FillRect
        push    word 32
        push    word 24
        push    word 256
        push    word 152
        push    word COL_YELLOW
        call    FillRect
        push    word 35
        push    word 27
        push    word 250
        push    word 146
        push    word COL_BLUE
        call    FillRect
        xor     bx,bx
        mov     bl,[CurLevel]
        shl     bx,1
        mov     bx,[LevelCompTbl+bx]    ; "LEVEL COMPLETE!" / "GAME COMPLETE!"
        push    word 36
        push    bx
        push    word COL_YELLOW
        push    word 2
        call    DrawCentered
        push    word 64
        push    word 68
        push    word StrScoreLbl
        push    word COL_WHITE
        push    word 1
        call    DrawString
        push    word 168
        push    word 68
        push    word [ScoreBeforeH]
        push    word [ScoreBefore]
        push    word 6
        push    word COL_WHITE
        call    DrawNumber
        push    word 64
        push    word 84
        push    word StrCoinsLbl
        push    word COL_WHITE
        push    word 1
        call    DrawString
        push    word 168
        push    word 84
        push    word 'x'
        push    word COL_WHITE
        push    word 1
        call    DrawChar
        xor     ax,ax
        mov     al,[Coins]
        push    word 176
        push    word 84
        push    word 0
        push    ax
        push    word 0
        push    word COL_WHITE
        call    DrawNumber
        push    word 64
        push    word 100
        push    word StrTimeLeft
        push    word COL_WHITE
        push    word 1
        call    DrawString
        push    word 168
        push    word 100
        push    word 0
        push    word [Time]
        push    word 0
        push    word COL_WHITE
        call    DrawNumber
        push    word 208
        push    word 100
        push    word StrX50
        push    word COL_WHITE
        push    word 1
        call    DrawString
        push    word 64
        push    word 116
        push    word StrBonus
        push    word COL_WHITE
        push    word 1
        call    DrawString
        push    word 168
        push    word 116
        push    word 0
        push    word [BonusPts]
        push    word 0
        push    word COL_WHITE
        call    DrawNumber
        push    word 64
        push    word 136
        push    word StrFinal
        push    word COL_WHITE
        push    word 1
        call    DrawString
        push    word 168
        push    word 136
        push    word [ScoreHi]
        push    word [ScoreLo]
        push    word 6
        push    word COL_YELLOW
        call    DrawNumber
        push    word 160
        push    word StrPressEnter
        push    word COL_LGREEN
        push    word 1
        call    DrawCentered
        call    FlipFrame
.out:   popa
        ret

; ------------------------------------------------------------ GAME OVER (7)
HandleGameOver:
        pusha
.keys:  call    GetKey
        test    al,al
        jz      .draw
        cmp     al,SC_ENTER
        jne     .keys
        mov     byte [GameState],ST_TITLE
        call    FlushKeys
        jmp     .out
.draw:  push    word 0
        push    word 0
        push    word SCREEN_W
        push    word SCREEN_H
        push    word COL_BLACK
        call    FillRect
        push    word 32
        push    word 24
        push    word 256
        push    word 152
        push    word COL_RED
        call    FillRect
        push    word 35
        push    word 27
        push    word 250
        push    word 146
        push    word COL_BLACK
        call    FillRect
        push    word 56
        push    word StrGameOver
        push    word COL_RED
        push    word 3
        call    DrawCentered
        push    word 100
        push    word 92
        push    word StrFinalScore
        push    word COL_WHITE
        push    word 1
        call    DrawString
        push    word 204
        push    word 92
        push    word [ScoreHi]
        push    word [ScoreLo]
        push    word 6
        push    word COL_WHITE
        call    DrawNumber
        push    word 100
        push    word 112
        push    word StrCoinsC
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        xor     ax,ax
        mov     al,[Coins]
        push    word 148
        push    word 112
        push    word 0
        push    ax
        push    word 0
        push    word COL_YELLOW
        call    DrawNumber
        push    word 180
        push    word 112
        push    word StrTimeC
        push    word COL_YELLOW
        push    word 1
        call    DrawString
        push    word 228
        push    word 112
        push    word 0
        push    word [Time]
        push    word 3
        push    word COL_YELLOW
        call    DrawNumber
        push    word 146
        push    word StrPressTitle
        push    word COL_LGREEN
        push    word 1
        call    DrawCentered
        call    FlipFrame
.out:   popa
        ret

; =============================================================================
;  MODULE 7 + 8 : KEYBOARD AND TIMER INTERRUPTS
; =============================================================================

; -----------------------------------------------------------------------------
; KbdISR  (INT 09h)
; Purpose : reads the scan code from port 60h, ignores the E0h prefix (and the
;           fake shift that follows it on NumLock keyboards), keeps the 128-byte
;           key-state table (1 = held), queues make codes and arms the jump
;           buffer; sends EOI and returns with IRET.
; -----------------------------------------------------------------------------
KbdISR:
        push    ax
        push    bx
        push    ds
        mov     ax,cs
        mov     ds,ax
        in      al,60h
        cmp     al,0E0h
        jne     .code
        mov     byte [ExtFlag],1        ; extended prefix: ignore it
        jmp     .eoi
.code:  mov     ah,[ExtFlag]
        mov     byte [ExtFlag],0
        mov     bl,al
        and     bl,7Fh
        test    ah,ah
        jz      .go
        cmp     bl,2Ah                  ; fake shift after E0 (NumLock) is ignored
        je      .eoi
        cmp     bl,36h
        je      .eoi
.go:    mov     [LastScan],bl           ; scan code without the release bit
        xor     bh,bh
        test    al,80h
        jnz     .release
        cmp     byte [KeyTbl+bx],0
        jne     .eoi                    ; auto-repeat: nothing new
        mov     byte [KeyTbl+bx],1
        cmp     bl,SC_SPACE
        jne     .q
        mov     byte [JumpBuf],6        ; jump request lives for 6 frames
.q:     mov     al,[KeyTail]            ; put the key into the ring queue
        mov     ah,al
        inc     ah
        and     ah,15
        cmp     ah,[KeyHead]
        je      .eoi                    ; queue full
        push    bx
        xor     bh,bh
        mov     bl,al
        mov     al,[LastScan]
        mov     [KeyQueue+bx],al
        pop     bx
        mov     [KeyTail],ah
        jmp     .eoi
.release:
        mov     byte [KeyTbl+bx],0
.eoi:   mov     al,20h                  ; end of interrupt
        out     20h,al
        pop     ds
        pop     bx
        pop     ax
        iret

; -----------------------------------------------------------------------------
; TimerISR  (INT 08h, programmed to 30 Hz)
; Purpose : counts ticks for the game loop and chains to the original BIOS
;           handler about 18.2 times per second so DOS time keeps running.
; -----------------------------------------------------------------------------
TimerISR:
        push    ax
        push    ds
        mov     ax,cs
        mov     ds,ax
        inc     word [TickCount]
        add     word [ChainAcc],91
        cmp     word [ChainAcc],150
        jb      .eoi
        sub     word [ChainAcc],150
        pop     ds
        pop     ax
        jmp     far [cs:OldInt08]       ; the BIOS handler sends the EOI and IRETs
.eoi:   mov     al,20h
        out     20h,al
        pop     ds
        pop     ax
        iret

; InstallHandlers : saves the old vectors (INT 21h AH=35h), installs ours
;                   (AH=25h) and reprograms the timer to 30 Hz.
InstallHandlers:
        pusha
        push    es
        mov     ax,3509h
        int     21h
        mov     [OldInt09],bx
        mov     [OldInt09+2],es
        mov     ax,3508h
        int     21h
        mov     [OldInt08],bx
        mov     [OldInt08+2],es
        cli
        mov     dx,KbdISR
        mov     ax,2509h
        int     21h
        mov     dx,TimerISR
        mov     ax,2508h
        int     21h
        mov     al,36h                  ; PIT channel 0, mode 3
        out     43h,al
        mov     ax,PIT_DIV
        out     40h,al
        mov     al,ah
        out     40h,al
        sti
        pop     es
        popa
        ret

; RestoreHandlers : puts back both vectors and the normal 18.2 Hz timer rate.
RestoreHandlers:
        pusha
        push    ds
        cli
        lds     dx,[OldInt09]
        mov     ax,2509h
        int     21h
        pop     ds
        push    ds
        lds     dx,[OldInt08]
        mov     ax,2508h
        int     21h
        pop     ds
        mov     al,36h
        out     43h,al
        xor     al,al                   ; divisor 0 = 65536 = 18.2 Hz
        out     40h,al
        out     40h,al
        sti
        popa
        ret

; =============================================================================
;  DATA  (constants first, then variables grouped by purpose)
; =============================================================================
MsgNoMem        db 'Not enough memory to run MARIO.COM',13,10,'$'
MsgTest         db 'MARIO COLOUR TEST - PRESS ANY KEY',0

; 16 colours, 6-bit VGA values (r,g,b): see the COL_xxx constants
Palette:        db  0, 0, 0,   23,37,63,   54,10, 0,   63,47,44     ; black sky red skin
                db 34,20, 5,   14, 6, 0,   63,63,63,    0,22,62     ; brown dark white blue
                db  0,42, 0,    0,22, 0,   63,38,14,   50,37,20     ; green dgreen orange tan
                db 63,54, 0,   47,47,47,   34,54, 0,   46,15, 3     ; yellow gray lgreen brick

; night palette: same colour numbers, moonlit blues and purples (level 2)
PaletteNight:   db  0, 0, 0,    3, 4,16,   56,12,10,   60,46,46     ; black navy-sky red skin
                db 26,15,18,    6, 4,12,   52,56,63,   10,24,63     ; brown dark moon-white blue
                db  3,20,26,    2,11,18,   60,36,12,   36,30,40     ; green dgreen orange tan
                db 63,58,16,   30,32,46,   14,42,40,   30,10,26     ; yellow gray lgreen brick

TileChars       db '.GB?ME[]()SoF'      ; character -> tile code (index = code)
TileAddr        dw 0, TileGround, TileBrick, TileQuestion, TileQuestion, TileEmpty
                dw TilePipeTL, TilePipeTR, TilePipeBL, TilePipeBR, TileStair, SprCoin, TilePole
MarioSmallTbl   dw SprMarioSmallStand, SprMarioSmallRun, SprMarioSmallJump
MarioSuperTbl   dw SprMarioSuperStand, SprMarioSuperRun, SprMarioSuperJump
ChainTbl        dw 100,200,400,500,800,1000,2000,4000,5000,8000   ; stomp chain
StateTable      dw HandleTitle, HandlePlaying, HandlePaused, HandleDying
                dw HandleLifeLost, HandleWinSeq, HandleLevelComp, HandleGameOver, HandleTitle
CloudX          dw 30,150,260,380,470,560
CloudY          dw 24,40,28,48,24,36
BushX           dw 48,352,540,760
StarX           dw 165,202,24,187,29,109,44,214,123,282,63,298,295,285,148,73,157,92,96,49,30,105,299,185,127,294,268,175
StarY           dw 39,103,29,94,84,24,75,28,31,74,48,27,94,37,73,89,91,33,67,90,99,83,78,58,43,58,83,113
StarCol         db COL_WHITE,COL_YELLOW,COL_WHITE,COL_GRAY      ; twinkle sequence
MoonHW          db 0,5,7,8,9,10,10,11,11,12,12,12,12,12,12,12,11,11,10,10,9,8,7,5,0
HillX           dw 0,110,230,340,460
TreeX           dw 56,120,344,408,568,608
; ---- per-level tables, indexed by CurLevel*2 (level 1 = day, level 2 = night)
PaletteTbl      dw Palette, PaletteNight
LevelTextTbl    dw LevelText, LevelText2
EntInitTbl      dw EntInit, EntInit2
LevelTimeTbl    dw START_TIME, 250                      ; level 2 is shorter
GoombaSpdTbl    dw GOOMBA_V, 00A0h                      ; level 2 enemies are faster
KoopaSpdTbl     dw KOOPA_V, 00E0h
WorldNoTbl      dw StrWorldNo, StrWorldNo2
WorldBigTbl     dw StrWorldBig, StrWorldBig2
LevelCompTbl    dw StrLevelComp, StrGameComp

StrScore        db 'SCORE',0
StrCoins        db 'COINS',0
StrWorld        db 'WORLD',0
StrTime         db 'TIME',0
StrLives        db 'LIVES',0
StrHealth       db 'HEALTH',0
StrWorldNo      db '1-1',0
StrWorldNo2     db '1-2',0
StrTitle        db 'SUPER MARIO',0
StrEngine       db 'E N G I N E',0
StrStart        db 'START GAME',0
StrExit         db 'EXIT',0
StrTeam         db 'GROUP|FatimaAnwar,Tehreem,FatimaAltaf',0
StrPaused       db 'PAUSED',0
StrResume       db 'Press P to resume',0
StrWorldBig     db 'WORLD 1-1',0
StrWorldBig2    db 'WORLD 1-2',0
StrGameComp     db 'GAME COMPLETE!',0
StrLivesLeft    db 'LIVES LEFT',0
StrLevelComp    db 'LEVEL COMPLETE!',0
StrScoreLbl     db 'SCORE',0
StrCoinsLbl     db 'COINS',0
StrTimeLeft     db 'TIME LEFT',0
StrX50          db ' x 50',0
StrBonus        db 'TIME BONUS',0
StrFinal        db 'FINAL SCORE',0
StrPressEnter   db 'Press ENTER to continue',0
StrGameOver     db 'GAME OVER',0
StrFinalScore   db 'Final Score:',0
StrCoinsC       db 'Coins:',0
StrTimeC        db 'Time:',0
StrPressTitle   db 'Press ENTER for the title',0

; ---- initial enemy table: 4 Goombas and 2 Koopas, 4 free slots (mushrooms)
%macro ENTITY 2                         ; type, map column
        db      %1, ES_WAIT             ; type, state
        dw      %2*TILE                 ; world x
        db      0, 0                    ; x fraction, kick grace
        dw      (GROUND_TOP_Y-16)*256   ; y (8.8)
        dw      0, 0, 0, 0              ; vx, vy, timer, aux
%endmacro
EntInit:        ENTITY ET_GOOMBA, 11
                ENTITY ET_GOOMBA, 19
                ENTITY ET_KOOPA,  25
                ENTITY ET_GOOMBA, 32
                ENTITY ET_KOOPA,  39
                ENTITY ET_GOOMBA, 44
                times (ENT_MAX-6)*ENT_SIZE db 0

; ---- level 2 (night): 7 enemies, 5 free slots.  Columns are on solid ground.
EntInit2:       ENTITY ET_GOOMBA, 11
                ENTITY ET_GOOMBA, 19
                ENTITY ET_KOOPA,  23
                ENTITY ET_GOOMBA, 34
                ENTITY ET_GOOMBA, 36
                ENTITY ET_KOOPA,  38
                ENTITY ET_GOOMBA, 42
                times (ENT_MAX-7)*ENT_SIZE db 0

; ---- artwork and level (generated by tools/make_assets.py)
%include "sprites.inc"
%include "level.inc"
; ---- level 2: 60 x 12 tiles, same characters as level.inc
; .=sky G=ground B=brick ?=coin block M=mushroom block E=empty [ ] ( )=pipe
; S=stair o=coin F=flag pole.  Pits are 3 to 6 tiles wide (a run jump clears 7).
LevelText2:
                db '............................................................'
                db '............................................................'
                db '........................................................F...'
                db '........................................................F...'
                db '........................................................F...'
                db '.....................................................S..F...'
                db '.......?BMB?.................oo.....................SS..F...'
                db '............................o..o....B?B.[]...oo....SSS..F...'
                db '.................[].....................()........SSSS..F...'
                db '.................().....................().......SSSSS..S...'
                db 'GGGGGGGGGGGG...GGGGGGGGGGGGG....GGGGGGGGGGGG...GGGGGGG..GGGG'
                db 'GGGGGGGGGGGG...GGGGGGGGGGGGG....GGGGGGGGGGGG...GGGGGGG..GGGG'
; ---- variables: video and memory
FrameSeg        dw 0                    ; segment of the 64000-byte frame buffer
DrawSeg         dw 0                    ; segment all drawing procedures write to
FontOff         dw 0                    ; ROM 8x8 font pointer
FontSeg         dw 0
CharBuf         times 8 db 0            ; copy of one glyph
; ---- variables: interrupts and keyboard
OldInt08        dd 0
OldInt09        dd 0
TickCount       dw 0                    ; incremented by TimerISR
LastTick        dw 0
TickDelta       dw 1
ChainAcc        dw 0
KeyTbl          times 128 db 0          ; 1 = key held
KeyQueue        times 16 db 0           ; ring queue of make codes
KeyHead         db 0
KeyTail         db 0
ExtFlag         db 0
LastScan        db 0
JumpBuf         db 0
; ---- variables: game state
GameState       db ST_TITLE
CurLevel        db 0                    ; 0 = level 1 (day), 1 = level 2 (night)
GoombaSpd       dw GOOMBA_V             ; set per level by ResetLevel
KoopaSpd        dw KOOPA_V
TitleSel        db 0
ScoreLo         dw 0
ScoreHi         dw 0
ScoreBefore     dw 0
ScoreBeforeH    dw 0
BonusPts        dw 0
Coins           db 0
Lives           db START_LIVES
Time            dw START_TIME
ClockAcc        dw 0
CamX            dw 0
DeathTimer      dw 0
LifeTimer       dw 0
WinPhase        db 0
WinTimer        dw 0
; ---- variables: hero
MarioXPix       dw MARIO_START_X
MarioXFr        dw 0
MarioY          dw 0
MarioVX         dw 0
MarioVY         dw 0
Facing          db 0
OnGround        db 1
Form            db 0                    ; 0 Small, 1 Super
HP              db 1
InvulnT         dw 0
StompChain      db 0
PrevFeet        dw 0
Pose            db 0
HideMario       db 0
; ---- scratch
TmpCol0         dw 0
TmpOffs         dw 0
TmpC0           dw 0
TmpFlag         dw 0
; ---- tables
EntTbl          times ENT_MAX*ENT_SIZE db 0
EffTbl          times EFF_MAX*EFF_SIZE db 0
OrigMap         times MAP_SIZE db 0     ; never changed after InitLevel
WorkMap         times MAP_SIZE db 0     ; changed by blocks and coins

%ifdef TESTMODE
%include "tests/testmode.inc"
%endif