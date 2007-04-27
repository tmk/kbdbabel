; ---------------------------------------------------------------------
; AT/PS2 to Sun keyboard transcoder for 8051 type processors.
;
; $Id: kbdbabel_ps2_sun_8051.asm,v 1.1 2007/04/27 18:42:29 akurz Exp $
;
; Clock/Crystal: 18.432MHz.
;
; AT/PS2 Keyboard connect:
; This two pins need externals 4.7k resistors as pullup.
; DATA - p3.4   (Pin 14 on DIL40, Pin 8 on AT89C2051 PDIP20)
; CLOCK - p3.2  (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
;
; Sun Host/Computer connect:
; Sun4/5/6: Inverted signal using transistors and 4.7k resistors
; is connected to the serial port lines
; Sun3: RS232 level using a MAX232-IC
; RxD - p3.0 (Pin 10 on DIL40, Pin 2 on AT89C2051 PDIP20)
; TxD - p3.1 (Pin 11 on DIL40, Pin 3 on AT89C2051 PDIP20)
;
; LED-Output connect:
; LEDs are connected with 220R to Vcc
; buzzer		- p1.7	(Pin 8 on DIL40, Pin 19 on AT89C2051 PDIP20)
; AT/PS2 RX error	- p1.6	(Pin 7 on DIL40, Pin 18 on AT89C2051 PDIP20)
; AT/PS2 RX Parity error- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; Ring buffer full	- p1.4	(Pin 5 on DIL40, Pin 16 on AT89C2051 PDIP20)
; Compose	- p1.3	(Pin 4 on DIL40, Pin 15 on AT89C2051 PDIP20)
; ScrollLock	- p1.2	(Pin 3 on DIL40, Pin 14 on AT89C2051 PDIP20)
; CapsLock	- p1.1	(Pin 2 on DIL40, Pin 13 on AT89C2051 PDIP20)
; NumLock	- p1.0	(Pin 1 on DIL40, Pin 12 on AT89C2051 PDIP20)
;
; Build:
; $ asl kbdbabel_ps2_sun_8051.asm -o kbdbabel_ps2_sun_8051.p
; $ p2bin -l \$ff kbdbabel_ps2_sun_8051
; write kbdbabel_ps2_sun_8051.bin on an empty 27C256 or AT89C2051
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
SunCmdLedF	bit	22h.0	; Sun command processing: set LED
SunKbdKeyClickF	bit	22h.1	; Sun Keyboard feature: Keyclick
BuzzerBufF	bit	22h.2	; Store Buzzer state here

;------------------ octets
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
PS2RXLastBuf	equ	37h	; Last received scancode
PS2LedBuf	equ	38h	; LED state buffer for PS2 Keyboard
SunRXBuf	equ	39h	; Sun host-to-dev buffer

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
	; start-bit must be 0
	jb	KbBitBufH.5, Int0Error
	; stop-bit must be 1
	jnb	KbBitBufL.7, Int0Error
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
	jb      p,Int0RXParityBitPar
	jnc	Int0ParityError
	sjmp	Int0Output

Int0RXParityBitPar:
	jc	Int0ParityError

Int0Output:
	; -- return received byte
;	jnb	SunKbdKeyClickF,Int0OutputNoClick
;	setb	p3.7	; buzzer on
;Int0OutputNoClick:
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
	clr	p1.5
	sjmp	Int0Return

Int0Error:
; -- cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	p1.6
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
; AT/PS2 to Sun translaton table
;----------------------------------------------------------
ATPS22Sunxlt0	DB	  00h, 012h, 010h, 00ch, 008h, 005h, 006h, 00bh,   00h, 007h, 011h, 00eh, 00ah, 035h, 02ah,  00h
ATPS22Sunxlt1	DB	 00h, 013h, 063h,  00h, 04ch, 036h, 01eh,  00h,   00h,  00h, 064h, 04eh, 04dh, 037h, 01fh,  00h
ATPS22Sunxlt2	DB	 00h, 066h, 065h, 04fh, 038h, 021h, 020h,  00h,   00h, 079h, 067h, 050h, 03ah, 039h, 022h,  00h
ATPS22Sunxlt3	DB	 00h, 069h, 068h, 052h, 051h, 03bh, 023h,  00h,   00h,  00h, 06ah, 053h, 03ch, 024h, 025h,  00h
ATPS22Sunxlt4	DB	 00h, 06bh, 054h, 03dh, 03eh, 027h, 026h,  00h,   00h, 06ch, 06dh, 055h, 056h, 03fh, 028h,  00h
ATPS22Sunxlt5	DB	 00h,  00h, 057h,  00h, 040h, 029h,  00h,  00h,  077h, 06eh, 059h, 041h,  00h, 058h,  00h,  00h
ATPS22Sunxlt6	DB	 00h, 07ch,  00h,  00h,  00h,  00h, 02bh,  00h,   00h, 070h,  00h, 05bh, 044h,  00h,  00h,  00h
ATPS22Sunxlt7	DB	05eh, 032h, 071h, 05ch, 05dh, 045h, 01dh, 062h,  009h, 07dh, 072h, 047h, 02fh, 046h, 017h, 016h
ATPS22Sunxlt8	DB	 00h,  00h,  00h,  10h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22Sunxlt9	DB	 00h, 00dh,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h, 078h
ATPS22Sunxlta	DB	 00h, 002h,  00h, 02dh,  00h,  00h,  00h, 07ah,  001h,  00h,  00h,  00h,  00h,  00h,  00h, 043h
ATPS22Sunxltb	DB	 00h,  00h, 004h,  00h,  00h,  00h,  00h, 030h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22Sunxltc	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h, 02eh,  00h,  00h,  00h,  00h,  00h
ATPS22Sunxltd	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h, 05ah,  00h,  00h,  00h,  00h,  00h
ATPS22Sunxlte	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h, 04ah,  00h, 018h, 034h,  00h,  00h, 00fh
ATPS22Sunxltf	DB	02ch, 042h, 01bh, 00fh, 01ch, 014h,  00h, 015h,   00h,  00h, 07bh,  00h, 016h, 060h, 015h,  00h

;----------------------------------------------------------
; AT/PS2 to Sun translaton table for 0xE0-Escaped scancodes
; Note: Ctrl-R (E014h) is mapped like Ctrl-L (14h)
; todo: PrtScreen (E012E07C)
;----------------------------------------------------------
ATPS22SunxltE0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltE1	DB	 00h,  0dh,  00h,  00h,  4ch,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltE2	DB	 00h,  02h,  00h,  2dh,  00h,  00h,  00h,  7ah,   01h,  00h,  00h,  00h,  00h,  00h,  00h,  78h
ATPS22SunxltE3	DB	 00h,  00h,  04h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltE4	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  2eh,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltE5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  5ah,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltE6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  4ah,  00h,  18h,  34h,  00h,  00h,  00h
ATPS22SunxltE7	DB	 2ch,  42h,  1bh,  00h,  1ch,  14h,  00h,  00h,   00h,  00h,  7bh,  00h,  00h,  60h,  00h,  00h
ATPS22SunxltE8	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltE9	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltEa	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltEb	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltEc	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltEd	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltEe	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
ATPS22SunxltEf	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
;----------------------------------------------------------
; ATPS22Sun
; Helper, translate normal AT/PS2 to Sun scancode
; input: dptr: table address, a: AT/PS2 scancode
;----------------------------------------------------------
ATPS22Sun:
	jb	PS2RXEscapeF,ATPS22SunEsc

; --- normal single scancodes
	mov	dptr,#ATPS22Sunxlt0
	movc	a,@a+dptr
	sjmp	ATPS22SunEnd

; --- 0xE0-escaped scancodes
ATPS22SunEsc:
	clr	PS2RXEscapeF
	mov	dptr,#ATPS22SunxltE0
	movc	a,@a+dptr
;	sjmp	ATPS22SunEnd

ATPS22SunEnd:
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
	clr	p1.4
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
	; save buzzer-state
	mov	c,p1.7
	mov	BuzzerBufF,c

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

	; keyclick-feature
	jnb	SunKbdKeyClickF,TranslateToBufNoclick
	jb	PS2RXBreakF,TranslateToBufNoclick
	setb	p1.7
TranslateToBufNoclick:

	; --- restore new scancode
	mov	a,RawBuf

	; keyboard disabled?
;	jb	FooBarDisableF,TranslateToBufEnd

	; --- translate
	clr	PS2RXCompleteF
	call	ATPS22Sun

	; --- dont insert zeros
	jz	TranslateToBufEnd

	; --- insert
TranslateToBufInsert:
	; restore make/break bit 7
	mov	c,PS2RXBreakF
	mov	acc.7,c
	clr	c

	; insert into buf
	mov	r2, a
	call	RingBuf1CheckInsert

	clr	PS2RXEscapeF

	; FIXME: will send "all keys released after break code"
	; insert into buf
	jnb	PS2RXBreakF,TranslateToBufEnd
	clr	PS2RXBreakF
	mov	r2, #7fh
	call	RingBuf1CheckInsert

TranslateToBufEnd:
	; restore buzzer-state
	mov	c,BuzzerBufF
	mov	p1.7,c

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
; check and respond to received Sun commands
;----------------------------------------------------------
SunCmdProc:
	; -- get received Sun LK command
	mov	a,SunRXBuf

	; -- argument for 0xe command: set keyboard LED
	jnb	SunCmdLedF,SunCPNotEDarg
	clr	SunCmdLedF
	; NumLock
	mov	c,acc.0
	cpl	c
	mov	p1.0,c
	; CapsLock
	mov	c,acc.3
	cpl	c
	mov	p1.1,c
	; ScrollLock
	mov	c,acc.2
	cpl	c
	mov	p1.2,c
	; Compose
	mov	c,acc.1
	cpl	c
	mov	p1.3,c
	; -- output to AT/PS2 Keyboard
	swap	a
	; ScrollLock
	mov	c,acc.6
	mov	acc.0,c
	; CapsLock
	mov	c,acc.7
	mov	acc.2,c
	; NumLock
	mov	c,acc.4
	mov	acc.1,c
	anl	a,#07h

	; -- check if LEDs changed
	cjne	a,PS2LedBuf,SunCPLedTX2PS2
	sjmp	SunCPDone
SunCPLedTX2PS2:
	; -- send to PS2 keyboad
	mov	PS2LedBuf,a
	mov	r2,#0edh
	call	RingBuf2CheckInsert
	mov	a,PS2LedBuf
	mov	r2,a
	call	RingBuf2CheckInsert
	sjmp	SunCPDone

SunCPNotEDarg:
	; -- command 0x1: keyboard reset. send POST code \xff\x04\x7f\xfe\x25
	cjne	a,#01h,SunCPNot01
	mov	r2,#0ffh
	call	RingBuf1CheckInsert
	mov	r2,#04h
	call	RingBuf1CheckInsert
	mov	r2,#7fh
	call	RingBuf1CheckInsert
	mov	r2,#0feh
	call	RingBuf1CheckInsert
	mov	r2,#25h
	call	RingBuf1CheckInsert
	sjmp	SunCPDone
SunCPNot01:
	; -- command 0x2: beep on
	cjne	a,#02h,SunCPNot02
	setb	p1.7
SunCPNot02:
	; -- command 0x3: beep off
	cjne	a,#03h,SunCPNot03
	clr	p1.7
SunCPNot03:
	; -- command 0xa: keyclick on
	cjne	a,#0ah,SunCPNot0a
	setb	SunKbdKeyClickF
SunCPNot0a:
	; -- command 0xb: keyclick off
	cjne	a,#0bh,SunCPNot0b
	clr	SunKbdKeyClickF
SunCPNot0b:
	; -- command 0x0e	; LEDs
	cjne	a,#0eh,SunCPNot0e
	setb	SunCmdLedF
	sjmp	SunCPDone
SunCPNot0e:
	cjne	a,#0fh,SunCPNot0f
	sjmp	SunCPSendAck
SunCPNot0f:
	sjmp	SunCPDone

SunCPSendAck:
	mov	r2,#0h
	call	RingBuf1CheckInsert
;	sjmp	SunCPDone

SunCPDone:
	ret

;----------------------------------------------------------
; init uart with timer 1 as baudrate generator for 1200 BPS
;----------------------------------------------------------
uart_timer1_init:
	mov	scon, #050h	; uart mode 1 (8 bit), single processor
	orl	tmod, #020h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 2, 8bit-auto-reload
	orl	pcon, #080h	; SMOD, bit 7 in PCON

	mov	th1, #uart_t1_1200_18432k
	mov	tl1, #uart_t1_1200_18432k

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
RCSId	DB	"$Id: kbdbabel_ps2_sun_8051.asm,v 1.1 2007/04/27 18:42:29 akurz Exp $"

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

	; -- mute the anoying buzzer
	clr	p1.7
	clr	SunKbdKeyClickF

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
	jb	RI, LoopProcessSunCmd

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
LoopProcessSunCmd:
; -- commands from Sun host received via serial line
	mov	a,sbuf
	mov	SunRXBuf,a
	clr	RI

	acall	SunCmdProc
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

