;**********************************************************************
;                                                                     *
;    Filename:      hlock84b.asm                                      *
;    Date:          So last century...                                *
;    File Version:  1.00b                                             *
;                                                                     *
;    Author:        Orest Kulik                                       *
;                                                                     * 
;**********************************************************************
;                                                                     *
;    Notes:         hardware lock                                     *
;                   version b, PRNG usage                             *
;                                                                     *
;                                                                     *
;                                                                     *
;**********************************************************************
  list      p=16F84             ; list directive to define processor
  #include <p16F84.inc>         ; processor specific variable definitions
  __CONFIG   _CP_ON & _WDT_OFF & _PWRTE_ON & _XT_OSC

;***********************************************************************
; VARIABLE DEFINITIONS
;***********************************************************************
rand_hi    EQU     0x0C 
rand_lo    EQU     0x0D
txBuf    EQU  0x0E
rxBuf    EQU  0x0F
idx    EQU  0x10
startbyte  EQU  0x11
counter    EQU  0x12
; 18 bytes 0x13 - 0x24 for Rx/Tx buffer
; 8 bytes 0x25 - 0x2C for random seed & for random table
pass    EQU  0x2D  ; PRNG counter

;***********************************************************************
; MACRO DEFINITIONS
;***********************************************************************
page0  macro
  bcf  STATUS,RP0
  endm
page1  macro
  bsf  STATUS,RP0
  endm
prng  macro      ;  set counter and buffer address for reading 8 seed bytes
  movlw  d'8'    ;  load counter
  movwf  counter ;
  movlw  h'25'   ;  load with buffer address
  movwf  FSR     ;
  endm
#define  _TxOUT  PORTA,0
#define  _RxIN  PORTB,0
;***********************************************************************
  ORG     0x000   ;  processor reset vector
  clrf  INTCON    ;  disable interrupts
  goto    main    ;  go to the beginning of program

;***********************************************************************
; interrupt - read serial routine 1start-8data-1stop@14400bps
;***********************************************************************
  ORG     0x004      ;  interrupt vector location    
  bcf  INTCON,7      ; [1T]  disable all interrupts
  btfsc  _RxIN       ; [1/2T]is this realy start bit?
  goto   endint      ; [2T]
  movlw  d'29'       ; [1T]
  movwf  idx         ; [1T]
; [5T]
RxB_1  decfsz  idx,f ; [1/2T]
  goto  RxB_1        ; [2T]
  clrf  rxBuf        ; [1T]
  movlw  h'01'       ; [1T]
  movwf  txBuf       ; [1T]
  clrc      ; [1T]
RxS_2  bsf  txBuf,1  ; [1T]
; [5T+(28*3T+2T)+6T=96T] wait for 1 & 1/2 bit to sample next bit
  btfss  _RxIN       ; [1/2T]is it '1'
  bcf  txBuf,1       ; [1T]  no, it is '0'
  rrf  txBuf,f       ; [1T]
  rrf  rxBuf,f       ; [1T]
  skpnc      ; [1/2T]
  goto  RxS_4        ; [2T]
  movlw  d'17'       ; [1T]
  movwf  idx         ; [1T]
RxS_3  decfsz  idx,f ; [1/2T]
    goto  RxS_3      ; [2T]
  nop                ; [1T]
  nop                ; [1T]
  skpc               ; [1/2T]
  goto  RxS_2        ; [2T]
; [8T+(16*3T+2T)+4T=63T]
RxS_4  rrf  txBuf,w  ; [1T]
  movfw  rxBuf       ; [1T]
  bcf  INTCON,1      ; [1T] clear interrupt flag
  bsf  INTCON,7      ; [1T] enable all interrupts
  retfie             ; [2T]
; [4T] extra spent on finishing reading on error
endint  clrc         ; [1T]
  bcf  INTCON,1      ; [1T]  clear interrupt flag
  bsf  INTCON,7      ; [1T]  enable all interrupts
  retfie             ; [2T]  start bit is HI, exit - [11T] spent  
  
;***********************************************************************
; main code starts here at 0x40, first 64 bytes free (interrupt routine)
;***********************************************************************
main  org  0x40
  page1  
  movlw  b'10000000' ;  weak pull-ups disabled, set RB0/INT to falling edge int
  movwf  OPTION_REG
  clrf  TRISA    ;  PORTA,0 pin is output
  movlw  b'00000001' ;  PORTB,0 pin is input
  movwf  TRISB
  page0
  bsf  _TxOUT
  bsf  _RxIN
  prng
