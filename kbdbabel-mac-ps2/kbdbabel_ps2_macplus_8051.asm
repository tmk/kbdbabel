; ---------------------------------------------------------------------
; AT/PS2 to Macintosh Plus keyboard transcoder
; for 8051 type processors.
;
; $KbdBabel: kbdbabel_ps2_macplus_8051.asm,v 1.5 2007/06/27 22:31:34 akurz Exp $
;
; Clock/Crystal: 11.0592MHz.
;
; Mac Keyboard connect:
; DATA - p3.4	(Pin 14 on DIL40, Pin 8 on AT89C2051 PDIP20)
; CLOCK - p3.2  (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
;
; AT Host connect:
; DATA - p3.5	(Pin 15 on DIL40, Pin 9 on AT89C2051 PDIP20)
; CLOCK - p3.3	(Pin 13 on DIL40, Pin 7 on AT89C2051 PDIP20, Int 1)
;
; LED-Output connect:
; LEDs are connected with 470R to Vcc
; CapsLock			- p1.7	(Pin 8 on DIL40, Pin 19 on AT89C2051 PDIP20)
; Mac Timer Int TF1 active	- p1.6	(Pin 7 on DIL40, Pin 18 on AT89C2051 PDIP20)
; Mac Sleep timer		- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; Mac TX			- p1.4
; AT/PS2 RX error		- p1.3
; AT/PS2 RX Parity error	- p1.2
; Int1 / PS2 TX active		- p1.1
; Int1 / PS2 active		- p1.0
;
; Build using the macroassembler by Alfred Arnold
; $ asl -L kbdbabel_ps2_macplus_8051.asm -o kbdbabel_ps2_macplus_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_ps2_macplus_8051
; write kbdbabel_ps2_macplus_8051.bin on an empty 27C256 or AT89C2051
;
; Copyright 2007 by Alexander Kurz
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
;------------------ octets
B20		sfrb	20h	; bit adressable space
B21		sfrb	21h
B22		sfrb	22h
;		equ	23h
KbBitBufL	sfrb	24h
KbBitBufH	sfrb	25h
PS2TXBitBuf	equ	26h
MacBitBuf	equ	27h
MacBitCount	sfrb	28h
MacPauseCount	equ	29h
RingBuf1PtrIn	equ	30h	; Ring Buffer write pointer, starting with zero
RingBuf1PtrOut	equ	31h	; Ring Buffer read pointer, starting with zero
RingBuf2PtrIn	equ	32h	; Ring Buffer write pointer, starting with zero
RingBuf2PtrOut	equ	33h	; Ring Buffer read pointer, starting with zero
RawBuf		equ	34h	; raw PC/XT scancode
PS2ResendTTL	equ	35h	; prevent resent-loop
PS2ResendBuf	equ	36h
PS2LedBuf	equ	37h	; LED state buffer for PS2 Keyboard
PS2RXLastBuf	equ	38h	; Last received scancode
MacScancode	equ	39h	; Mac Scancode TX buffer
MacRXBitBuf	equ	3ah	; Mac RX Bit buffer
MacRXBuf	equ	3bh	; Mac RX buffer
MacTxBuf	equ	3ch	; Mac TX buffer
PS2LastBuf	equ	3dh	; for PS2-Typematic surpressor

;------------------ bits
PS2RXBitF	bit	B20.0	; RX-bit-buffer
PS2RXCompleteF	bit	B20.1	; full and correct byte-received
PS2ActiveF	bit	B20.2	; PS2 RX or TX in progress flag
PS2HostToDevF	bit	B20.3	; host-to-device flag for Int1-handler
PS2RXBreakF	bit	B20.4	; AT/PS2 0xF0 Break scancode received
PS2RXEscapeF	bit	B20.5	; AT/PS2 0xE0 Escape scancode received
PS2TXAckF	bit	B20.6	; ACK-Bit on host-to-dev
PS2RXAckF	bit	B20.7	; ACK-Scancode received
MiscSleepF	bit	B21.0	; sleep timer active flag
TF0ModF		bit	B21.1	; Timer modifier: PS2 timeout or alarm clock
TimeoutF	bit	B21.2	; Timeout occured
PS2ResendF	bit	B21.3	; AT/PS2 resend
MacCapsLockF	bit	B21.4	; Mechanical CapsLock-Emulation
PS2LastBreakF	bit	B21.5	; for PS2-Typematic surpressor
PS2LastEscapeF	bit	B21.6	; for PS2-Typematic surpressor
TF1ModF		bit	B22.1	; Timer modifier
MacMasq9eF	bit	B22.2	; Mac 9e Masq-Scancode
MacMasq8e9eF	bit	B22.3	; Mac 8e9e Masq-Scancode
MiscSleepT1F	bit	B22.4	; sleep timer1 active flag
MacTxF		bit	B22.5	; Mac RX/TX control flag
MacSleepInitF	bit	B22.6	; timer init flag
MacRXCompleteF	bit	B22.7	; full and correct byte-received

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
;------------------ AT scancode timing intervals generated with timer 0 in 8 bit mode
; 50mus@11.0592MHz -> th0 and tl0=209 or 46 processor cycles	; (256-11059.2*0.05/12)
interval_t0_50u_11059_2k	equ	209

; 45mus@11.0592MHz -> th0 and tl0=214 or 41 processor cycles	; (256-11059.2*0.045/12)
interval_t0_45u_11059_2k	equ	214

; 45mus@12.000MHz -> th0 and tl0=211 or 45 processor cycles	; (256-12000*0.045/12)
interval_t0_45u_12M		equ	211

; 40mus@18.432MHz -> th0 and tl0=194 or 61 processor cycles	; (256-18432*0.04/12)
interval_t0_40u_18432k		equ	194

; 40mus@22.1184MHz -> th0 and tl0=182 or 80 processor cycles	; (256-22118.4*0.04/12)
interval_t0_40u_22118_4k	equ	182

; 40mus@24.000MHz -> th0 and tl0=176 or 80 processor cycles	; (256-24000*0.04/12)
interval_t0_40u_24M		equ	176

;------------------ KC-85 interval generation with timer 1 in 8 bit mode
; 125mus@11.0592MHz -> th0 and tl0=141 or 115 processor cycles	; (256-11059.2*0.125/12)
interval_t1_125u_11059_2k	equ	141

; 125mus@12.000MHz -> th0 and tl0=131 or 125 processor cycles	; (256-12000*0.125/12)
interval_t1_125u_12M		equ	131

; 125mus@18.432MHz -> th0 and tl0=64 or 192 processor cycles	; (256-18432*0.125/12)
interval_t1_125u_18432k		equ	64

; 125mus@22.1184MHz -> th0 and tl0=26 or 230 processor cycles	; (256-22118.4*0.125/12)
interval_t1_125u_22118_4k	equ	26

; 125mus@24.000MHz -> th0 and tl0=6 or 250 processor cycles	; (256-24000*0.125/12)
interval_t1_125u_24M		equ	6

;------------------ Mac scancode timing intervals generated with timer 1 in 8 bit mode
; 200mus@11.0592MHz -> th0 and tl0=72 or 184 processor cycles	; (256-11059.2*0.2/12)
interval_t1_200u_11059_2k	equ	72

; 150mus@11.0592MHz -> th0 and tl0=118 or 138 processor cycles	; (256-11059.2*0.15/12)
interval_t1_150u_11059_2k	equ	118

;------------------ timeout values using timer 0 in 16 bit mode
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

; 0.3ms@11.0592MHz -> th0,tl0=0feh,ebh	; (65536-11059.2*0.3/12)
interval_th_300u_11059_2k	equ	254
interval_tl_300u_11059_2k	equ	235

; 0.15ms@11.0592MHz -> th0,tl0=0ffh,76h	; (65536-11059.2*0.15/12)
interval_th_150u_11059_2k	equ	255
interval_tl_150u_11059_2k	equ	118

; 0.13ms@11.0592MHz -> th0,tl0=0ffh,88h	; (65536-11059.2*0.13/12)
interval_th_130u_11059_2k	equ	255
interval_tl_130u_11059_2k	equ	136

; 40mus@11.0592MHz -> th0,tl0=0ffh,dch	; (65536-11059.2*0.04/12)
interval_th_40u_11059_2k	equ	255
interval_tl_40u_11059_2k	equ	220

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

; 0.3ms@18.432MHz -> th0,tl0=0feh,33h	; (65536-18432*0.3/12)
interval_th_300u_18432k		equ	254
interval_tl_300u_18432k		equ	51

; 0.15ms@18.432MHz -> th0,tl0=0ffh,19h	; (65536-18432*0.15/12)
interval_th_150u_18432k		equ	255
interval_tl_150u_18432k		equ	25

; 0.13ms@18.432MHz -> th0,tl0=0ffh,38h	; (65536-18432*0.13/12)
interval_th_130u_18432k		equ	255
interval_tl_130u_18432k		equ	56

; 40mus@18.432MHz -> th0,tl0=0ffh,C3h	; (256-18432*0.04/12) (65536-18432*0.04/12)
interval_th_40u_18432k		equ	255
interval_tl_40u_18432k		equ	194

; --- 22.1184MHz
; 20ms@22.1184MHz -> th0,tl0=70h,00h	; (65536-22118.4*20/12)
interval_th_20m_22118_4k	equ	112
interval_tl_20m_22118_4k	equ	0

; 10ms@22.1184MHz -> th0,tl0=0B8h,00h	; (65536-22118.4*10/12)
interval_th_10m_22118_4k	equ	184
interval_tl_10m_22118_4k	equ	0

; 1ms@22.1184MHz -> th0,tl0=0f8h,0cdh	; (65536-22118.4*1/12)
interval_th_1m_22118_4k		equ	248
interval_tl_1m_22118_4k		equ	205

; 0.3ms@22.1184MHz -> th0,tl0=0fdh,d7h	; (65536-22118.4*.3/12)
interval_th_300u_22118_4k	equ	253
interval_tl_300u_22118_4k	equ	215

; 0.15ms@22.1184MHz -> th0,tl0=0feh,edh	; (65536-22118.4*.15/12)
interval_th_15u_22118_4k	equ	254
cfinterval_tl_15u_22118_4k	equ	237

; 0.128ms@22.1184MHz -> th0,tl0=0ffh,14h	; (65536-22118.4*.128/12)
interval_th_128u_22118_4k	equ	255
interval_tl_128u_22118_4k	equ	20

; 40mus@22.1184MHz -> th0,tl0=0ffh,b7h	; (65536-22118.4*0.04/12)
interval_th_40u_22118_4k	equ	255
interval_tl_40u_22118_4k	equ	183

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

; 0.3ms@24.000MHz -> th0,tl0=0fdh,A8h	; (65536-24000*.3/12)
interval_th_300u_24M		equ	253
interval_tl_300u_24M		equ	168

; 0.15ms@24.000MHz -> th0,tl0=0feh,d4h	; (65536-24000*.15/12)
interval_th_15u_24M		equ	254
interval_tl_15u_24M		equ	212

; 0.128ms@24.000MHz -> th0,tl0=0ffh,00h	; (65536-24000*.128/12)
interval_th_128u_24M		equ	255
interval_tl_128u_24M		equ	0

; 40mus@24MHz -> th0,tl0=0ffh,b0h	; (65536-24000*0.04/12)
interval_th_40u_24M		equ	255
interval_tl_40u_24M		equ	176

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
	org	03h	; external interrupt 0
;	ljmp	HandleInt0
;----------------------------
	org	0bh	; handle TF0
	ljmp	HandleTF0
;----------------------------
; int 1, connected to AT-keyboard clock line.
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
; TF0ModF=0:
; timer is used to measure the AT/PS2-clock-intervals
; Stop the timer after overflow, cleanup RX buffers
; RX timeout after 1 - 1.3ms
;
; TF0ModF=1: delay timer
;----------------------------------------------------------
HandleTF0:
	; stop timer
	clr	tr0

	jb	TF0ModF,timerAsClockTimer

	; --- timer used for AT/PS2 bus timeout
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
	clr	TF0ModF

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
;	clr	p1.2

	; start-bit must be 0
	jb	KbBitBufH.5, Int1Error
	; stop-bit must be 1
	jnb	KbBitBufL.7, Int1Error
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
	clr	p1.2
	sjmp	Int1Return

Int1Error:
; -- cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	p1.3
	sjmp	Int1Return

; --------------------------- AT/PS2 TX
Int1PS2TX:
	; -- reset RX bit buffer
	clr	PS2RXBitF
	setb	PS2TXAckF
	clr	p1.1
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
	setb	p1.1

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
;	setb	p1.2
;	setb	p1.3
	setb	p1.0
	pop	psw
	pop	acc
	reti

;----------------------------------------------------------
; timer 1 int handler:
;
; TF1ModF=0: delay timer
; timer is used as 16-bit alarm clock.
;
; TF1ModF=1:
; timer is used in 8-bit-auto-reload-mode to generate
; the Mac scancode clock with 2x150 microseconds timings.
;----------------------------------------------------------
HandleTF1:
	clr	p1.6
	jb	TF1ModF,timer1MacClock

	; --- timer used to generate delays
	dec	MacPauseCount
	clr	tr1
	setb	MiscSleepT1F
	clr	p1.5
	sjmp	HandleTF1End

timer1MacClock:
	; --- timer used as Mac-Clock-Driver
	push	acc
	push	psw
	jb	MacTxF,timer1MacClockTX

	; --- RX
	mov	c,MacBitCount.0
	jnc	timer1RXdoClock
	; --- on high clock, get a data bit
	mov	a,MacRXBitBuf
	mov	c,p3.4
	rrc	a
	mov	MacRXBitBuf,a
timer1RXdoClock:

	; --- the clock line
	mov	c,MacBitCount.0
	mov	p3.2,c		; drive clock line

	; --- check bit number
	mov	a,MacBitCount
	cjne	a,#0fh,timer1RXTXEnd

	; --- bit 8 is sent stop.
	clr	tr1
	clr	TF1ModF
	setb	MacTxF
	setb	p1.4
	setb	MacSleepInitF
	mov	a,MacRXBitBuf
	xrl	a,#4
	jz	timer1RXTXEnd
	mov	a,MacRXBitBuf
	mov	MacRXBuf,a
	setb	MacRXCompleteF
	sjmp	timer1RXTXEnd

	; --- TX
timer1MacClockTX:
	mov	c,MacBitCount.0
	jc	timer1TXdoClock
	; --- on low clock, set data line
	mov	a,MacTXBuf
	rrc	a
	mov	p3.4,c
	mov	MacTXBuf,a
timer1TXdoClock:

	; --- the clock line
	mov	c,MacBitCount.0
	mov	p3.2,c		; drive clock line

	; --- check bit number
	mov	a,MacBitCount
	cjne	a,#0fh,timer1RXTXEnd

	; --- bit 8 is sent stop.
	clr	tr1
	clr	TF1ModF
	clr	MacTxF
	clr	p1.4
	setb	MacSleepInitF
;	sjmp	timer1RXTXEnd

; --------------------------- done
timer1RXTXEnd:
	inc	MacBitCount
	pop	psw
	pop	acc

HandleTF1End:
	setb	p1.6
	reti

;----------------------------------------------------------
; AT/PS2 to Mac Plus translation table
;----------------------------------------------------------
AT2MacXlt0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  86h, 0a6h,  00h
AT2MacXlt1	DB	 00h, 0f6h,  8eh,  00h, 0aeh,  98h, 0a4h,  00h,   00h,  00h, 0b0h, 0c0h,  80h, 0d8h, 0e4h,  00h
AT2MacXlt2	DB	 00h,  88h, 0f0h, 0a0h, 0b8h, 0d4h,  94h,  00h,   00h, 0c6h, 0c8h, 0e0h, 0c4h, 0f8h, 0f4h,  00h
AT2MacXlt3	DB	 00h, 0dah, 0e8h,  90h, 0d0h,  84h, 0b4h,  00h,   00h,  00h, 0bah, 0b2h,  82h, 0ach,  9ch,  00h
AT2MacXlt4	DB	 00h, 0eah,  8ah, 0a2h, 0fch, 0dch, 0cch,  00h,   00h, 0fah,  9ah, 0d2h, 0cah, 0e2h, 0ech,  00h
AT2MacXlt5	DB	 00h,  00h, 0f2h,  00h, 0c2h,  8ch,  00h,  00h,  0ceh,  8eh,  92h, 0bch,  00h,  00h,  00h,  00h
AT2MacXlt6	DB	 00h, 0aah,  00h,  00h,  00h,  00h, 0e6h,  00h,   00h, 0e4h,  00h, 0b4h, 0cch,  00h,  00h,  00h
AT2MacXlt7	DB	0a4h, 0c0h,  94h, 0f4h,  8ch, 0ech, 0f0h,  88h,   00h, 0b0h, 0d4h, 0b8h, 0a0h,  9ch,  00h,  00h
AT2MacXlt8	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; AT/PS2 to Mac Plus translation extension table for Mac-Escape-Codes
; note: the two bits used here may also be encodedcoded
;	into bit 0 and bit 7 of AT2Macxlt0 / AT2MacXltE0
;	For better readability it is encoded explicitly here.
;
; bit 0: 9e escape
; bit 1: 8e,9e escape
; bit 4: PS2-E0-9e escape
; bit 5: PS2-E0-8e,9e escape
;----------------------------------------------------------
AT2MacEXlt0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacEXlt1	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacEXlt2	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacEXlt3	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacEXlt4	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  20h,  00h,  00h,  00h,  00h,  00h
AT2MacEXlt5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  10h,  00h,  00h,  00h,  00h,  00h
AT2MacEXlt6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  01h,  00h,  11h,  01h,  00h,  00h,  00h
AT2MacEXlt7	DB	 01h,  01h,  11h,  01h,  11h,  11h,  01h,  02h,   00h,  02h,  01h,  01h,  02h,  01h,  00h,  00h
AT2MacEXlt8	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; AT/PS2 to Mac Plus translation table for 0xE0-Escaped scancodes
;----------------------------------------------------------
AT2MacXltE0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacXltE1	DB	 00h, 0f6h,  00h,  00h, 0aeh,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacXltE2	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacXltE3	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacXltE4	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h, 0d8h,  00h,  00h,  00h,  00h,  00h
AT2MacXltE5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  98h,  00h,  00h,  00h,  00h,  00h
AT2MacxltE6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h, 0b0h,  00h,  00h,  00h,  00h
AT2MacXltE7	DB	 00h,  00h,  88h,  00h, 0a0h, 0d8h,  00h,  02h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
AT2MacXltE8	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

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

	; ------ Typematic surpressor
	jb	PS2RXBreakF,TranslateToBufTSBreak
	jb	PS2LastBreakF,TranslateToBufTSEnd
	sjmp	TranslateToBufTSBreakOk
TranslateToBufTSBreak:
	jnb	PS2LastBreakF,TranslateToBufTSEnd
TranslateToBufTSBreakOk:

	jb	PS2RXEscapeF,TranslateToBufTSEscape
	jb	PS2LastEscapeF,TranslateToBufTSEnd
	sjmp	TranslateToBufTSEscapeOk
TranslateToBufTSEscape:
	jnb	PS2LastEscapeF,TranslateToBufTSEnd
TranslateToBufTSEscapeOk:

	mov	a,RawBuf
	xrl	a,PS2LastBuf
	jnz	TranslateToBufTSEnd
	clr	PS2RXCompleteF
	ljmp	TranslateToBufEnd

TranslateToBufTSEnd:
	mov	c,PS2RXBreakF
	mov	PS2LastBreakF,c
	mov	c,PS2RXEscapeF
	mov	PS2LastEscapeF,c
	mov	a,RawBuf
	mov	PS2LastBuf,a

	; ------ Mechanical CapsLock-Switch emulation
	jb	PS2RXEscapeF,TranslateToBufNoCapsLock
	mov	a,RawBuf
	cjne	a,#58h,TranslateToBufNoCapsLock
	; ignore CapsLock Break Codes
	jnb	PS2RXBreakF,TranslateToBufCapsLockMake
	clr	PS2RXBreakF
	clr	PS2RXCompleteF
	ljmp	TranslateToBufEnd

TranslateToBufCapsLockMake:
	cpl	MacCapsLockF
	mov	c,MacCapsLockF
	cpl	c
	mov	PS2RXBreakF,c
	mov	p1.7,c

	; -- send LED-Command to PS2 keyboard
	mov	r2,#0edh
	call	RingBuf2CheckInsert
	mov	a,#0
	mov	c,PS2RXBreakF
	cpl	c
	mov	acc.2,c
	mov	r2,a
	call	RingBuf2CheckInsert
TranslateToBufNoCapsLock:

	; --- restore new scancode
	mov	a,RawBuf
	; keyboard disabled?
;	jb	FooBarDisableF,TranslateToBufEnd

	; --- translate and insert
	clr	PS2RXCompleteF
	jb	PS2RXEscapeF,TranslateToBufE0Esc
; --- normal single scancodes

	; --- check for Multi-Byte Mac Scancodes
	mov	dptr,#AT2MacEXlt0
	movc	a,@a+dptr
	mov	c,acc.0
	mov	MacMasq9eF,c
	mov	c,acc.1
	mov	MacMasq8e9eF,c

	; --- get Mac Scancode
	mov	a,RawBuf
	mov	dptr,#AT2MacXlt0
	movc	a,@a+dptr

	sjmp	TranslateToBufInsert

; --- 0xE0-escaped scancodes
TranslateToBufE0Esc:
	clr	PS2RXEscapeF

	; --- check for Multi-Byte Mac Scancodes
	mov	dptr,#AT2MacEXlt0
	movc	a,@a+dptr
	mov	c,acc.4
	mov	MacMasq9eF,c
	mov	c,acc.5
	mov	MacMasq8e9eF,c

	; --- get Mac Scancode
	mov	a,RawBuf
	mov	dptr,#AT2MacXltE0
	movc	a,@a+dptr

;	sjmp	TranslateToBufInsert

TranslateToBufInsert:
	; --- dont insert zeros
	jnz	TranslateToBufGo
	clr	PS2RXBreakF
	clr	PS2RXEscapeF
	clr	MacMasq9eF
	clr	MacMasq8e9eF
	sjmp	TranslateToBufEnd

TranslateToBufGo:
	; --- Mac Make/Break
	mov	c,PS2RXBreakF
	mov	acc.0,c
	clr	PS2RXBreakF
	mov	MacScancode,a

	; --- check for 9e escape code
	jnb	MacMasq9eF,TranslateToBufNo9e
	mov	r2,#9eh
	call	RingBuf1CheckInsert
TranslateToBufNo9e:

	; --- check for 8e9e escape code
	jnb	MacMasq8e9eF,TranslateToBufNo8e9e
	mov	a,#8eh
	mov	c,PS2RXBreakF
	mov	acc.0,c
	mov	r2,a
	call	RingBuf1CheckInsert
	mov	r2,#9eh
	call	RingBuf1CheckInsert
TranslateToBufNo8e9e:

	mov	a,MacScancode
	mov	r2,a
	call	RingBuf1CheckInsert
	mov	r2,#0deh
	call	RingBuf1CheckInsert

TranslateToBufEnd:
	ret

;----------------------------------------------------------
; Send heartbeat or data from the ring buffer to the computer
;----------------------------------------------------------
Buf1TX:
	; check if data is present in the ring buffer
	clr	c
	mov	a,RingBuf1PtrIn
	subb	a,RingBuf1PtrOut
	anl	a,#RingBuf1SizeMask
	jz	Buf1TXCheckHeartbeat

;	mov	MacPauseCount,#1
	; -- get data from buffer
	mov	a,RingBuf1PtrOut
	add	a,#RingBuf1
	mov	r0,a
	mov	a,@r0

	; -- send data
	mov	MacTxBuf,a
;	mov	p1,a
	call	timer1_init

	; -- increment output pointer
	inc	RingBuf1PtrOut
	anl	RingBuf1PtrOut,#RingBuf1SizeMask
	sjmp	Buf1TXEnd

Buf1TXCheckHeartbeat:
	mov	a,MacPauseCount
	jz	Buf1TXSendHeartbeat
	call	timer1_init_20ms
	sjmp	Buf1TXEnd

Buf1TXSendHeartbeat:
	; -- send heartbeat
	mov	MacTxBuf,#0deh
	call	timer1_init

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
	clr	ex1		; may diable input interrupt here
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
	setb	ex1
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
	setb	ex1		; may diable input interrupt here

Buf2TXEnd:
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
	clr	TF0ModF
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

	mov	th0, #interval_th_40u_11059_2k
	mov	tl0, #interval_tl_40u_11059_2k

	setb	TF0ModF
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

	mov	th0, #interval_th_1m_11059_2k
	mov	tl0, #interval_tl_1m_11059_2k

	setb	TF0ModF
	clr	MiscSleepF
	setb	et0		; (IE.3) enable timer 0 interrupt
	setb	tr0		; timer 0 run
	ret

;----------------------------------------------------------
; init timer 1 for interval timing
;----------------------------------------------------------
timer1_init_10ms:
	anl	tmod, #0fh	; clear all upper bits
	orl	tmod, #19h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 1, 16bit

	mov	th1, #interval_th_10m_11059_2k
	mov	tl1, #interval_tl_10m_11059_2k

	clr	TF1ModF
	clr	MiscSleepT1F
	setb	p1.5
	setb	et1		; enable timer 1 interrupt
	setb	tr1		; timer 1 run
	ret

;----------------------------------------------------------
; init timer 1 for interval timing
;----------------------------------------------------------
timer1_init_20ms:
	anl	tmod, #0fh	; clear all upper bits
	orl	tmod, #19h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 1, 16bit

	mov	th1, #interval_th_20m_11059_2k
	mov	tl1, #interval_tl_20m_11059_2k

	clr	TF1ModF
	clr	MiscSleepT1F
	setb	p1.5
	setb	et1		; enable timer 1 interrupt
	setb	tr1		; timer 1 run
	ret

;----------------------------------------------------------
; init timer 1 for interval timing (fast 8 bit reload)
; need 150mus intervals
;----------------------------------------------------------
timer1_init:
	clr	tr1

	anl	tmod, #0fh	; clear all lower bits
	orl	tmod, #20h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th1, #interval_t1_150u_11059_2k
	mov	tl1, #interval_t1_150u_11059_2k
	setb	et1		; (IE.1) enable timer 0 interrupt

	setb	TF1ModF		; see timer 1 interrupt code
	mov	MacBitCount,#0

	setb	tr1		; go
	ret

;----------------------------------------------------------
; Id
;----------------------------------------------------------
RCSId	DB	"$Id: kbdbabel_ps2_macplus_8051.asm,v 1.2 2007/06/28 10:13:41 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom
	; -- init UART and timer0/1
;	acall	uart_timer1_init
	acall	timer0_init
	clr	TF0ModF

	; -- enable interrupts int1
	setb	ex1		; external interupt 1 enable
	setb	it1		; falling edge trigger for int 1
	setb	px1		; high priority for int 1
	setb	it0		; falling edge trigger for int 0
	setb	ea

	; -- clear all flags
	mov	B20,#0
	mov	B21,#0
	mov	B22,#0

	; -- set PS2 clock and data line
	setb	p3.3
	setb	p3.5

	; -- init the ring buffers
	mov	RingBuf1PtrIn,#0
	mov	RingBuf1PtrOut,#0
	mov	RingBuf2PtrIn,#0
	mov	RingBuf2PtrOut,#0

;	; -- cold start flag
	setb	MiscSleepT1F
	clr	p1.5

;	; -- low repeat rate FIXME
	mov	r2,#0f3h
	call	RingBuf2CheckInsert
	mov	r2,#077h
	call	RingBuf2CheckInsert

; ----------------
Loop:
	; -- check AT/PS2 receive status
	jb	PS2RXCompleteF,LoopProcessATPS2Data

	; -- Mac receive status
	jb	MacRXCompleteF,LoopProcessMacData

	; -- send data to keyboard
	call	Buf2TX

	; -- check if Mac communication active.
	jb	TF1ModF,Loop

	; -- check if Mac delay is active.
	jnb	MiscSleepT1F,Loop

	jb	MacTxF,LoopMacTX
	sjmp	LoopMacRX

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
LoopProcessMacData
; -- AT/PS2 data received, process the received scancode into output ring buffer
	clr	MacRXCompleteF
	mov	a,MacRXBuf
	cjne	a,#68h,Loop
	; --- this seems to be the ID-Code for the German Mac-Plus keyboard
	mov	r2,#0d0h
	call	RingBuf1CheckInsert
	mov	r2,#0ceh
	call	RingBuf1CheckInsert
	; --- capslock release
	mov	r2,#0deh
	call	RingBuf1CheckInsert
	mov	r2,#0cfh
	call	RingBuf1CheckInsert
	sjmp	Loop

; ----------------
; Mac RX
LoopMacRX:
	jb	p3.4,Loop
	jnb	MacSleepInitF,LoopMacRXNoInit
	clr	MacSleepInitF
	; --- init delay
	mov	MacPauseCount,#1
	call	timer1_init_10ms
	sjmp	Loop
LoopMacRXNoInit:

	; -- receive data from computer
	call	timer1_init
	sjmp	Loop

; ----------------
; Mac TX
LoopMacTX:
	jnb	p3.4,Loop
	jnb	MacSleepInitF,LoopMacTXNoInit
	clr	MacSleepInitF
	; --- init delay
	mov	MacPauseCount,#13
	call	timer1_init_20ms
	sjmp	Loop
LoopMacTXNoInit:

;	mov	a,MacPauseCount
;	jz	LoopMacTXGo
;	call	timer1_init_20ms
;	sjmp	Loop
;LoopMacTXGo:

	; -- send data/heartbeat to computer
	call	Buf1TX
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
