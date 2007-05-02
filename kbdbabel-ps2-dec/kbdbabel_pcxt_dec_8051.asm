; ---------------------------------------------------------------------
; PC/XT to DEC LK201/LK401 keyboard transcoder for 8051 type processors.
; For shure, nobody will need this. Otherwise, please tell me.
; Just the development helper between pc-at and at-dec.
;
; $KbdBabel: kbdbabel_pcxt_dec_8051.asm,v 1.1 2007/04/17 10:04:51 akurz Exp $
;
; Clock/Crystal: 18.432MHz.
; 3.6864MHz or 7.3728 may do as well.
;
; PC/XT Keyboard connect:
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
; NumLock	- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; Wait		- p1.4	(Pin 5 on DIL40, Pin 16 on AT89C2051 PDIP20)
; TX buffer full- p1.3
; numlockfeature- p1.2
; 1/3 Volume	- p1.1	
; 1/9 Volume	- p1.0
; Buzzer	- p3.7 (Pin 11 on AT89C2051 PDIP20)
;
; Build:
; $ asl kbdbabel_pcxt_dec_8051.asm -o kbdbabel_pcxt_dec_8051.p
; $ p2bin -l \$ff kbdbabel_pcxt_dec_8051
; write kbdbabel_pcxt_dec_8051.bin on an empty 27C256 or AT89C2051
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
PCRXBitF	bit	20h.0	; RX-bit-buffer
PCRXCompleteF	bit	20h.1	; full and correct byte-received
PCRXActiveF	bit	20h.2	; receive in progress flag
PCXTBreakF	bit	20h.3	; Release/Break-Code flag
ATTXMasqF	bit	20h.4	; TX-AT-Masq-Char-Bit (send two byte scancode)
ATTXParF	bit	20h.5	; TX-AT-Parity bit
ATTFModF	bit	20h.6	; Timer modifier: alarm clock or clock driver
MiscSleepF	bit	20h.7	; sleep timer active flag
ATCommAbort	bit	21h.0	; AT communication aborted
ATHostToDevIntF	bit	21h.1	; host-do-device init flag triggered by ex1 / unused.
ATHostToDevF	bit	21h.2	; host-to-device flag for timer
ATTXActiveF	bit	21h.3	; AT TX active
ATCmdReceivedF	bit	21h.4	; full and correct AT byte-received
ATCmdResetF	bit	21h.5	; reset
LKCmdClrLedF	bit	21h.6	; LK command processing: clear LED
LKCmdSetLedF	bit	21h.7	; LK command processing: set LED
ATKbdDisableF	bit	22h.0	; Keyboard disable
LKModeNumLock_	bit	22h.1	; emulated NumLock-Mode, for arrow-keys on PC-Keyboard
PCXTTypematicF	bit	22h.2	; typematic scancode received

LKModSL		bit	23h.0	; LK modifier state storage: left shift
LKModSR		bit	23h.1	; LK modifier state storage: right shift
LKModAL		bit	23h.2	; LK modifier state storage: left alt
LKModAR		bit	23h.3	; LK modifier state storage: right alt
LKModC		bit	23h.4	; LK modifier state storage: ctrl

;------------------ octets
LKModAll	equ	23h	; collective access to stored LK modifier flags
KbBitBufL	equ	24h
KbBitBufH	equ	25h
KbClockMin	equ	26h
KbClockMax	equ	27h
ATBitCount	equ	28h	; AT scancode TX counter
LKLEDBuf	equ	29h	; must be bit-addressable
ATLEDBuf	equ	2ah	; must be bit-addressable
RawBuf		equ	30h	; raw PC/XT scancode
OutputBuf	equ	31h	; AT scancode
TXBuf		equ	32h	; AT scancode TX buffer
RingBufPtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
DECRXBuf	equ	35h	; DEC host-to-dev buffer
ATRXCount	equ	36h
DECBeepPCL	equ	37h	; Beep pulse counter, 8 low bits
DECBeepPCH	equ	38h	; Beep pulse counter, more bits
PCXTLastBuf	equ	39h	; last scancode received
;KbClockIntBuf	equ	33h

