; ---------------------------------------------------------------------
; AT/PS2 to DEC LK201/LK401 keyboard transcoder for 8051 type processors.
;
; $KbdBabel: kbdbabel_ps2_dec_8051.asm,v 1.7 2007/04/25 08:29:29 akurz Exp $
;
; Clock/Crystal: 18.432MHz.
; 3.6864MHz or 7.3728 may do as well.
;
; AT/PS2 Keyboard connect:
; This two pins need externals 4.7k resistors as pullup.
; DATA - p3.4   (Pin 14 on DIL40, Pin 8 on AT89C2051 PDIP20)
; CLOCK - p3.2  (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
;
; DEC Host connect:
; RS232 level using a MAX232-IC
; RxD - p3.0 (Pin 10 on DIL40, Pin 2 on AT89C2051 PDIP20)
; TxD - p3.1 (Pin 11 on DIL40, Pin 3 on AT89C2051 PDIP20)
;
; LED-Output connect:
; LEDs are connected with 220R to Vcc
; ScrollLock	- p1.7	(Pin 8 on DIL40, Pin 19 on AT89C2051 PDIP20)
; CapsLock	- p1.6	(Pin 7 on DIL40, Pin 18 on AT89C2051 PDIP20)
; Compose	- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; Wait/Combi	- p1.4	(Pin 5 on DIL40, Pin 16 on AT89C2051 PDIP20)
; AT/PS2 RX error	- p1.3
; AT/PS2 RX Parity error- p1.2
:
; Buzzer connect
; clicks should be 2ms of 2kHz, beeps 125ms of 2kHz
; buzzer volume mid	- p1.1
; buzzer volume	coarse	- p1.0
; buzzer		- p3.7	(Pin 17 on DIL40, Pin 11 on AT89C2051 PDIP20)
;
; Build:
; $ asl kbdbabel_ps2_dec_8051.asm -o kbdbabel_ps2_dec_8051.p
; $ p2bin -l \$ff kbdbabel_ps2_dec_8051
; write kbdbabel_ps2_dec_8051.bin on an empty 27C256 or AT89C2051
;
; Copyright 2006 by Alexander Kurz
;
; This is free software.
; You may copy and redistibute this software according to the
; GNU general public license version 2 or any later verson.
;
; ---------------------------------------------------------------------

	cpu 8052
	include	stddef51.inc

;----------------------------------------------------------
; Variables / Memory layout
;----------------------------------------------------------
;------------------ bits
PS2RXBitF	bit	20h.0	; RX-bit-buffer
PS2RXCompleteF	bit	20h.1	; full and correct byte-received
PS2ActiveF	bit	20h.2	; PS2 RX or TX in progress flag
PS2HostToDevF	bit	20h.3	; host-to-device flag for Int0-handler
PS2RXBreakF	bit	20h.4	; AT/PS2 0xF0 Break scancode received
PS2RXEscapeF	bit	20h.5	; AT/PS2 0xE0 Escape scancode received
PS2TXAckF	bit	20h.6	; ACK-Bit on host-to-dev
PS2RXAckF	bit	20h.7	; ACK-Scancode received
MiscSleepF	bit	21h.0	; sleep timer active flag
TFModF		bit	21h.1	; Timer modifier: PS2 timeout or alarm clock
TimeoutF	bit	21h.2	; Timeout occured
PS2ResendF	bit	21h.3	; AT/PS2 resend
LKCmdLedOffF	bit	22h.2	; wait for LED-Turn-Off Argument
LKCmdLedOnF	bit	22h.3	; wait for LED-Turn-On Argument
LKCmdVolF	bit	22h.4	; wait for Volume Argument
LKKeyClickF	bit	22h.5
LKModSL		bit	23h.0	; LK modifier state storage: left shift
LKModSR		bit	23h.1	; LK modifier state storage: right shift
LKModAL		bit	23h.2	; LK modifier state storage: left alt
LKModAR		bit	23h.3	; LK modifier state storage: right alt
LKModC		bit	23h.4	; LK modifier state storage: ctrl

;------------------ octets
LKModAll	equ	23h	; collective access to stored LK modifier flags
KbBitBufL	equ	24h
KbBitBufH	equ	25h
;KbClockMin	equ	26h
;KbClockMax	equ	27h
PS2TXBitBuf	equ	28h
PS2ResendBuf	equ	29h
RawBuf		equ	30h	; raw PC/XT scancode
PS2ResendTTL	equ	31h	; prevent resent-loop
TXBuf		equ	32h	; AT scancode TX buffer
RingBuf1PtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBuf1PtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
RingBuf2PtrIn	equ	35h	; Ring Buffer write pointer, starting with zero
RingBuf2PtrOut	equ	36h	; Ring Buffer read pointer, starting with zero
DECRXBuf	equ	37h	; DEC host-to-dev buffer
DECLedBuf	equ	38h	; LED state buffer
PS2RXLastBuf	equ	39h	; Last received scancode
LKModBuf	equ	3ah	; translated received modifier codes
PS2LedBuf	equ	3bh	; LED state buffer for PS2 Keyboard

;------------------ arrays
RingBuf1		equ	40h
RingBuf1SizeMask	equ	0fh	; 16 byte ring-buffer size
RingBuf2		equ	50h
RingBuf2SizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	60h	; the stack

;----------------------------------------------------------
; misc constants
;----------------------------------------------------------
;------------------ bitrates generated with timer 1 in 8 bit mode
; 1200BPS @3.6864MHz -> tl1 and th1 = #240 with SMOD=1	; (256-2*3686.4/384/1.2)
uart_t1_1200_3686_4k		equ	240

; 1200BPS @7.3728MHz -> tl1 and th1 = #224 with SMOD=1	; (256-2*7372.8/384/1.2)
uart_t1_1200_7372_8k		equ	224

; 1200BPS @11.0592MHz -> tl1 and th1 = #208 with SMOD=1 ; (256-2*11059.2/384/1.2)
uart_t1_1200_11059_2k		equ	208

; 1200BPS @14.7456MHz -> tl1 and th1 = #192 with SMOD=1	; (256-2*14745.6/384/1.2)
uart_t1_1200_14745_6k		equ	192

; 1200BPS @18.432MHz -> tl1 and th1 = #176 with SMOD=1	; (256-2*18432/384/1.2)
uart_t1_1200_18432k		equ	176

; 4800BPS @11.0592MHz -> tl1 and th1 = #244 with SMOD=1	; (256-2*11059.2/384/4.8)
uart_t1_4800_11059_2k		equ     244

; 4800BPS @18.432MHz -> tl1 and th1 = #236 with SMOD=1	; (256-2*18432/384/4.8)
uart_t1_4800_18432k		equ	236

; 9600BPS @18.432MHz -> tl1 and th1 = #246 with SMOD=1	; (256-2*18432/384/9.6)
uart_t1_9600_18432k		equ	246

;------------------ bitrates generated with timer 2
; 9600 BPS at 18.432MHz -> RCAP2H,RCAP2L=#0FFh,#0c4h	; (256-18432/32/9.6)
uart_t2h_9600_18432k		equ	255
uart_t2l_9600_18432k		equ	196

;------------------ AT scancode timing intervals generated with timer 0 in 8 bit mode
; 50mus@11.0592MHz -> th0 and tl0=209 or 46 processor cycles	; (256-11059.2*0.05/12)
interval_t0_50u_11059_2k	equ	209

; 50mus@11.0592MHz -> th0 and tl0=214 or 41 processor cycles	; (256-11059.2*0.045/12)
interval_t0_45u_11059_2k	equ	214

; 45mus@12.000MHz -> th0 and tl0=211 or 45 processor cycles	; (256-12000*0.045/12)
interval_t0_45u_12M		equ	211

; 40mus@18.432MHz -> th0 and tl0=194 or 61 processor cycles	; (256-18432*0.04/12)
interval_t0_40u_18432k		equ	194

; 40mus@24.000MHz -> th0 and tl0=176 or 80 processor cycles	; (256-24000*0.04/12)
interval_t0_40u_24M		equ	176

;------------------ AT RX timeout values using timer 0 in 16 bit mode
; --- 18.432MHz
; 20ms@18.432MHz -> th0,tl0=0c4h,00h	; (65536-18432*20/12)
interval_th_20m_18432k		equ	136
interval_tl_20m_18432k		equ	0

; 10ms@18.432MHz -> th0,tl0=0c4h,00h	; (65536-18432*10/12)
interval_th_10m_18432k		equ	196
interval_tl_10m_18432k		equ	0

; 1ms@18.432MHz -> th0,tl0=0fah,00h	; (65536-18432*1/12)
interval_th_1m_18432k		equ	250
interval_tl_1m_18432k		equ	0

; 0.13ms@18.432MHz -> th0,tl0=0ffh,38h	; (65536-18432*0.13/12)
interval_th_130u_18432k		equ	255
interval_tl_130u_18432k		equ	56

; 40mus@18.432MHz -> th0,tl0=0ffh,C3h	; (256-18432*0.04/12) (65536-18432*0.04/12)
interval_th_40u_18432k		equ	255
interval_tl_40u_18432k		equ	194

; --- 11.0592MHz
; 20ms@11.0592MHz -> th0,tl0=0b8h,00h	; (65536-11059.2*20/12)
interval_th_20m_11059_2k	equ	184
interval_tl_20m_11059_2k	equ	0

; 10ms@11.0592MHz -> th0,tl0=0dch,00h	; (65536-11059.2*10/12)
interval_th_10m_11059_2k	equ	220
interval_tl_10m_11059_2k	equ	0

; 1ms@11.0592MHz -> th0,tl0=0fch,66h	; (65536-11059.2*1/12)
interval_th_1m_11059_2k		equ	252
interval_tl_1m_11059_2k		equ	42

; 0.13ms@11.0592MHz -> th0,tl0=0ffh,88h	; (65536-11059.2*0.13/12)
interval_th_130u_11059_2k	equ	255
interval_tl_130u_11059_2k	equ	136

; --- 24.000MHz
; 20ms@24.000MHz -> th0,tl0=63h,0c0h	; (65536-24000*20/12)
interval_th_20m_24M		equ	99
interval_tl_20m_24M		equ	192

; 10ms@24.000MHz -> th0,tl0=0B1h,E0h	; (65536-24000*10/12)
interval_th_10m_24M		equ	177
interval_tl_10m_24M		equ	224

; 1ms@24.000MHz -> th0,tl0=0f8h,30h	; (65536-24000*1/12)
interval_th_1m_24M		equ	248
interval_tl_1m_24M		equ	48

; 0.128ms@24.000MHz -> th0,tl0=0ffh,00h	; (65536-24000*.128/12)
interval_th_128u_24M		equ	255
interval_tl_128u_24M		equ	0

;------------------ PCXT RX timeout and interval diagnosis using timer 0 in 16 bit mode
; --- 11 bit for timing diagnosis
; 1.02ms @24.000MHz	; 2048*12/24000
; 1.33ms @18.432MHz	; 2048*12/18432
; 2.22ms @11.0592MHz	; 2048*12/11059.2
; 3.33ms @7.3728MHz	; 2048*12/7372.8
interval_th_11_bit		equ	0f8h
interval_tl_11_bit		equ	0

; --- 10 bit for timing diagnosis
; 1.1ms @11.0592MHz	; 1024*12/11059.2
; 1.7ms @7.3728MHz	; 1024*12/7372.8
interval_th_10_bit		equ	0fch
interval_tl_10_bit		equ	0

; --- 9 bit for timing diagnosis
; 0.83ms @7.3728MHz	; 512*12/7372.8
; 1.7ms @3.6864MHz	; 512*12/3686.4
interval_th_9_bit		equ	0feh
interval_tl_9_bit		equ	0

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
	jnb	P3.4, HandleInt0	; this is time critical
	setb	PS2RXBitF
	ljmp	HandleInt0
;----------------------------
	org	0bh	; handle TF0
	ljmp	HandleTF0
;----------------------------
;	org	13h	; Int 1
;	ljmp	HandleInt1
;----------------------------
;	org	1bh	; handle TF1
;	ljmp	HandleTF1
;----------------------------
;	org	23h	; RI/TI
;	ljmp	HandleRITI
;----------------------------
;	org	2bh	; handle TF2
;	ljmp	HandleTF2

	org	033h
;----------------------------------------------------------
; int0 handler:
; read one data bit triggered by the keyboard clock line
; rotate bit into KbBitBufH, KbBitBufL.
; Last clock sample interval is stored in r6
; rotate bit into 22h, 23h.
; Num Bits is in r7
;
; TX:
; Byte to sent is read from PS2TXBitBuf
; ACK result is stored in PS2TXAckF. 0 is ACK, 1 is NACK.
;----------------------------------------------------------
HandleInt0:
	push	acc
	push	psw

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
	jb	PS2HostToDevF,Int0PS2TX

; --------------------------- AT/PS2 RX: get and save data samples
;	clr	p1.3
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
	jnz	Int0NotStartBit	; start bit
Int0NotStartBit:
	clr	c
	subb	a,#0ah
	jz	Int0LastBit

; -- inc the bit counter
	inc	r7
	ljmp	Int0Return

; -- special handling for last bit: output
Int0LastBit:
;	clr	p1.2

	; start-bit must be 0
	jb	KbBitBufH.5, Int0Error
	; stop-bit must be 1
	jnb	KbBitBufL.7, Int0Error
	; error LED off
	setb	p1.2
	setb	p1.3

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
	jb      p,Int0RXParityBitPar
	jnc	Int0ParityError
	sjmp	Int0Output

Int0RXParityBitPar:
	jc	Int0ParityError

Int0Output:
	; -- return received byte
	jnb	LKKeyClickF,Int0OutputNoClick
;	setb	p3.7	; buzzer on
Int0OutputNoClick:
	mov	a, KbBitBufL
	mov	RawBuf, a
	mov	r7,#0
	setb	PS2RXCompleteF	; fully received flag
	clr	PS2ActiveF	; receive in progress flag

;	; --- write to LED
;	xrl	a,0FFh
;	mov	p1,a

	sjmp	Int0Return

Int0ParityError:
; -- cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	p1.2
	sjmp	Int0Return

Int0Error:
; -- cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	p1.3
	sjmp	Int0Return

; --------------------------- AT/PS2 TX
Int0PS2TX:
;	clr	p1.4
	; -- reset RX bit buffer
	clr	PS2RXBitF
	setb	PS2TXAckF
;	setb	p1.5
; -- checks by bit number
	mov	a,r7
	jz	Int0PS2TXStart
	clr	c
	subb	a,#09h
	jc	Int0PS2TXData
	jz	Int0PS2TXPar
	dec	a
	jz	Int0PS2TXStop

	; --- the last bit. read ACK-bit
	mov	c,p3.4
	mov	PS2TXAckF,c
;	mov	p1.5,c

	; --- reset data and clock
	mov	r7,#0h
	clr	p3.2		; pull down clock
	setb	p3.4		; data
	clr	PS2ActiveF	; receive in progress flag
	clr	PS2HostToDevF
	sjmp	Int0Return

Int0PS2TXStart:
	; --- set start bit
	clr	p3.4
	sjmp	Int0PS2TXReturn

Int0PS2TXData
	; --- set data bit
	mov	a,PS2TXBitBuf
	mov	c,acc.0
	mov	p3.4,c
	rr	a
	mov	PS2TXBitBuf,a
	sjmp	Int0PS2TXReturn

Int0PS2TXPar:
	; --- set parity bit
	mov	a,PS2TXBitBuf
	mov	c,p
	cpl	c
	mov	p3.4,c
	sjmp	Int0PS2TXReturn

Int0PS2TXStop:
	; --- set stop bit
	setb	p3.4
	sjmp	Int0PS2TXReturn

Int0PS2TXReturn:
; -- inc the bit counter
	inc	r7
;	sjmp	Int0Return

; --------------------------- done
Int0Return:
;	setb	p1.4
;	setb	p1.2
;	setb	p1.3
	pop	psw
	pop	acc
	reti

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
	; buzzer off
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

;	setb	p3.4	; data
;	setb	p3.2	; clock

	sjmp	HandleTF0End

timerAsClockTimer:
	; --- timer used to generate delays
	setb	MiscSleepF
	clr	TFModF

HandleTF0End:
	reti

;----------------------------------------------------------
; AT/PS2 to DEC LK translaton table
; edit: PS2-0x77 -> LK-0xad (NumLock-> Compose)
;----------------------------------------------------------
ATPS22DECxlt0	DB	 00h, 067h, 065h, 05ah, 058h, 056h, 057h, 072h,   00h, 068h, 066h, 064h, 059h, 0beh, 0bfh,  00h
ATPS22DECxlt1	DB	 00h, 0ach, 0aeh,  00h, 0afh, 0c1h, 0c0h,  00h,   00h,  00h, 0c3h, 0c7h, 0c2h, 0c6h, 0c5h,  00h
ATPS22DECxlt2	DB	 00h, 0ceh, 0c8h, 0cdh, 0cch, 0d0h, 0cbh,  00h,   00h, 0d4h, 0d3h, 0d2h, 0d7h, 0d1h, 0d6h,  00h
ATPS22DECxlt3	DB	 00h, 0deh, 0d9h, 0ddh, 0d8h, 0dch, 0dbh,  00h,   00h,  00h, 0e3h, 0e2h, 0e1h, 0e0h, 0e5h,  00h
ATPS22DECxlt4	DB	 00h, 0e8h, 0e7h, 0e6h, 0ebh, 0efh, 0eah,  00h,   00h, 0edh, 0f3h, 0ech, 0f2h, 0f0h, 0f9h,  00h
ATPS22DECxlt5	DB	 00h,  00h, 0fbh,  00h, 0fah, 0f5h,  00h,  00h,  0b0h, 0abh, 0bdh, 0f6h,  00h, 0f7h,  00h,  00h
ATPS22DECxlt6	DB	 00h, 0c9h,  00h,  00h,  00h,  00h, 0bch,  00h,   00h, 096h,  00h, 099h, 09dh,  00h,  00h,  00h
ATPS22DECxlt7	DB	092h, 094h, 097h, 09ah, 09bh, 09eh, 0fbh, 0adh,  071h,  00h, 098h, 0a0h,  00h, 09fh,  00h,  00h
ATPS22DECxlt8	DB	 00h,  00h,  00h, 065h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxlt9	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxlta	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltb	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltc	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltd	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxlte	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltf	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; AT/PS2 to DEC LK translaton table for 0xE0-Escaped scancodes
;----------------------------------------------------------
ATPS22DECxltE0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltE1	DB	 00h, 0b2h,  00h,  00h, 0afh,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltE2	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltE3	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltE4	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltE5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltE6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h, 08dh,  00h, 0a7h, 08ah,  00h,  00h,  00h
ATPS22DECxltE7	DB	08bh, 08ch, 0a9h,  00h, 0a8h, 0aah,  00h,  00h,   00h,  00h, 08fh,  00h,  00h, 08eh,  00h,  00h
ATPS22DECxltE8	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltE9	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltEa	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltEb	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltEc	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltEd	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltEe	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22DECxltEf	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; ATPS22DEC
; Helper, translate normal AT/PS2 to DEC LK scancode
; input: dptr: table address, a: AT/PS2 scancode
;----------------------------------------------------------
ATPS22DEC:
	jb	PS2RXEscapeF,ATPS22DECEsc

; --- normal single scancodes
	mov	dptr,#ATPS22DECxlt0
	movc	a,@a+dptr
	sjmp	ATPS22DECEnd

; --- 0xE0-escaped scancodes
ATPS22DECEsc:
	clr	PS2RXEscapeF
	mov	dptr,#ATPS22DECxltE0
	movc	a,@a+dptr
;	sjmp	ATPS22DECEnd

ATPS22DECEnd:
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
;	clr	p1.@3
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
;	clr	p1.@3
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

	; ------ check special keys
	; --- save modifiers
	mov	a,LKModAll
	mov	LKModBuf,a

	; --- restore new scancode
	mov	a,RawBuf
	jb	PS2RXEscapeF,TranslateToBufSpecialEsc
	; --- special single keys
	cjne	a,#012h,TranslateToBufNot12	; Shift L
	mov	c,PS2RXBreakF
	cpl	c
	mov	LKModSL,c
	sjmp	TranslateToBufModCode
TranslateToBufNot12:
	cjne	a,#059h,TranslateToBufNot59	; Shift R
	mov	c,PS2RXBreakF
	cpl	c
	mov	LKModSR,c
	sjmp	TranslateToBufModCode
TranslateToBufNot59:
	cjne	a,#014h,TranslateToBufNot14	; Ctrl L
	mov	c,PS2RXBreakF
	cpl	c
	mov	LKModC,c
	sjmp	TranslateToBufModCode
TranslateToBufNot14:
	cjne	a,#011h,TranslateToBufNot11	; Alt L
	mov	c,PS2RXBreakF
	cpl	c
	mov	LKModAL,c
	sjmp	TranslateToBufModCode
TranslateToBufNot11:
;	cjne	a,#058h,TranslateToBufNot58	; CapsLock
;	clr	PS2RXBreakF
;	sjmp	TranslateToBufNormalCode
;TranslateToBufNot58:
	sjmp	TranslateToBufNormalCode

TranslateToBufSpecialEsc:
	; --- special escaped keys
	cjne	a,#011h,TranslateToBufNotE011	; Alt R
	mov	c,PS2RXBreakF
	cpl	c
	mov	LKModAR,c
	sjmp	TranslateToBufModCode
TranslateToBufNotE011:
	cjne	a,#014h,TranslateToBufNotE014	; Ctrl R
	mov	c,PS2RXBreakF
	cpl	c
	mov	LKModC,c
	sjmp	TranslateToBufModCode
TranslateToBufNotE014:
	sjmp	TranslateToBufNormalCode

TranslateToBufModCode:
	clr	PS2RXBreakF
	mov	a,LKModAll
	jnz	TranslateToBufModNZ
	; --- all modifiers released
	clr	PS2RXBreakF
	clr	PS2RXEscapeF
	clr	PS2RXCompleteF
	mov	a,#0b3h
	sjmp TranslateToBufInsert

TranslateToBufModNZ:
	cjne	a,LKModBuf,TranslateToBufModNE
	; --- nothing changed, ignore
	clr	PS2RXEscapeF
	clr	PS2RXCompleteF
	sjmp	TranslateToBufEnd

TranslateToBufModNE:
	; --- modifier changed, send it
	mov	a,RawBuf
	clr	PS2RXCompleteF
	clr	PS2RXBreakF
	sjmp	TranslateToBufNoGo

	; ------ normal scancodes
TranslateToBufNormalCode:
	; --- ignore break scancodes for normal keys
	jnb	PS2RXBreakF,TranslateToBufNoGo
	clr	PS2RXBreakF
	clr	PS2RXEscapeF
	clr	PS2RXCompleteF
	sjmp	TranslateToBufEnd

TranslateToBufNoGo:
	; keyboard disabled?
;	jb	FooBarDisableF,TranslateToBufEnd
	; --- check typematic/metronome
	; todo
	; TranslateToBufInsert

	; --- translate
	clr	PS2RXCompleteF
	call	ATPS22DEC

	; --- dont insert zeros
	jz	TranslateToBufEnd

	; --- insert
TranslateToBufInsert:
	mov	r2, a
	call	RingBuf1CheckInsert

TranslateToBufEnd:
	ret

;----------------------------------------------------------
; Send data from the ring buffer
;----------------------------------------------------------
	; -- send ring buffer contents
Buf1TX:
	; check if data is present in the ring buffer
	clr	c
	mov	a,RingBuf1PtrIn
	subb	a,RingBuf1PtrOut
	anl	a,#RingBuf1SizeMask
	jz	Buf1TXEnd

;	clr	p1.@1
	; -- get data from buffer
	mov	a,RingBuf1PtrOut
	add	a,#RingBuf1
	mov	r0,a
	mov	a,@r0

	; -- send data
	mov	sbuf,a		; 8 data bits
	clr	TI

	; -- increment output pointer
	inc	RingBuf1PtrOut
	anl	RingBuf1PtrOut,#RingBuf1SizeMask

Buf1TXEnd:
;	setb	p1.@1
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
	clr	p3.2		; clock down

	; -- wait 40mus
	call	timer0_init_40mus
Buf2TXWait1:
	jnb	MiscSleepF,Buf2TXWait1
	clr	p3.4		; data down

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
	setb	p3.2		; clock up
	; -- keyboard should start sending clocks now
Buf2TXWait3:
	jb	PS2HostToDevF,Buf2TXWait3
	setb	p3.4		; data up

	; -- wait 1ms
	call	timer0_init_1ms
;	call	timer0_init_40mus
Buf2TXWait4:
	jnb	MiscSleepF,Buf2TXWait4
	setb	p3.2		; clock up

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
; check and respond to received DEC commands
;----------------------------------------------------------
DECCmdProc:
	; -- get received DEC LK command
	mov	a,DECRXBuf

	; -- turn off LEDs
	jnb	LKCmdLedOffF,DECCPLedOff
	clr	LKCmdLedOffF
	cpl	a
	anl	a,DECLedBuf
	mov	DECLedBuf,a
	sjmp	DECCPLedDisplay

DECCPLedOff:
	; -- turn on LEDs
	jnb	LKCmdLedOnF,DECCPNotLedOn
	clr	LKCmdLedOnF
	orl	a,DECLedBuf
	mov	DECLedBuf,a
	sjmp	DECCPLedDisplay

DECCPLedDisplay:
	; -- output to LEDs
	cpl	a
	mov	c,acc.3
	mov	p1.7,c	; ScrollLock
	mov	c,acc.2
	mov	p1.6,c	; CapsLock
	mov	c,acc.1
	mov	p1.5,c	; Compose
	mov	c,acc.0
	mov	p1.4,c	; Wait/Combi
	; -- output to AT/PS2 Keyboard
	mov	a,DECLedBuf
	swap	a
	; ScrollLock
	mov	c,acc.7
	mov	acc.0,c
	; CapsLock
	mov	c,acc.6
	mov	acc.2,c
	; Compose to NumLock
	mov	c,acc.5
	mov	acc.1,c
	anl	a,#07h
	; -- check if LEDs changed
	cjne	a,PS2LedBuf,DECCPLedTX2PS2
	ljmp	DECCPDone
DECCPLedTX2PS2:
	; -- send to PS2 keyboad
	mov	PS2LedBuf,a
	mov	r2,#0edh
	call	RingBuf2CheckInsert
	mov	a,PS2LedBuf
	mov	r2,a
	call	RingBuf2CheckInsert
	ljmp	DECCPDone

DECCPNotLedOn:
	; -- set volume
	jnb	LKCmdVolF,DECCPNotVol
	clr	LKCmdVolF
	cpl	a
	; volume comes in bit 0-2
	mov	c,acc.2
	mov	p1.0,c
	mov	c,acc.1
	mov	p1.1,c
	ljmp	DECCPDone

DECCPNotVol:
	; -- command 0xfd: keyboard reset. send POST code \x01\x00\x00\x00
	cjne	a,#0fdh,DECCPNotFD
	mov	r2,#01h
	call	RingBuf1CheckInsert
	mov	r2,#00h
	call	RingBuf1CheckInsert
	mov	r2,#00h
	call	RingBuf1CheckInsert
	mov	r2,#00h
	call	RingBuf1CheckInsert
	sjmp	DECCPDone
DECCPNotFD:
	; -- command 0x0A
	cjne	a,#0Ah,DECCPNot0A
	sjmp	DECCPSendAck
DECCPNot0A:
	; -- command 0x11: LED off
	cjne	a,#11h,DECCPNot11
	setb	LKCmdLedOffF		; LED bit mask follows as next argument
	sjmp	DECCPDone
DECCPNot11:
	; -- command 0x13: LED off
	cjne	a,#13h,DECCPNot13
	setb	LKCmdLedOnF		; LED bit mask follows as next argument
	sjmp	DECCPDone
DECCPNot13:
	; -- command 0x1A
	cjne	a,#1Ah,DECCPNot1A
	sjmp	DECCPSendAck
DECCPNot1A:
	; -- command 0x1B: enable keyclick
	cjne	a,#1Bh,DECCPNot1B
	setb	LKCmdVolF		; Volume follows as next argument
	setb	LKKeyClickF
	setb	p3.7
	sjmp	DECCPDone
DECCPNot1B:
	; -- command 0x23: enable bell
	cjne	a,#023h,DECCPNot23
	;clr	p1.@1
	sjmp	DECCPDone
DECCPNot23:
	; -- command 0x3A
	cjne	a,#3Ah,DECCPNot3A
	sjmp	DECCPSendAck
DECCPNot3A:
	; -- command 0x4A
	cjne	a,#4Ah,DECCPNot4A
	sjmp	DECCPSendAck
DECCPNot4A:
	; -- command 0x5A
	cjne	a,#5Ah,DECCPNot5A
	sjmp	DECCPSendAck
DECCPNot5A:
	; -- command 0x6A
	cjne	a,#6Ah,DECCPNot6A
	sjmp	DECCPSendAck
DECCPNot6A:
	; -- command 0x72
	cjne	a,#72h,DECCPNot72
	sjmp	DECCPSendAck
DECCPNot72:
	; -- command 0x0A2
	cjne	a,#0A2h,DECCPNotA2
	sjmp	DECCPSendAck
DECCPNotA2:
	; -- command 0x78
	cjne	a,#78h,DECCPNot78
	sjmp	DECCPSendAck
DECCPNot78:
	; -- command 0x99: disable keyclick
	cjne	a,#99h,DECCPNot99
	clr	LKKeyClickF
	clr	p3.7
	sjmp	DECCPDone
DECCPNot99:
	; -- command 0xa1: disable bell
	cjne	a,#0A1h,DECCPNotA1
	;setb	p1.@1
	sjmp	DECCPSendAck
DECCPNotA1:
	; -- command 0xa7: sound bell
	cjne	a,#0A7h,DECCPNotA7
	sjmp	DECCPDone
DECCPNotA7:
	sjmp	DECCPDone

DECCPSendAck:
	mov	r2,#0BAh
	call	RingBuf1CheckInsert
;	sjmp	DECCPDone

DECCPDone:
;	setb	p1.@1
	ret

;----------------------------------------------------------
; init uart with timer 1 as baudrate generator for 4800 BPS
;----------------------------------------------------------
uart_timer1_init:
	mov	scon, #050h	; uart mode 1 (8 bit), single processor
	orl	tmod, #020h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 2, 8bit-auto-reload
	orl	pcon, #080h	; SMOD, bit 7 in PCON

;	mov	th1, #uart_t1_4800_11059_2k
;	mov	tl1, #uart_t1_4800_11059_2k
	mov	th1, #uart_t1_4800_18432k
	mov	tl1, #uart_t1_4800_18432k

	clr	es		; disable serial interrupt
	setb	tr1

	clr	ri
	setb	ti

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

	mov	th0, #interval_th_40u_18432k
	mov	tl0, #interval_tl_40u_18432k

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

	mov	th0, #interval_th_1m_18432k
	mov	tl0, #interval_tl_1m_18432k

	setb	TFModF
	clr	MiscSleepF
	setb	et0		; (IE.3) enable timer 0 interrupt
	setb	tr0		; timer 0 run
	ret

;----------------------------------------------------------
; Id
;----------------------------------------------------------
RCSId	DB	"$Id: kbdbabel_ps2_dec_8051.asm,v 1.6 2007/04/25 08:54:33 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom
	; -- init UART and timer0/1
	acall	uart_timer1_init
	acall	timer0_init
	clr	TFModF

	; -- enable interrupts int0
	setb	ex0		; external interupt 0 enable
	setb	it0		; falling edge trigger for int 0
	setb	ea

	; -- clear all flags
	mov	20h,#0
	mov	21h,#0
	mov	22h,#0
	mov	23h,#0

	; -- set PS2 clock and data line
	setb	p3.2
	setb	p3.4

	; -- turn off the buzzer
	setb	p1.0
	clr	p3.7
	clr	LKKeyClickF

	; -- init the ring buffers
	mov	RingBuf1PtrIn,#0
	mov	RingBuf1PtrOut,#0
	mov	RingBuf2PtrIn,#0
	mov	RingBuf2PtrOut,#0

;	; -- cold start flag
;	setb	FooBarColdStartF

; ----------------
Loop:
	; -- check AT/PS2 receive status
	jb	PS2RXCompleteF,LoopProcessATPS2Data

	; -- check on new data from serial line
	jb	RI, LoopProcessLKCmd

	; -- loop if serial TX is active
	jnb	TI, Loop

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

; ----------------
LoopProcessLKcmd:
; -- commands from DEC host received via serial line
	mov	a,sbuf
	mov	DECRXBuf,a
	clr	RI

	acall	DECCmdProc
	sjmp	Loop

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	" Copyright 2007 by Alexander Kurz"
LIC02	DB	" --- "
;GPL_S1	DB	" This program is free software; licensed under the terms of the GNU GPL V2"
GPL01	DB	" This program is free software; you can redistribute it and/or modify"
GPL02	DB	" it under the terms of the GNU General Public License as published by"
GPL03	DB	" the Free Software Foundation; either version 2, or (at your option)"
GPL04	DB	" any later version."
GPL05	DB	" --- "
GPL06	DB	" This program is distributed in the hope that it will be useful,"
GPL07	DB	" but WITHOUT ANY WARRANTY; without even the implied warranty of"
GPL08	DB	" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the"
GPL09	DB	" GNU General Public License for more details."
GPL10	DB	" "
; ----------------
	end
