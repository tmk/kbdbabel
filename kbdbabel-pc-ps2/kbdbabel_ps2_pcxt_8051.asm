; ---------------------------------------------------------------------
; AT/PS2 to PC/XT keyboard transcoder for 8051 type processors.
;
; $Id: kbdbabel_ps2_pcxt_8051.asm,v 1.1 2009/08/21 22:09:54 akurz Exp $
;
; Clock/Crystal: 24MHz.
;
; PC/XT Keyboard connect:
; This two pins need externals 4.7k resistors as pullup.
; DATA - p3.4   (Pin 14 on DIL40, Pin 8 on AT89C2051 PDIP20)
; CLOCK - p3.2  (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
;
; AT/PS2 Keyboard connect:
; This two pins need externals 4.7k resistors as pullup.
; DATA - p3.5	(Pin 14 on DIL40, Pin 8 on AT89C2051 PDIP20)
; CLOCK - p3.3	(Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
;
; LED-Output connect:
; LEDs are connected with 220R to Vcc
; PCXT Ring buffer full	- p1.7	(Pin 8 on DIL40, Pin 19 on AT89C2051 PDIP20)
; AT/PS2 RX error	- p1.6	(Pin 7 on DIL40, Pin 18 on AT89C2051 PDIP20)
; AT/PS2 RX Parity error- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; PS2 Ring buffer full	- p1.4	(Pin 5 on DIL40, Pin 16 on AT89C2051 PDIP20)
; 	- p1.3	(Pin 4 on DIL40, Pin 15 on AT89C2051 PDIP20)
; 	- p1.2	(Pin 3 on DIL40, Pin 14 on AT89C2051 PDIP20)
; 	- p1.1	(Pin 2 on DIL40, Pin 13 on AT89C2051 PDIP20)
; 	- p1.0	(Pin 1 on DIL40, Pin 12 on AT89C2051 PDIP20)
;
; Build:
; $ asl -L kbdbabel_ps2_pcxt_8051.asm -o kbdbabel_ps2_pcxt_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_ps2_pcxt_8051
; write kbdbabel_ps2_pcxt_8051.bin on an empty 27C256 or AT89C2051
;
; Copyright 2009 by Alexander Kurz
;
; This is free software.
; You may copy and redistibute this software according to the
; GNU general public license version 3 or any later version.
;
; ---------------------------------------------------------------------

	cpu 8052
	include	stddef51.inc
	include kbdbabel_intervals.inc

;----------------------------------------------------------
; Variables / Memory layout
;----------------------------------------------------------
;------------------ octets
B20		sfrb	20h	; bit adressable space
B21		sfrb	21h
B22		sfrb	22h
B23		sfrb	23h
KbBitBufL	sfrb	24h
KbBitBufH	sfrb	25h
;KbClockMin	equ	26h
;KbClockMax	equ	27h
PS2TXBitBuf	equ	28h
PS2ResendBuf	equ	29h
PCXTBitCount	equ	2ah
PCXTTXBuf	equ	2bh
RawBuf		equ	30h	; raw PC/XT scancode
PS2ResendTTL	equ	31h	; prevent resent-loop
TXBuf		equ	32h	; AT scancode TX buffer
RingBuf1PtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBuf1PtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
RingBuf2PtrIn	equ	35h	; Ring Buffer write pointer, starting with zero
RingBuf2PtrOut	equ	36h	; Ring Buffer read pointer, starting with zero
PS2RXLastBuf	equ	37h	; Last received scancode
PS2LedBuf	equ	38h	; LED state buffer for PS2 Keyboard

;------------------ bits
PS2RXBitF	bit	B20.0	; RX-bit-buffer
PS2RXCompleteF	bit	B20.1	; full and correct byte-received
PS2ActiveF	bit	B20.2	; PS2 RX or TX in progress flag
PS2HostToDevF	bit	B20.3	; host-to-device flag for Int0-handler
PS2RXBreakF	bit	B20.4	; AT/PS2 0xF0 Break scancode received
PS2RXEscapeF	bit	B20.5	; AT/PS2 0xE0 Escape scancode received
PS2TXAckF	bit	B20.6	; ACK-Bit on host-to-dev
PS2RXAckF	bit	B20.7	; ACK-Scancode received
MiscSleepF	bit	B21.0	; sleep timer active flag
TFModF		bit	B21.1	; Timer modifier: PS2 timeout or alarm clock
TimeoutF	bit	B21.2	; Timeout occured
PS2ResendF	bit	B21.3	; AT/PS2 resend
PCXTNextBitF	bit	B22.0	; Next PC/XT Data Bit to send
PCXTActiveF	bit	B22.1	; PCXT TX in progress flag
;------------------ arrays
RingBuf1		equ	40h	; Data for the host
RingBuf1SizeMask	equ	0fh	; 16 byte ring-buffer size
RingBuf2		equ	50h	; Data for the keyboard
RingBuf2SizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	60h	; the stack

;----------------------------------------------------------
; start
;----------------------------------------------------------
	org	0	; cold start
	ljmp	Start
;----------------------------------------------------------
; interrupt handlers
;----------------------------------------------------------
;----------------------------
; int 0, connected to keyboard clock line.
; With a raising signal on the clock line there are 15mus
; left to read the data line. Using a 3.6864 MHz Crystal
; this will be less than 5 processor cycles.
;----------------------------
	org	03h	; external interrupt 0
	reti
;	ljmp	HandleInt0
;----------------------------
	org	0bh	; handle TF0
	ljmp	HandleTF0
;----------------------------
	org	13h	; Int 1
	jnb	P3.5, HandleInt1	; this is time critical
	setb	PS2RXBitF
	ljmp	HandleInt1
;----------------------------
	org	1bh	; handle TF1
	ljmp	HandleTF1
;----------------------------
;	org	23h	; RI/TI
;	ljmp	HandleRITI
;----------------------------
;	org	2bh	; handle TF2
;	ljmp	HandleTF2

	org	033h

;----------------------------------------------------------
; timer 0 int handler:
;
; TFModF=0:
; timer is used to measure the clock-signal-interval length
; Stop the timer after overflow, cleanup RX buffers
; RX timeout after 1 - 1.3ms
;
; TFModF=1: delay timer
;----------------------------------------------------------
HandleTF0:
	; stop timer
	clr	tr0

	jb	TFModF,timerAsClockTimer

	; --- timer used for AT/PS2 bus timeout
	; buzzeroff
;	clr	p3.7
	; cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	PS2ActiveF	; receive in progress flag
	clr	PS2HostToDevF
	setb	TimeoutF

	; reset timer value
	mov	th0, #interval_th_11_bit
	mov	tl0, #interval_tl_11_bit

;	setb	p3.5	; data
;	setb	p3.3	; clock

	sjmp	HandleTF0End

timerAsClockTimer:
	; --- timer used to generate delays
	setb	MiscSleepF
	clr	TFModF

HandleTF0End:
	reti

;----------------------------------------------------------
; int1 handler:
; read one AT/PS2 data bit triggered by the keyboard clock line
; rotate bit into KbBitBufH, KbBitBufL.
; Last clock sample interval is stored in r6
; rotate bit into 22h, 23h.
; Num Bits is in r7
;
; TX:
; Byte to sent is read from PS2TXBitBuf
; ACK result is stored in PS2TXAckF. 0 is ACK, 1 is NACK.
;----------------------------------------------------------
HandleInt1:
	push	acc
	push	psw
	clr	p1.0

	; receive in progress flag
	setb	PS2ActiveF

; -- reset timeout timer
	; stop timer 0
	clr	tr0

	; reset timer value
	mov	th0, #interval_th_11_bit
	mov	tl0, #interval_tl_11_bit

	; start timer 0
	setb	tr0

; -- check for RX/TX
	jb	PS2HostToDevF,Int1PS2TX

; --------------------------- AT/PS2 RX: get and save data samples
; -- write to mem, first 8 bits
	mov	c,PS2RXBitF	; new bit
	mov	a,KbBitBufL
	rrc	a
	mov	KbBitBufL,a

; -- write to mem, upper bits
	mov	a,KbBitBufH
	rrc	a
	mov	KbBitBufH,a

; -- diag: write byte count or data bits to LED-Port
;	mov	a,r7
;	mov	a,KbBitBufL
;	xrl	a,0FFh
;	mov	p1,a

; -- reset bit buffer
	clr	PS2RXBitF

; --------------------------- consistancy checks
; -- checks by bit number
	mov	a,r7
	jnz	Int1NotStartBit	; start bit
Int1NotStartBit:
	clr	c
	subb	a,#0ah
	jz	Int1LastBit

; -- inc the bit counter
	inc	r7
	ljmp	Int1Return

; -- special handling for last bit: output
Int1LastBit:
	; start-bit must be 0
	jb	KbBitBufH.5, Int1Error
	; stop-bit must be 1
	jnb	KbBitBufL.7, Int1Error
	; error LED off
	setb	p1.5
	setb	p1.6

	; -- rotate back 2x
	mov	a,KbBitBufH
	rlc	a
	mov	KbBitBufH,a
	mov	a,KbBitBufL
	rlc	a
	mov	KbBitBufL,a

	mov	a,KbBitBufH
	rlc	a
	mov	KbBitBufH,a
	mov	a,KbBitBufL
	rlc	a
	mov	KbBitBufL,a

	; -- check parity
	jb	p,Int1RXParityBitPar
	jnc	Int1ParityError
	sjmp	Int1Output

Int1RXParityBitPar:
	jc	Int1ParityError

Int1Output:
	; -- return received byte
	mov	a, KbBitBufL
	mov	RawBuf, a
	mov	r7,#0
	setb	PS2RXCompleteF	; fully received flag
	clr	PS2ActiveF	; receive in progress flag

;	; --- write to LED
;	xrl	a,0FFh
;	mov	p1,a

	sjmp	Int1Return

Int1ParityError:
; -- cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	p1.5
	sjmp	Int1Return

Int1Error:
; -- cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	p1.6
	sjmp	Int1Return

; --------------------------- AT/PS2 TX
Int1PS2TX:
;	clr	p1.4
	; -- reset RX bit buffer
	clr	PS2RXBitF
	setb	PS2TXAckF
;	setb	p1.5
; -- checks by bit number
	mov	a,r7
	jz	Int1PS2TXStart
	clr	c
	subb	a,#09h
	jc	Int1PS2TXData
	jz	Int1PS2TXPar
	dec	a
	jz	Int1PS2TXStop

	; --- the last bit. read ACK-bit
	mov	c,p3.5
	mov	PS2TXAckF,c
;	mov	p1.5,c

	; --- reset data and clock
	mov	r7,#0h
	clr	p3.3		; pull down clock
	setb	p3.5		; data
	clr	PS2ActiveF	; receive in progress flag
	clr	PS2HostToDevF
	sjmp	Int1Return

Int1PS2TXStart:
	; --- set start bit
	clr	p3.5
	sjmp	Int1PS2TXReturn

Int1PS2TXData
	; --- set data bit
	mov	a,PS2TXBitBuf
	mov	c,acc.0
	mov	p3.5,c
	rr	a
	mov	PS2TXBitBuf,a
	sjmp	Int1PS2TXReturn

Int1PS2TXPar:
	; --- set parity bit
	mov	a,PS2TXBitBuf
	mov	c,p
	cpl	c
	mov	p3.5,c
	sjmp	Int1PS2TXReturn

Int1PS2TXStop:
	; --- set stop bit
	setb	p3.5
	sjmp	Int1PS2TXReturn

Int1PS2TXReturn:
; -- inc the bit counter
	inc	r7
;	sjmp	Int1Return

; --------------------------- done
Int1Return:
	setb	p1.0
	pop	psw
	pop	acc
	reti

;----------------------------------------------------------
; timer 1 int handler: PC/XT transmitter
;----------------------------------------------------------
HandleTF1:
; --------------------------- PC/XT clock driver, TX only
	push	acc			; 2,4
	push	psw			; 2,6

; --------------------------- device-to-host communication
; -- switch on bit-number
; -----------------
	mov	dptr,#timer1PCXTJT		; 2,8
	mov	a,PCXTBitCount			; 1,9
	add	a,PCXTBitCount			; 1,10
	jmp	@a+dptr				; 2,12

timer1PCXTJT:
	sjmp	timer1TXStart1Bit		; 2,14
	sjmp	timer1TXEnd
	sjmp	timer1TXStart2Bit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXDataBit
	sjmp	timer1TXRelease
	sjmp	timer1TXStopBit
	sjmp	timer1TXRelease
	sjmp	timer1TXStop

; -----------------
timer1TXRelease:
; -- output of the data bit
	; note:	PCXTNextBitF is computed in the previous step due to timing issues
	; 	low-delay-output is important here
	; data bit output
	mov	c,PCXTNextBitF
	mov	p3.4,c
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	; set clock line
	setb	p3.2
	sjmp	timer1TXEnd

; -----------------
timer1TXStart1Bit:
	clr	p3.2
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	setb	p3.4
	sjmp	timer1TXEnd

; -----------------
timer1TXStart2Bit:
	setb	PCXTNextBitF		; 1
	nop
	nop
	nop
	nop
	call	nop20
	clr	p3.2
	sjmp	timer1TXEnd

; -----------------
timer1TXDataBit:
; -- set data bit 0-7 and pull down clock line
	mov	a,PCXTTXBuf		; 1
	rrc	a			; 1	; next data bit to c
	mov	PCXTNextBitF,c		; 2
	mov	PCXTTXBuf,a		; 1
	call	nop20
	clr	p3.2
	sjmp	timer1TXEnd

; -----------------
timer1TXStopBit:
	clr	PCXTNextBitF
	nop
	nop
	nop
	nop
	call	nop20
	clr	p3.2
	sjmp	timer1TXEnd

; -----------------
timer1TXStop:
; -- stop timer auto-reload
	clr	tr1
	clr	PCXTActiveF
	setb	p3.5
	setb	p3.3			; release PS2-Clock to allow PS2-Communication
;	sjmp	timer1TXEnd

; --------------------------- done
timer1TXEnd:
; -- done
	inc	PCXTBitCount		; 1
	pop	psw			; 2
	pop	acc			; 2
	reti				; 2

;----------------------------------------------------------
; AT/PS2 to PC/XT translaton table
;----------------------------------------------------------
ATPS22PCXTxlt0	DB	  0h,  43h,   0h,  3fh,  3dh,  3bh,  3ch,  58h,    0h,  44h,  42h,  40h,  3eh,  0fh,   0h,   0h
ATPS22PCXTxlt1	DB	  0h,  38h,  2ah,   0h,  1dh,  10h,  02h,   0h,    0h,   0h,  2ch,  1fh,  1eh,  11h,  03h,   0h
ATPS22PCXTxlt2	DB	  0h,  2eh,  2dh,  20h,  12h,  05h,  04h,   0h,    0h,  39h,  2fh,  21h,  14h,  13h,  06h,   0h
ATPS22PCXTxlt3	DB	  0h,  31h,  30h,  23h,  22h,  15h,  07h,   0h,    0h,   0h,  32h,  24h,  16h,  08h,  09h,   0h
ATPS22PCXTxlt4	DB	  0h,  33h,  25h,  17h,  18h,  0bh,  0ah,   0h,    0h,  34h,  35h,  26h,  27h,  19h,  0ch,   0h
ATPS22PCXTxlt5	DB	  0h,   0h,  28h,   0h,  1ah,  0dh,   0h,   0h,   3ah,  36h,  1ch,  1bh,   0h,  29h,   0h,   0h
ATPS22PCXTxlt6	DB	  0h,  2bh,   0h,   0h,   0h,   0h,  0eh,   0h,    0h,  4fh,   0h,  4bh,  47h,   0h,   0h,   0h
ATPS22PCXTxlt7	DB	 52h,  53h,  50h,  4ch,  4dh,  48h,  01h,  45h,   57h,  4eh,  51h,  4ah,   0h,  49h,  46h,   0h
ATPS22PCXTxlt8	DB	  0h,   0h,   0h,  41h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxlt9	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxlta	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltb	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltc	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltd	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxlte	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltf	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

;----------------------------------------------------------
; AT/PS2 to PC/XT translaton table for 0xE0-Escaped scancodes
; Note: Ctrl-R (E014h) is mapped like Ctrl-L (14h)
;----------------------------------------------------------
ATPS22PCXTxltE0	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltE1	DB	  0h,  38h,   0h,   0h,  1dh,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltE2	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltE3	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltE4	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltE5	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,  1ch,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltE6	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,  4fh,   0h,  4bh,  47h,   0h,   0h,   0h
ATPS22PCXTxltE7	DB	 52h,  53h,  50h,   0h,  4dh,  48h,   0h,   0h,    0h,   0h,  51h,   0h,  37h,  49h,   0h,   0h
ATPS22PCXTxltE8	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltE9	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltEa	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltEb	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltEc	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltEd	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltEe	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
ATPS22PCXTxltEf	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

;----------------------------------------------------------
; Helper, translate normal AT/PS2 to PCXT scancode
; input: dptr: table address, a: AT/PS2 scancode
;----------------------------------------------------------
ATPS22PCXT:
	jb	PS2RXEscapeF,ATPS22PCXTEsc

; --- normal single scancodes
	mov	dptr,#ATPS22PCXTxlt0
	movc	a,@a+dptr
	sjmp	ATPS22PCXTEnd

; --- 0xE0-escaped scancodes
ATPS22PCXTEsc:
	clr	PS2RXEscapeF
	mov	dptr,#ATPS22PCXTxltE0
	movc	a,@a+dptr
;	sjmp	ATPS22PCXTEnd

ATPS22PCXTEnd:
	ret

;----------------------------------------------------------
; ring buffer insertion helper. Input Data comes in r2
;----------------------------------------------------------
RingBuf1CheckInsert:
	; check for ring buffer overflow
	mov	a,RingBuf1PtrOut
	setb	c
	subb	a,RingBuf1PtrIn
	anl	a,#RingBuf1SizeMask
	jz	RingBuf1Full

	; some space left, insert data
	mov	a,RingBuf1PtrIn
	add	a,#RingBuf1
	mov	r0,a
	mov	a,r2
	mov	@r0,a

	; increment pointer
	inc	RingBuf1PtrIn
	anl	RingBuf1PtrIn,#RingBuf1SizeMask
	ret

RingBuf1Full:
	; error routine
	clr	p1.7
	ret

;----------------------------------------------------------
; ring buffer insertion helper. Input Data comes in r2
;----------------------------------------------------------
RingBuf2CheckInsert:
	; check for ring buffer overflow
	mov	a,RingBuf2PtrOut
	setb	c
	subb	a,RingBuf2PtrIn
	anl	a,#RingBuf2SizeMask
	jz	RingBuf2Full

	; some space left, insert data
	mov	a,RingBuf2PtrIn
	add	a,#RingBuf2
	mov	r0,a
	mov	a,r2
	mov	@r0,a

	; increment pointer
	inc	RingBuf2PtrIn
	anl	RingBuf2PtrIn,#RingBuf2SizeMask
	ret

RingBuf2Full:
	; error routine
	clr	p1.4
	ret

;----------------------------------------------------------
; Get received data and translate it into the ring buffer
;----------------------------------------------------------
TranslateToBuf:
	mov	a,RawBuf
	; --- check for 0xFA ACK-Code
	cjne	a,#0FAh,TranslateToBufNotFA	;
	clr	PS2RXCompleteF
	setb	PS2RXAckF
	ljmp	TranslateToBufEnd
TranslateToBufNotFA:
	; --- check for 0xFE Resend-Code
	cjne	a,#0FEh,TranslateToBufNotFE	;
	clr	PS2RXCompleteF
	setb	PS2ResendF
	ljmp	TranslateToBufEnd
TranslateToBufNotFE:
	; ------ check for Escape codes
	; --- check for 0xF0 release / break code
	cjne	a,#0F0h,TranslateToBufNotF0	;
	clr	PS2RXCompleteF
	setb	PS2RXBreakF
	ljmp	TranslateToBufEnd
TranslateToBufNotF0:
	; --- check for 0xE0 ESC code
	cjne	a,#0E0h,TranslateToBufNotE0	; esc code
	clr	PS2RXCompleteF
	setb	PS2RXEscapeF
	ljmp	TranslateToBufEnd
TranslateToBufNotE0:

	; --- restore new scancode
	mov	a,RawBuf

	; keyboard disabled?
;	jb	FooBarDisableF,TranslateToBufEnd

	; --- translate
	clr	PS2RXCompleteF
	call	ATPS22PCXT

	; --- dont insert zeros
	jz	TranslateToBufClrEnd

	; --- insert
TranslateToBufInsert:
	; restore make/break bit 7
	mov	c,PS2RXBreakF
	mov	acc.7,c
	clr	c

	; insert into buf
	mov	r2, a
	call	RingBuf1CheckInsert

TranslateToBufClrEnd:
	clr	PS2RXBreakF
	clr	PS2RXEscapeF

TranslateToBufEnd:
	ret

;----------------------------------------------------------
; Send data from the ring buffer
;----------------------------------------------------------
	; -- send ring buffer contents
Buf1TX:
	; -- check if AT/PS2 bus or PCXT-transmit is active
	jb	PS2ActiveF,Buf1TXEnd
	jb	PCXTActiveF,Buf1TXEnd

	; check if data is present in the ring buffer
	clr	c
	mov	a,RingBuf1PtrIn
	subb	a,RingBuf1PtrOut
	anl	a,#RingBuf1SizeMask
	jz	Buf1TXEnd

	; -- get data from buffer
	mov	a,RingBuf1PtrOut
	add	a,#RingBuf1
	mov	r0,a
	mov	a,@r0

	; -- send data
	setb	p3.5
	clr	p3.3			; pull down PS2-Clock to inhibit PS2-Communication
	mov	PCXTBitCount,#0
	mov	PCXTTXBuf,a		; 8 data bits
	call	timer1_init_45mus

	; -- increment output pointer
	inc	RingBuf1PtrOut
	anl	RingBuf1PtrOut,#RingBuf1SizeMask

Buf1TXEnd:
	ret

;----------------------------------------------------------
; Send data from the ring buffer to the keyboard
;----------------------------------------------------------
Buf2TX:
	; -- check if AT/PS2 bus is active
	jb	PS2ActiveF,Buf2TXEnd

	; -- allow Device-to-Host communication
	jnb	TimeoutF,Buf2TXEnd

;	; -- check for resend-flag
;	jnb	PS2ResendF,Buf2TXNoResend
;	dec	PS2ResendTTL
;	mov	a,PS2ResendTTL
;	jnz	Buf2TXGo
;
;	; -- Resend-TTL expired, reset the keyboard, FIXME
;	mov	RingBuf2PtrIn,#0
;	mov	RingBuf2PtrOut,#0
;	mov	PS2ResendBuf,#0ffh
;	sjmp	Buf2TXGo

	; -- check if data is present in the ring buffer
Buf2TXNoResend:
	mov	PS2ResendTTL,#08h
	clr	c
	mov	a,RingBuf2PtrIn
	subb	a,RingBuf2PtrOut
	anl	a,#RingBuf2SizeMask
	jz	Buf2TXEnd

Buf2TXGo:
	; -- check if AT/PS2 bus is active
	jb	PS2ActiveF,Buf2TXEnd

	; -- init the bus
	clr	tr0
	clr	ex0		; may diable input interrupt here
	clr	p3.3		; clock down

	; -- wait 40mus
	call	timer0_init_40mus
Buf2TXWait1:
	jnb	MiscSleepF,Buf2TXWait1
	clr	p3.5		; data down

	; -- wait 40mus
	call	timer0_init_40mus
Buf2TXWait2:
	jnb	MiscSleepF,Buf2TXWait2

	; -- timeout timer
	call	timer0_init

;	jb	PS2ResendF,Buf2TXResend
	; -- get data from buffer
	mov	a,RingBuf2PtrOut
	add	a,#RingBuf2
	mov	r0,a
	mov	a,@r0
	mov	PS2TXBitBuf,a
	mov	PS2ResendBuf,a
	sjmp	Buf2TXSend

;Buf2TXResend:
;	; -- resend last byte
;	clr	PS2ResendF
;	mov	a,PS2ResendBuf
;	mov	PS2TXBitBuf,a

Buf2TXSend:
	; -- init int handler
	mov	r7,#0
	setb	PS2HostToDevF
	setb	ex0
	setb	p3.3		; clock up
	; -- keyboard should start sending clocks now
Buf2TXWait3:
	jb	PS2HostToDevF,Buf2TXWait3
	setb	p3.5		; data up

	; -- wait 1ms
	call	timer0_init_1ms
;	call	timer0_init_40mus
Buf2TXWait4:
	jnb	MiscSleepF,Buf2TXWait4
	setb	p3.3		; clock up

	; -- output to LED
;	mov	a,PS2TXBitBuf
;	cpl	a
;	mov	p1,a

	; -- increment output pointer
	inc	RingBuf2PtrOut
	anl	RingBuf2PtrOut,#RingBuf2SizeMask

	; -- restore normal timeout
	call	timer0_init
	setb	tr0
	setb	ex0		; may diable input interrupt here

Buf2TXEnd:
	ret

;----------------------------------------------------------
; helper, waste 20 cpu cycles
; note: call and return takes 4 cycles
;----------------------------------------------------------
nop20:
	nop
	nop
	nop
	nop
	nop
	nop

	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

	ret

;----------------------------------------------------------
; init timer 0 for AT/PS2 interval timing, timeout=1ms
;----------------------------------------------------------
timer0_init:
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit

	mov	th0, #interval_th_11_bit
	mov	tl0, #interval_tl_11_bit

	clr	TimeoutF
	clr	TFModF
	setb	et0		; (IE.3) enable timer 0 interrupt
	setb	tr0		; timer 0 run
	ret

;----------------------------------------------------------
; init timer 0 for interval timing
; need 40-50mus intervals
;----------------------------------------------------------
timer0_init_40mus:
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit

	mov	th0, #interval_th_40u_24M
	mov	tl0, #interval_tl_40u_24M

	setb	TFModF
	clr	MiscSleepF
	setb	et0		; (IE.3) enable timer 0 interrupt
	setb	tr0		; timer 0 run
	ret

;----------------------------------------------------------
; init timer 0 for interval timing
; need 1ms
;----------------------------------------------------------
timer0_init_1ms:
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit

	mov	th0, #interval_th_1m_24M
	mov	tl0, #interval_tl_1m_24M

	setb	TFModF
	clr	MiscSleepF
	setb	et0		; (IE.3) enable timer 0 interrupt
	setb	tr0		; timer 0 run
	ret

;----------------------------------------------------------
; init timer 1 for PC/XT for interval timing with 2*45mus
;----------------------------------------------------------
timer1_init_45mus:
	anl	tmod, #0fh	; clear all lower bits
	orl	tmod, #20h	; 8-bit Auto-Reload Timer, mode 2

	mov	th1, #interval_t0_45u_24M
	mov	tl1, #interval_t0_45u_24M

	setb	PCXTActiveF

	setb	et1		; (IE.3) enable timer 1 interrupt
	setb	tr1		; timer 1 run
	ret

;----------------------------------------------------------
; Id
;----------------------------------------------------------
RCSId	DB	"$KbdBabel: kbdbabel_ps2_pcxt_8051.asm,v 1.4 2009/03/31 09:48:25 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom
	; -- init UART and timer0/1
	acall	timer0_init
	clr	TFModF

	; -- enable interrupts int0
	setb	ex1		; external interupt 1 enable
	setb	it1		; falling edge trigger for int 1
	setb	ea

	; -- clear all flags
	mov	B20,#0
	mov	B21,#0
	mov	B22,#0
	mov	B23,#0

	; -- set PS2 clock and data line
	setb	p3.3
	setb	p3.5

	; -- init the ring buffers
	mov	RingBuf1PtrIn,#0
	mov	RingBuf1PtrOut,#0
	mov	RingBuf2PtrIn,#0
	mov	RingBuf2PtrOut,#0

; ----------------
Loop:
	; -- check AT/PS2 receive status
	jb	PS2RXCompleteF,LoopProcessATPS2Data

	; -- loop PCXT-TX is active
	jb	PCXTActiveF, Loop

	; send data to computer
	call	Buf1TX

	; send data to keyboard
	call	Buf2TX

	; -- loop
	sjmp Loop

;----------------------------------------------------------
; helpers for the main loop
;----------------------------------------------------------
; ----------------
LoopProcessATPS2Data:
; -- AT/PS2 data received, process the received scancode into output ring buffer
	call	TranslateToBuf
	sjmp	Loop

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	" Copyright 2009 by Alexander Kurz"
LIC02	DB	" --- "
;GPL_S1	DB	" This program is free software; licensed under the terms of the GNU GPL V3"
GPL01	DB	" This program is free software; you can redistribute it and/or modify"
GPL02	DB	" it under the terms of the GNU General Public License as published by"
GPL03	DB	" the Free Software Foundation; either version 3, or (at your option)"
GPL04	DB	" any later version."
GPL05	DB	" --- "
GPL06	DB	" This program is distributed in the hope that it will be useful,"
GPL07	DB	" but WITHOUT ANY WARRANTY; without even the implied warranty of"
GPL08	DB	" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the"
GPL09	DB	" GNU General Public License for more details."
GPL10	DB	" "
; ----------------
	end

