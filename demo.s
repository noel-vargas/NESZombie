
; Noel Andres Vargas Padilla 801-19-7297
PPUCTRL   = $2000
PPUSCROLL = $2005
PPUMASK   = $2001
PPUSTATUS = $2002
PPUADDR   = $2006
PPUDATA   = $2007
OAMADDR   = $2003
OAMDMA    = $4014
OAMDATA = $2004
sprite_buff_addr = $0200

CONTROLLER1 = $4016
CONTROLLER2 = $4017

BTN_RIGHT   = %00000001
BTN_LEFT    = %00000010
BTN_DOWN    = %00000100
BTN_UP      = %00001000
BTN_START   = %00010000
BTN_SELECT  = %00100000
BTN_B       = %01000000
BTN_A       = %10000000



.segment "HEADER"
  ; .byte "NES", $1A      ; iNES header identifier
  .byte $4E, $45, $53, $1A
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte $01, $00        ; mapper 0, vertical mirroring

.segment "VECTORS"
  ;; When an NMI happens (once per frame if enabled) the label nmi:
  .addr nmi
  ;; When the processor first turns on or is reset, it will jump to the label reset:
  .addr reset
  ;; External interrupt IRQ (unused)
  .addr 0

; "nes" linker config requires a STARTUP section, even if it's empty
.segment "STARTUP"

.segment "ZEROPAGE"
sprite_offset: .res 1
; Args for render_sprite subroutine
pos_x: .res 1
pos_y: .res 1
tile_num: .res 1

pad1: .res 1
player_dir: .res 1

nmi_counter: .res 1

; Main code segment for the program
.segment "CODE"

reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs		;  .
  inx		; now X = 0
  stx PPUCTRL	; disable NMI
  stx PPUMASK 	; disable rendering
  stx $4010 	; disable DMC IRQs

;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit PPUSTATUS
  bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory
  
;; second wait for vblank, PPU is ready after this
vblankwait2:
  bit PPUSTATUS
  bpl vblankwait2

main:
  clear_oam:
    ldx #0
    loop_clear_oam:
      lda #$FA ; load byte x of sprite list
      sta OAMDATA ; 
      inx
      cpx #255
      bne loop_clear_oam
      
  lda #$50
  sta pos_x
  sta pos_y
  lda #$02
  sta tile_num

  load_palettes:
    lda PPUSTATUS
    lda #$3f
    sta PPUADDR
    lda #$00
    sta PPUADDR

    ldx #$00
    @loop:
      lda palettes, x
      sta PPUDATA
      inx
      cpx #$20
      bne @loop

enable_rendering:
  lda #%10000000	; Enable NMI
  sta PPUCTRL
  lda #%00010110; Enable background and sprite rendering in PPUMASK.
  sta PPUMASK

forever:
  
  JSR read_controller1
  JSR update_player
  jmp forever

read_controller1:

  ; write a 1, then a 0, to CONTROLLER1
  ; to latch button states
  LDA #$01
  STA CONTROLLER1
  LDA #$00 
  STA CONTROLLER1

  LDA #%00000001
  STA pad1

get_buttons:
  LDA CONTROLLER1 ; Read next button's state
  LSR A           
  ROL pad1        ; Rotate button state from carry flag
                  ; onto right side of pad1
                  ; and leftmost 0 of pad1 into carry flag
  BCC get_buttons ; Continue until original "1" is in carry flag
  RTS

update_player:
  LDA pad1 ; load button presses
  AND #BTN_LEFT ; filter out all but left 
  BEQ check_right ; if result equals 0, left not pressed.
  DEC pos_x ; if it doesn't branch, move player left\
  LDA #1
  STA player_dir
  JMP done_checking

check_right:
  LDA pad1
  AND #BTN_RIGHT
  BEQ check_up
  INC pos_x
  LDA #2 ; set direction for right
  STA player_dir
check_up:
  LDA pad1
  AND #BTN_UP
  BEQ check_down
  lda #3 ; set direction for up
  STA player_dir
  DEC pos_y
check_down:
  LDA pad1
  AND #BTN_DOWN
  BEQ done_checking
  inc pos_y
  lda #4 ; set direction for down
  STA player_dir
  
done_checking:
  RTS
  ; testing
  ; lista de tiles en byte array
render_sprite:
  lda PPUSTATUS

  ; Write first tile of selected sprite
  ldx sprite_offset * direction +8
  ; First tile
  lda pos_y
  sta $0200,X 
  inx
  lda tile_num
  sta $0200,X
  inx
  lda #$00
  sta $0200,X
  inx
  lda pos_x
  sta $0200,X
  inx

  ; Second tile
  lda pos_y
  clc
  adc #8
  sta $0200,X
  inx
  lda tile_num
  clc
  adc #16
  sta $0200,X
  inx
  lda #$00
  sta $0200,X
  inx 
  lda pos_x
  sta $0200,X
  inx

  ; Third tile
  lda pos_y
  sta $0200,X
  inx
  lda tile_num
  clc
  adc #1
  sta $0200,X
  inx
  lda #$00
  sta $0200,X
  inx
  lda pos_x
  clc
  adc #8
  sta $0200,X
  inx

  ; Fourth tile
  lda pos_y
  clc
  adc #8
  sta $0200,X
  inx
  lda tile_num
  clc
  adc #17
  sta $0200,X
  inx
  lda #$00
  sta $0200,X
  inx
  lda pos_x
  clc
  adc #8
  sta $0200,X

  ; add 4 to address offset
  lda sprite_offset
  clc
  adc #4
  sta sprite_offset

  rts

nmi:
  lda #$00
  sta PPUSCROLL
  lda #$00
  sta PPUSCROLL

  LDA #$02
  STA OAMDMA
  JSR render_sprite

  ; inc nmi_counter ; Increment nmi_counter
  ; lda nmi_counter ; Load nmi_counter
  ; cmp #60 ; Compare nmi_counter to 60
  ; bne skip_reset_timer ; If nmi_counter is not 60, skip resetting it
  ;  ; If nmi_counter is 60, render sprite
  ; lda #$00 ; Reset nmi_counter to 0
  ; sta nmi_counter ; Store 0 in nmi_counter
  ; skip_reset_timer:
  rti

palettes:
; background palette
.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

; sprite palette
.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

sprites:
.byte $00, $02, $00, $00
.byte $00, $03, $00, $08
.byte $08, $12, $00, $00
.byte $08, $13, $00, $08

.byte $00, $04, $00, $10
.byte $00, $05, $00, $18
.byte $08, $14, $00, $10
.byte $08, $15, $00, $18

.byte $00, $06, $00, $20
.byte $00, $07, $00, $28
.byte $08, $16, $00, $20
.byte $08, $17, $00, $28

.byte $00, $08, $00, $30
.byte $00, $09, $00, $38
.byte $08, $18, $00, $30
.byte $08, $19, $00, $38

.byte $00, $22, $00, $40
.byte $00, $23, $00, $48
.byte $08, $32, $00, $40
.byte $08, $33, $00, $48

.byte $00, $24, $00, $50
.byte $00, $25, $00, $58
.byte $08, $34, $00, $50
.byte $08, $35, $00, $58

.byte $00, $26, $00, $60
.byte $00, $27, $00, $68
.byte $08, $36, $00, $60
.byte $08, $37, $00, $68

.byte $00, $28, $00, $70
.byte $00, $29, $00, $78
.byte $08, $38, $00, $70
.byte $08, $39, $00, $78

; Character memory
.segment "CHARS"
.incbin "tanks.chr"