; set first byte to 0x55
  movlw  h'55'       ; set first byte for Tx - '0x55'
  movwf  0x13
  movlw  b'10010000' ;  set global and RB0/INT int flag
  movwf  INTCON
;***********************************************************************
; wait for initialization byte '0xff' from PC
loopin  btfss  STATUS,C
  goto  loopin
  xorlw  h'ff'
  skpnz
  goto  loopin2
  clrc
  goto  loopin
; send response byte '0xaa' to PC
loopin2  movlw  h'aa'
  call  Tx
; main loop
; read data for PRNG seed
; wait for '0xee' start byte
  clrc
  bcf  startbyte,0
ib  btfsc  STATUS,C  ; [1T]  loop for the first byte
  call  ibyte    ; [8/9T]8-0xee, 9-else
  btfss  startbyte,0  ; [1/2T]was the start byte read? '0xee'
  goto  ib    ; [2T]  no start byte -> loop
; read 8 bytes
seedrd  btfss  STATUS,C  ; [1T]
  goto  seedrd    ; [2T]
  movwf  INDF    ; [1T]
  incf  FSR,f    ; [1T]
  clrc      ; [1T]
  decfsz  counter,f  ; [1T]
  goto  seedrd    ; [2T]
; set counter and buffer address for reading 17 serial data bytes
  movlw  d'17'    ; [1T]  load counter
  movwf  counter    ; [1T]
  movlw  h'14'    ; [1T]  load with buffer address
  movwf  FSR    ; [1T]
  bcf  startbyte,0
; wait for '0x00' start byte
looprd  btfsc  STATUS,C  ; [1T]  loop for the first byte
  call  initby    ; [7/8T]7-0x00, 8-else
  btfss  startbyte,0  ; [1/2T]was the start byte read? '0x00'
  goto  looprd    ; [2T]  no start byte -> loop
; read 17 bytes
looprd2 btfss  STATUS,C  ; [1T]
  goto  looprd2    ; [2T]
  movwf  INDF    ; [1T]
  incf  FSR,f    ; [1T]
  clrc      ; [1T]
  decfsz  counter,f  ; [1T]
  goto  looprd2    ; [2T]
  bcf  INTCON,7  ;   disable interrupts while encoding and writing
;create 8 byte table from 8 seed bytes - spend ~8.44ms or 7779T
  prng
  clrc
tloop1  clrf  rand_hi    ; [1T]  hi=0x00
  movf  INDF,w    ; [1T]  if (lo==0x00)
  skpnz      ; [1/2T]  lo=0xff
  movlw  h'ff'    ; [1T]  else
  movwf  rand_lo    ; [1T]    lo = seed[i]
  movwf  pass    ; [1T]  pass = lo >> 3
  rrf  pass,f    ; [1T]
  rrf  pass,f    ; [1T]
  rrf  pass,w    ; [1T]
  andlw  b'00011111'  ; [1T]
  movwf  pass    ; [1T]
  skpnz
  goto  f1
tloop2  call  random    ; [2T]  for (i=0;i<pass;i++) MyRand()
  decfsz  pass,f    ; [1/2T]
  goto  tloop2    ; [2T]
f1  movf  rand_lo,w  ; [1T]  table[i]=lo
  movwf  INDF    ; [1T]
  incf  FSR,f    ; [1T]
  decfsz  counter,f  ; [1/2T]
  goto  tloop1    ; [2T]
; encode data
  movf  0x29,w    ;   table[i] = table[i] ^ table[i+4] i=0,1,2,3
  xorwf  0x25,f
  movf  0x2a,w
  xorwf  0x26,f
  movf  0x2b,w
  xorwf  0x27,f
  movf  0x2c,w
  xorwf  0x28,f
  movf  0x25,w    ;  txout[i] = txout[i] ^ table[i%4] 
  xorwf  0x14,f
  movf  0x26,w
  xorwf  0x15,f
  movf  0x27,w
  xorwf  0x16,f
  movf  0x28,w
  xorwf  0x17,f
  movf  0x25,w
  xorwf  0x18,f
  movf  0x26,w
  xorwf  0x19,f
  movf  0x27,w
  xorwf  0x1a,f
  movf  0x28,w
  xorwf  0x1b,f
  movf  0x25,w
  xorwf  0x1c,f
  movf  0x26,w
  xorwf  0x1d,f
  movf  0x27,w
  xorwf  0x1e,f
  movf  0x28,w
  xorwf  0x1f,f
  movf  0x25,w
  xorwf  0x20,f
  movf  0x26,w
  xorwf  0x21,f
  movf  0x27,w
  xorwf  0x22,f
  movf  0x28,w
  xorwf  0x23,f
  movf  0x25,w
  xorwf  0x24,f