;------------------ arrays
RingBuf		equ	40h
RingBufSizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	50h	; the stack

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
	setb	PCRXBitF
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
; buffer: r5
;----------------------------------------------------------
HandleInt0:
	push	acc
	push	psw

	; receive in progress flag
	setb	PCRXActiveF
; --------------------------- diag: check if PCXT-RX happens during AT-TX
;	clr	p1.7		; @@@@@@@@@@ FIXME
	; check if flag is set
	jnb	ATTXActiveF,interCharFlagOk
;	clr	p1.4				; @@@@@@@@@@ FIXME
	sjmp	interCharTestEnd
interCharFlagOk:
;	setb	p1.4			; @@@@@@@@@@ FIXME
interCharTestEnd:
; --------------------------- get and save data samples
; -- write to mem, first 8 bits
	mov	c,PCRXBitF	; new bit
	mov	a,KbBitBufL
	rrc	a
	mov	KbBitBufL,a

; -- write to mem, upper bits
	mov	a,KbBitBufH
	rrc	a
	mov	KbBitBufH,a

; -- diag: write data bits to LED-Port
;	mov	a,KbBitBufL
;	xrl	a,0FFh
;	mov	p1,a

; -- reset bit buffer
	clr	PCRXBitF

; --------------------------- get and save clock timings
; this is an optional extra-check for the received data.
; The PC/XT-Protocol consists of 8 equally spaced clock cycles proceeded by
; one clock cycle of double length. These intervals are checked here.
; For diagnosis purposes the timing samples can be send via serial line.
; -- diag: time interval buffer address KbClockIntBuf
;	mov	a,r7
;	add	a,#KbClockIntBuf
;	mov	r1,a

; -- save and restart timer
	; stop timer 0
	clr	tr0

	; 11 bit from 16-bit timer.
	mov	a,th0
	anl	a,#07h		; 3 high bits from th0
	rr	a
	rr	a
	rr	a
	mov	r5, a

	mov	a,tl0
	anl	a,#0F8h		; 5 low bits
	rr	a
	rr	a
	rr	a
	orl	a, r5
	mov	r6,a

;	; diag: save clock samples
;	mov	@r1,a

	; reset timer value
	mov	th0, #interval_th_11_bit
	mov	tl0, #interval_tl_11_bit

	; start timer 0
	setb	tr0

; --------------------------- consistancy checks
; -- checks by bit number
	mov	a,r7
	jz	Int0Return	; bit zero
	dec	a
	jz	Int0StartBit	; start bit
	clr	c
	subb	a,#08h
	mov	r5,a		; save clock bit count result

; -- data check clock timings
	clr	c
	mov	a, r6
	subb	a, KbClockMin
	jc	Int0Error

	mov	a, r6
	clr	c
	subb	a, KbClockMax
	jnc	Int0Error

	mov	a,r5
	jnz	Int0Return

; -- special handling for last bit: output
	; start-bit must be 1
	jnb	KbBitBufH.7, Int0Error
	setb	p1.3		; error LED off
	mov	a, KbBitBufL
	mov	RawBuf, a
	mov	r7,#0
	setb	PCRXCompleteF	; fully received flag
	clr	PCRXActiveF	; receive in progress flag
	sjmp	Int0Return

Int0StartBit:
; -- start bit: calculate timings
	clr	PCRXCompleteF
	mov	a,r6
	clr	c
	rrc	a
	clr	c
	rrc	a
	mov	KbClockMin,a
	add	a,acc
	add	a,acc
	mov	KbClockMax,a
	anl	KbBitBufL,#0f0h
	mov	KbBitBufH,#0
	sjmp	Int0Return

Int0Error:
; -- cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0
	clr	p1.3		; error LED on

; --------------------------- done
Int0Return:
; -- inc the bit counter
	inc	r7
;	setb	p1.7			; @@@@@@@@@@ FIXME
	pop	psw
	pop	acc
	reti

;----------------------------------------------------------
; timer 0 int handler:
; timer is used to measure the clock-signal-interval length
; Stop the timer after overflow, cleanup RX buffers
; RX timeout after 1 - 1.3ms
;----------------------------------------------------------
HandleTF0:
	cpl	p3.7			; @@@@@@@@@@@ TESTING

	; stop timer
	clr	tr0

	; cleanup buffers
	mov	KbBitBufL,#0
	mov	KbBitBufH,#0
	mov	r7,#0

	; reset timer value
	mov	th0, #interval_th_11_bit
	mov	tl0, #interval_tl_11_bit

	reti