; write 18 bytes
  movlw  d'18'    ;   load counter (1 start byte + 17 data bytes)
  movwf  counter    ;
  movlw  h'13'    ;  load with buffer address
  movwf  FSR    ;
loopwr  movf  INDF,w    ; [1T]
  call  Tx    ; [2T]
  incf  FSR,f    ; [1T]
  decfsz  counter,f  ; [1/2T]
  goto  loopwr    ; [2T]
  prng
  clrc
  bcf  startbyte,0
  bsf  INTCON,7  ;  enable interrupts
  goto  ib    ; [2T]

;***********************************************************************
; pseudo random number generator
;***********************************************************************
random  MOVF rand_hi, W         ; if current random is 0000, make it 00FFH
        IORWF rand_lo, W
        BTFSC STATUS, Z
        COMF rand_lo, F 
        BTFSS rand_hi, 6        ; hi.7 = hi.7 xor hi.6
        MOVLW 00H
        BTFSC rand_hi, 6
        MOVLW 80H
        XORWF rand_hi, F  
        BTFSS rand_hi, 4        ; hi.7 = hi.7 xor hi.4
        MOVLW 00H
        BTFSC rand_hi, 4
        MOVLW 80H
        XORWF rand_hi, F  
        BTFSS rand_lo, 3        ; hi.7 = hi.7 xor lo.3
        MOVLW 00H
        BTFSC rand_lo, 3
        MOVLW 80H
        XORWF rand_hi, F  
        RLF rand_hi, W          ; carry = hi.7
        RLF rand_lo, F          ; double left shift
        RLF rand_hi, F
        return
        
;***********************************************************************
; check for initial byte 0x00 routine
;***********************************************************************
initby  movf  rxBuf,f     ; [1T]
  skpz                    ; [1/2T] is it 0x00?
  goto  initby2           ; [2T] byte is not 0x00
  bsf  startbyte,0        ; [1T] byte is 0x00, set startbyte flag
  clrc                    ; [1T]
  return                  ; [2T]
initby2  bcf  startbyte,0 ; [1T] delete startbyte flag
  clrc                    ; [1T]
  return                  ; [2T]

;***********************************************************************
; check for initial byte 0xee routine
;***********************************************************************
ibyte  movlw  h'ee'       ; [1T]
  xorwf  rxBuf,w          ; [1T]
  skpz                    ; [1/2T] is it 0xee?
  goto  ibyte2            ; [2T] byte is not 0xee
  bsf  startbyte,0        ; [1T] byte is 0xee, set startbyte flag
  clrc                    ; [1T]
  return                  ; [2T]
ibyte2  bcf  startbyte,0  ; [1T] delete startbyte flag
  clrc                    ; [1T]
  return                  ; [2T]

;***********************************************************************
;  write serial routine 1start-8data-1stop@14400bps
;***********************************************************************
Tx  movwf  txBuf
  movlw  d'10'
  movwf  idx
  clrc
  goto  TxB_2
TxB_1  rrf  txBuf,f       ; [1T]
TxB_2  skpnc              ; [1/2T]
  goto  TxB_4             ; [2T]
  setc                    ; [1T]
; start counting clock ticks f=3.6864MHz
; 1 bit takes 64T
; [0T]
  bcf  _TxOUT             ; [1T]
  movlw  d'18'            ; [1T]
  movwf  rxBuf            ; [1T]
; [3T]
TxB_3  decfsz  rxBuf,f    ; [1/2T]
  goto  TxB_3             ; [2T]
; [56T]
  nop                     ; [1T]
  decfsz  idx,f           ; [1/2T]
  goto  TxB_1             ; [2T]
; [60T]
  return
TxB_4  bsf  _TxOUT        ; [1T]
  movlw  d'17'            ; [1T]
  movwf  rxBuf            ; [1T]
  nop                     ; [1T]
  goto  TxB_3             ; [2T]

  end                     ; directive 'end of program'