;----------------------------------------------------------
; PC/XT to DEC LK translaton table
; F1-F10 are shifted to F11-F20
;----------------------------------------------------------
PCXT2DECxlt0	DB	 00h, 0bfh, 0c0h, 0c5h, 0cbh, 0d0h, 0d6h, 0dbh,  0e0h, 0e5h, 0eah, 0efh, 0f9h, 0f5h, 0bch, 0beh
PCXT2DECxlt1	DB	0c1h, 0c6h, 0cch, 0d1h, 0d7h, 0dch, 0e1h, 0e6h,  0ebh, 0f0h, 0fah, 0f6h, 0bdh, 0afh, 0c2h, 0c7h
PCXT2DECxlt2	DB	0cdh, 0d2h, 0d8h, 0ddh, 0e2h, 0e7h, 0ech, 0f2h,  0fbh, 0bfh, 0aeh, 0f7h, 0c3h, 0c8h, 0ceh, 0d3h
PCXT2DECxlt3	DB	0d9h, 0deh, 0e3h, 0e8h, 0edh, 0f3h, 0abh,  00h,  0ach, 0d4h, 0b0h, 071h, 072h, 073h, 074h, 07ch
PCXT2DECxlt4	DB	07dh, 080h, 081h, 082h, 083h,  00h,  00h, 09dh,  09eh, 09fh, 0a0h, 099h, 09ah, 09bh,  00h, 096h
PCXT2DECxlt5	DB	097h, 098h, 092h, 094h,  00h,  00h,  00h, 071h,  072h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
PCXT2DECxlt6	DB	 00h,  00h,  00h,  00h,  00h, 071h, 072h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
PCXT2DECxlt7	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h


;----------------------------------------------------------
; PC/XT to DEC LK translaton table
; Num Keys are in Arrow/PgUp/Dn/Del/Ins-Mode
;----------------------------------------------------------
PCXT2DECxltm0	DB	 00h, 0bfh, 0c0h, 0c5h, 0cbh, 0d0h, 0d6h, 0dbh,  0e0h, 0e5h, 0eah, 0efh, 0f9h, 0f5h, 0bch, 0beh
PCXT2DECxltm1	DB	0c1h, 0c6h, 0cch, 0d1h, 0d7h, 0dch, 0e1h, 0e6h,  0ebh, 0f0h, 0fah, 0f6h, 0bdh, 0afh, 0c2h, 0c7h
PCXT2DECxltm2	DB	0cdh, 0d2h, 0d8h, 0ddh, 0e2h, 0e7h, 0ech, 0f2h,  0fbh, 0bfh, 0aeh, 0f7h, 0c3h, 0c8h, 0ceh, 0d3h
PCXT2DECxltm3	DB	0d9h, 0deh, 0e3h, 0e8h, 0edh, 0f3h, 0abh,  00h,  0ach, 0d4h, 0b0h, 056h, 057h, 058h, 059h, 05ah
PCXT2DECxltm4	DB	064h, 065h, 066h, 067h, 068h,  00h,  00h, 08ah,  0aah, 08eh, 0a0h, 0a7h, 09ah, 0a8h,  00h, 08dh
PCXT2DECxltm5	DB	0a9h, 08fh, 08bh, 08ch,  00h,  00h,  00h, 071h,  072h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
PCXT2DECxltm6	DB	 00h,  00h,  00h,  00h,  00h, 071h, 072h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
PCXT2DECxltm7	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; PC/XT to DEC LK translaton table
; special key flags
;   bit 0: key is modifier key
;   bit 1: ignore PCXT typematic
;----------------------------------------------------------
;PCXT2DECxlte0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
;PCXT2DECxlte1	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  03h,  00h,  00h
;PCXT2DECxlte2	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  03h,  00h,  00h,  00h,  00h,  00h,  00h
;PCXT2DECxlte3	DB	 00h,  00h,  00h,  00h,  00h,  00h,  03h,  00h,   03h,  00h,  02h,  00h,  00h,  00h,  00h,  00h
;PCXT2DECxlte4	DB	 00h,  00h,  00h,  00h,  00h,  02h,  02h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
;PCXT2DECxlte5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
;PCXT2DECxlte6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
;PCXT2DECxlte7	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; ring buffer insertion helper. Input Data comes in r2
;----------------------------------------------------------
RingBufCheckInsert:
	; check for ring buffer overflow
	mov	a,RingBufPtrOut
	setb	c
	subb	a,RingBufPtrIn
	anl	a,#RingBufSizeMask
	jz	RingBufFull

	; some space left, insert data
	mov	a,RingBufPtrIn
	add	a,#RingBuf
	mov	r0,a
	mov	a,r2
	mov	@r0,a

	; increment pointer
	inc	RingBufPtrIn
	anl	RingBufPtrIn,#RingBufSizeMask
	ret

RingBufFull:
	; error routine
	clr	p1.3
	ret

;----------------------------------------------------------
; Get received data and translate it into the ring buffer
;----------------------------------------------------------
TranslateToBufDEC:
	; translate from PC/XT to DEC LK scancode
	mov	a,RawBuf

	; clear received data flag
	clr	PCRXCompleteF

	; -- check if scancode is typematic
	clr	PCXTTypematicF
	cjne	a,PCXTLastBuf,TranslateToBufTypematicPassed
	setb	PCXTTypematicF
TranslateToBufTypematicPassed:
	; save scancode for typematic-eleminator
	mov	PCXTLastBuf,a

	; -- save make/break bit 7
	mov	c,acc.7
	mov	PCXTBreakF,c

	; -- clear make/break bit 7
	anl	a,#7fh

	; -- check for modifier key codes
	; - make and break codes must be translated
	; - make codes generated by typematic must be filtered
	; - keypress status will be saved in LKMod
	cjne	a,#02ah,TranslateToBufNot2a	; Shift L
	mov	c,PCXTBreakF
	cpl	c
	mov	LKModSL,c
	sjmp	TranslateToBufModKey
TranslateToBufNot2a:
	cjne	a,#036h,TranslateToBufNot36	; Shift R
	mov	c,PCXTBreakF
	cpl	c
	mov	LKModSR,c
	sjmp	TranslateToBufModKey
TranslateToBufNot36:
	cjne	a,#1dh,TranslateToBufNot1d	; Ctrl
	mov	c,PCXTBreakF
	cpl	c
	mov	LKModC,c
	sjmp	TranslateToBufModKey
TranslateToBufNot1d:
	cjne	a,#038h,TranslateToBufNot38	; Alt
	mov	c,PCXTBreakF
	cpl	c
	mov	LKModAL,c
	sjmp	TranslateToBufModKey
TranslateToBufNot38:

	; -- ignore break / key release codes for non-modifier keys
	jnb	PCXTBreakF,TranslateToBufNoBreak
	sjmp	TranslateToBufEnd
TranslateToBufNoBreak:

	; --- check non-typematic keys
	; make codes generated by typematic must be filtered
	cjne	a,#03ah,TranslateToBufNot3a	; CapsLock
	sjmp	TranslateToBufNoTypematic
TranslateToBufNot3a:
	cjne	a,#045h,TranslateToBufNot45	; NumLock
	sjmp	TranslateToBufNoTypematic
TranslateToBufNot45:
	cjne	a,#046h,TranslateToBufNot46	; ScrollLock
	sjmp	TranslateToBufNoTypematic
TranslateToBufNot46:
	sjmp	TranslateToBufGo

TranslateToBufModKey:
	; -- check if last modifier is released
	mov	r3,a
	mov	a,LKModAll
	jz	TranslateToBufAllModRel
	mov	a,r3
	sjmp	TranslateToBufNoTypematic

TranslateToBufAllModRel:
	; send \xb3 "all modifiers released"
	mov	r2, #0b3h
	call	RingBufCheckInsert
	sjmp	TranslateToBufEnd

TranslateToBufNoTypematic:
	; --- filter typematic
	jnb	PCXTTypematicF,TranslateToBufNoTypematicKey
	sjmp	TranslateToBufEnd
TranslateToBufNoTypematicKey:

	; -- check for NumLock to switch mode
	cjne	a,#045h,TranslateToBufNot45_2
	cpl	LKModeNumLock_
	mov	c,LKModeNumLock_
	mov	p1.2,c
	clr	c
	sjmp	TranslateToBufEnd
TranslateToBufNot45_2:

TranslateToBufGo:
	; -- process scancode
	jb	LKModeNumLock_,PCXT2DECArrowMode
	; get NumLock-Mode LK scancode
	mov	dptr,#PCXT2DECxlt0
	movc	a,@a+dptr
	sjmp	PCXT2DECEnd

PCXT2DECArrowMode:
	; get Arrow-Mode LK scancode
	mov	dptr,#PCXT2DECxltm0
	movc	a,@a+dptr

PCXT2DECEnd:
	mov	OutputBuf,a

;	; keyboard disabled?
;	jb	ATKbdDisableF,TranslateToBufEnd

	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert

TranslateToBufEnd:
	ret

;----------------------------------------------------------
; Send data from the ring buffer
;----------------------------------------------------------
	; -- send ring buffer contents
BufTX:
	; check if data is present in the ring buffer
	clr	c
	mov	a,RingBufPtrIn
	subb	a,RingBufPtrOut
	anl	a,#RingBufSizeMask
	jz	BufTXEnd

;	clr	p1.1				; @@@@@@@@@@ FIXME
	; -- get data from buffer
	mov	a,RingBufPtrOut
	add	a,#RingBuf
	mov	r0,a
	mov	a,@r0

	; -- send data
	mov	sbuf,a		; 8 data bits
	clr	TI

	; -- increment output pointer
	inc	RingBufPtrOut
	anl	RingBufPtrOut,#RingBufSizeMask

BufTXEnd:
;	setb	p1.1				; @@@@@@@@@@ FIXME
	ret

;----------------------------------------------------------
; check and respond to received DEC commands
;----------------------------------------------------------
DECCmdProc:
	; -- get received DEC LK command
	mov	a,DECRXBuf

	; -- argument for 0x11 command: clear keyboard LED
	jnb	LKCmdClrLedF,DECCPNotClrLEDarg
	clr	LKCmdClrLedF
	anl	a,#0fh
	cpl	a
	anl	LKLEDBuf,a
	sjmp	DECCPLEDarg

DECCPNotClrLEDarg:
	; -- argument for 0x13 command: set keyboard LED
	jnb	LKCmdSetLedF,DECCPNotSetLEDarg
	clr	LKCmdSetLedF
	anl	a,#0fh
	orl	LKLEDBuf,a
;	sjmp	DECCPLEDarg

DECCPLEDarg:
	; -- process LED buffer
	; Wait
	mov	c,acc.0
	cpl	c
	mov	p1.4,c
	; Compose to NumLock
	mov	c,acc.1
	mov	ATLEDBuf.1,c
	cpl	c
	mov	p1.5,c
	mov	p1.0,c		; @@@@@@@@@@@@@ TESTING
	; CapsLock
	mov	c,acc.2
	mov	ATLEDBuf.2,c
	cpl	c
	mov	p1.6,c
	mov	p1.1,c		; @@@@@@@@@@@@@ TESTING
	; ScrollLock
	mov	c,acc.3
	mov	ATLEDBuf.0,c
	cpl	c
	mov	p1.7,c
	sjmp	DECCPDone

DECCPNotSetLEDarg:
	; -- command 0xfd: keyboard reset. send POST code \x01\x00\x00\x00
	cjne	a,#0fdh,DECCPNotFD
	mov	r2,#01h
	call	RingBufCheckInsert
	mov	r2,#00h
	call	RingBufCheckInsert
	mov	r2,#00h
	call	RingBufCheckInsert
	mov	r2,#00h
	call	RingBufCheckInsert
	sjmp	DECCPDone
DECCPNotFD:
	; -- command 0x0A
	cjne	a,#0Ah,DECCPNot0A
	sjmp	DECCPSendAck
DECCPNot0A:
	; -- command 0x11: clear LED
	cjne	a,#11h,DECCPNot11
	setb	LKCmdClrLedF
	sjmp	DECCPDone
DECCPNot11:
	; -- command 0x13: set LED
	cjne	a,#13h,DECCPNot13
	setb	LKCmdSetLedF
	sjmp	DECCPDone
DECCPNot13:
	; -- command 0x1A
	cjne	a,#1Ah,DECCPNot1A
	sjmp	DECCPSendAck
DECCPNot1A:
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
	sjmp	DECCPDone

DECCPSendAck:
	mov	r2,#0BAh
	call	RingBufCheckInsert
;	sjmp	DECCPDone

DECCPDone:
	ret

;----------------------------------------------------------
; init uart with timer 1 as baudrate generator for 4800 BPS
;----------------------------------------------------------
uart_timer1_init:
	mov	scon, #050h	; uart mode 1 (8 bit), single processor
	orl	tmod, #020h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 2, 8bit-auto-reload
	orl	pcon, #080h	; SMOD, bit 7 in PCON

	mov	th1, #uart_t1_4800_18432k
	mov	tl1, #uart_t1_4800_18432k

	clr	es		; disable serial interrupt
	setb	tr1

	clr	ri
	setb	ti

	ret

;----------------------------------------------------------
; init timer 0 for PC/XT interval timing, timeout=1ms
;----------------------------------------------------------
timer0_init:
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit

	mov	th0, #interval_th_11_bit
	mov	tl0, #interval_tl_11_bit

	setb	et0		; (IE.3) enable timer 0 interrupt
	setb	tr0		; timer 0 run
	ret

;----------------------------------------------------------
; init timer 0 as buzzer driver
;----------------------------------------------------------
timer0_init_beep:
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit

	mov	th0, #interval_th_11_bit
	mov	tl0, #interval_tl_11_bit

	setb	et0		; (IE.3) enable timer 0 interrupt
	setb	tr0		; timer 0 run
	ret


;DECBeepPCL
;DECBeepPCH

;----------------------------------------------------------
; Id
;----------------------------------------------------------
RCSId	DB	"$Id: kbdbabel_pcxt_dec_8051.asm,v 1.1 2007/05/02 08:37:33 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom
	; -- init UART and timer0/1
	acall	uart_timer1_init
	acall	timer0_init

	; -- enable interrupts int0
	setb	ex0		; external interupt 0 enable
	setb	it0		; falling edge trigger for int 0
	setb	ea

	; -- clear buffers and all flags
	mov	20h,#0
	mov	21h,#0
	mov	22h,#0
	mov	LKLEDBuf,#0
	mov	ATLEDBuf,#0
	mov	LKModAll,#0

	; -- init the ring buffer
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0

;	; -- cold start flag
;	setb	ATCmdResetF

; ----------------
Loop:
	; -- check PC/XT receive status
	jb	PCRXCompleteF,LoopProcessPCXTData

	; -- check on new DEC/LK data received on serial line
	jb	RI, LoopProcessLKcmd

	; -- loop if serial TX is active
	jnb	TI, Loop

	; send data
	call	BufTX

	; -- loop
	sjmp Loop

;----------------------------------------------------------
; helpers for the main loop
;----------------------------------------------------------
; ----------------
LoopProcessPCXTData:
; -- PC/XT data received, process the received scancode into output ring buffer
	call	TranslateToBufDEC
	sjmp	Loop

; ----------------
LoopProcessLKcmd:
; -- commands from DEC host received via serial line
;	clr	p1.6				; @@@@@@@@@@ FIXME
	mov	a,sbuf
	mov	DECRXBuf,a
	clr	RI
	acall	DECCmdProc
;	setb	p1.6				; @@@@@@@@@@ FIXME
	sjmp	Loop

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	"   Copyright 2006 by Alexander Kurz"
LIC02	DB	"   "
GPL01	DB	"   This program is free software; you can redistribute it and/or modify"
GPL02	DB	"   it under the terms of the GNU General Public License as published by"
GPL03	DB	"   the Free Software Foundation; either version 2, or (at your option)"
GPL04	DB	"   any later version."
GPL05	DB	"   "
GPL06	DB	"   This program is distributed in the hope that it will be useful,"
GPL07	DB	"   but WITHOUT ANY WARRANTY; without even the implied warranty of"
GPL08	DB	"   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the"
GPL09	DB	"   GNU General Public License for more details."
GPL10	DB	"   "
; ----------------
	end
