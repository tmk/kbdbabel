; ---------------------------------------------------------------------
; Wyse WY-85 to AT/PS2 keyboard transcoder for 8051 type processors
;
; $KbdBabel: kbdbabel_wy85_ps2_8051.asm,v 1.3 2007/06/27 22:11:56 akurz Exp $
;
; Clock/Crystal: 24MHz.
;
; WY85 Keyboard connect:
; DATA - p3.4   (Pin 14 on DIL40, Pin 8 on AT89C2051 PDIP20)
; CLOCK - p3.2  (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
;
; AT Host connect:
; DATA - p3.5	(Pin 15 on DIL40, Pin 9 on AT89C2051 PDIP20)
; CLOCK - p3.3	(Pin 13 on DIL40, Pin 7 on AT89C2051 PDIP20, Int 1)
;
; LED-Output connect:
; LEDs are connected with 470R to Vcc
; ScrollLock	- p1.7	(Pin 8 on DIL40, Pin 19 on AT89C2051 PDIP20)
; CapsLock	- p1.6	(Pin 7 on DIL40, Pin 18 on AT89C2051 PDIP20)
; NumLock	- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; Debug ByteTransLoop	- p1.4
; Debug BitTransLoop	- p1.3
; AT TX Communication abort	- p1.2
; AT RX Communication abort	- p1.1
; TX Buffer full		- p1.0
; Int0 active			- p3.7
;
; Build using the macroassembler by Alfred Arnold
; $ asl -L kbdbabel_wy85_ps2_8051.asm -o kbdbabel_wy85_ps2_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_wy85_ps2_8051
; write kbdbabel_wy85_ps2_8051.bin on an empty 27C256 or AT89C2051
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
B23		sfrb	23h
InputBitBuf	equ	24h	; Keyboard input bit buffer
ATBitCount	sfrb	25h	; AT scancode TX counter
RawBuf		equ	26h	; raw scancode
OutputBuf	equ	27h	; AT scancode
TXBuf		equ	28h	; AT scancode TX buffer
WY85InBuf	sfrb	29h	; WY85 bit compare new data buffer, must be bit-adressable
WY85XORBuf	sfrb	2ah	; WY85 bit compare XOR-result buffer, must be bit-adressable
RingBufPtrIn	equ	2eh	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	2fh	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	30h	; AT host-to-dev buffer
ATRXCount	equ	31h
ATRXResendBuf	equ	32h	; for AT resend feature
WY85TRBitCount	equ	33h	; Interrupt handler Bit Count
WY85TRWordCount	equ	34h	; Interrupt handler Word Count
WY85BitCount	equ	35h	; WY85 Bit counter
WY85ByteCount	equ	36h	; WY85 Byte countera
WY85XltPtr	equ	37h	; Scancode-Translation-Table-Pinter / Offset
WY85ByteNum	equ	16	; Number of bytes to be processed

;------------------ bits
ATTXMasqPauseF	bit	B20.0	; TX-AT-Masq-Char-Bit (for Pause-Key)
ATTXMasqPrtScrF	bit	B20.1	; TX-AT-Masq-Char-Bit (for PrtScr-Key)
ATKbdDisableF	bit	B20.2	; Keyboard disable
ATTXBreakF	bit	B20.3	; Release/Break-Code flag
ATTXMasqF	bit	B20.4	; TX-AT-Masq-Char-Bit (send two byte scancode)
ATTXParF	bit	B20.5	; TX-AT-Parity bit
TFModF		bit	B20.6	; AT Timer modifier: alarm clock or clock driver
MiscSleepT0F	bit	B20.7	; sleep timer active flag, timer 0
ATCommAbort	bit	B21.0	; AT communication aborted
ATHostToDevIntF	bit	B21.1	; host-do-device init flag triggered by ex1 / unused.
ATHostToDevF	bit	B21.2	; host-to-device flag for timer
ATTXActiveF	bit	B21.3	; AT TX active
ATCmdReceivedF	bit	B21.4	; full and correct AT byte-received
ATCmdResetF	bit	B21.5	; reset
ATCmdLedF	bit	B21.6	; AT command processing: set LED
ATCmdScancodeF	bit	B21.7	; AT command processing: set scancode
;		bit	B22.0
RXCompleteF	bit	B22.1	; full and correct byte-received
TF1ModF		bit	B22.2	; WY85-Timer Modifier:  Sleep=0, Clock-Generator=1
MiscSleepT1F	bit	B22.3	; sleep timer active flag, timer 1
WY85ClockF	bit	B22.4	; KC85 Clock transmit active

;------------------ arrays
WY85BitBuf1	equ	38h	; size is 20 byte
WY85BitBuf2	equ	4ch	; size is 20 byte
RingBuf		equ	60h
RingBufSizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	70h	; the stack

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

;------------------ WY-85 interval generation with timer 1 in 8 bit mode
; 17mus@24.000MHz -> th0 and tl0=222 or 34 processor cycles	; (256-24000*0.017/12)
interval_t1_17u_24M		equ	222

; 25mus@24.000MHz -> th0 and tl0=206 or 50 processor cycles	; (256-24000*0.025/12)
interval_t1_25u_24M		equ	206

; 30mus@24.000MHz -> th0 and tl0=196 or 60 processor cycles	; (256-24000*0.03/12)
interval_t1_30u_24M		equ	196

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
interval_tl_15u_22118_4k	equ	237

; 0.128ms@22.1184MHz -> th0,tl0=0ffh,14h	; (65536-22118.4*.128/12)
interval_th_128u_22118_4k	equ	255
interval_tl_128u_22118_4k	equ	20

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
	ljmp	HandleInt0
;----------------------------
	org	0bh	; handle TF0
	ljmp	HandleTF0
;----------------------------
	org	13h	; Int 1
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
; int0 handler:
; Get Bits by rotation into InputBitBuf.
;----------------------------------------------------------
HandleInt0:
	push	acc
	push	psw
;	clr	p3.7
; --------------------------- done
Int0Return:
;	setb	p3.7
	pop	psw
	pop	acc
	reti

;----------------------------------------------------------
; timer 1 int handler used for different purposes
; depending on TF1ModF
;
; TF1ModF=0:
; timer is used as 16-bit alarm clock for 20ms intervals.
; Stop the timer after overflow, MiscSleepT1F is cleared
;
; TF1ModF=1:
; timer is used in 8-bit-auto-reload-mode to generate
; 160 WY85 scancode clock cycles with 15-40 microseconds timings.
;
; Registers used: r5,r6
;----------------------------------------------------------
HandleTF1:
	push	acc				; 2,4
	push	psw				; 2,6

; --------------------------- timer is used as 16-bit alarm clock
	jb	TF1ModF,timer1AsClockTimer	; 2,8
	clr	MiscSleepT1F
	clr	tr1
	sjmp	timer1Return

; --------------------------- timer is used as 8-bit clock generator
timer1AsClockTimer:
	; --- sample one bit
	mov	a,r5		; 1,11
	rr	a		; 1
	mov	c,p3.4		; 1
	mov	acc.7,c		; 2
	mov	r5,a		; 1,16

	; --- 8 bits each byte
	djnz	r6,timer1NotSaveWord	; 2,18
	mov	r6,#8			; 1

	; --- store 8 bit to the 20-byte-buffer
;	clr	p1.0
	xch	a,r1		; 1
	mov	a,WY85TRWordCount	; 2
	add	a,#WY85BitBuf1	; 2
	xch	a,r1		; 1
	cpl	a		; 1
	mov	@r1,a		; 1
	inc	WY85TRWordCount	; 2
;	setb	p1.0

timer1NotSaveWord:
	clr	p3.2		; 1,19/29
	nop			; 1
	setb	p3.2		; 1,21/31

	; --- 160-clocks
	djnz	WY85TRBitCount,timer1Return	; 2,10

	; --- 160 clocks finished
	clr	WY85ClockF
	setb	RXCompleteF
	clr	p3.2
	clr	tr1
;	sjmp	timer1Return

timer1Return:
	pop	psw		; 2
	pop	acc		; 2
	reti

;----------------------------------------------------------
; int1 handler:
; trigger on host-do-device transmission signal
;----------------------------------------------------------
HandleInt1:
	setb	ATHostToDevIntF
	reti

;----------------------------------------------------------
; timer 0 int handler used for different purposes
; depending on TFModF and ATHostToDevF
;
; TFModF=0:
; timer is used as 16-bit alarm clock.
; Stop the timer after overflow, cleanup RX buffers
; and clear MiscSleepT0F
; RX timeout at 18.432MHz, set th0,tl0 to
;   0c0h,00h -> 10ms, 0e0h,00h -> 5ms, 0fah,00h -> 1ms
;   0fbh,0cdh -> 0.7ms, 0ffh,039h -> 0.12ms
;
; TFModF=1:
; timer is used in 8-bit-auto-reload-mode to generate
; the AT scancode clock with 2x40 microseconds timings.
; 40mus@18.432MHz -> th0 and tl0=0c3h or 61 processor cycles.
;
; TFModF=1, ATHostToDevF=0:
; device-to-host communication: send datagrams on the AT line.
; Each run in this mode will take 36 processor cycles.
; Extra nops between Data and Clock bit assignment for signal stabilization.
;
; TFModF=1, ATHostToDevF=1:
; host-do-device communication: receive datagrams on the AT line.
;----------------------------------------------------------
HandleTF0:
	jb	TFModF,timerAsClockTimer	; 2,2

; --------------------------- timer is used as 16-bit alarm clock
timerAsAlarmClock:
; -- stop timer 0
	clr	tr0
	clr	MiscSleepT0F
	reti

; --------------------------- AT clock driver, RX or TX
timerAsClockTimer:
	push	acc			; 2,4
	push	psw			; 2,6
	jb	ATHostToDevF,timerHostToDev	; 2,8

; --------------------------- device-to-host communication
timerDevToHost:
; -- switch on bit-number
; -----------------
	jb	ATBitCount.0,timerTXClockRelease	; 2,10
	mov	dptr,#timerDevToHostJT		; 2,12
	mov	a,ATBitCount			; 1,13
	jmp	@a+dptr				; 2,15

timerDevToHostJT:
	sjmp	timerTXStartBit		; 2,17
	sjmp	timerTXDataBit
	sjmp	timerTXDataBit
	sjmp	timerTXDataBit
	sjmp	timerTXDataBit
	sjmp	timerTXDataBit
	sjmp	timerTXDataBit
	sjmp	timerTXDataBit
	sjmp	timerTXDataBit
	sjmp	timerTXParityBit
	sjmp	timerTXStopBit
	sjmp	timerTXStop		; safety

; -----------------
timerTXStartBit:
; -- set start bit (0) and pull down clock line
	jnb	p3.3,timerTXClockBusy	; 2
	nop
	clr	p3.5			; 1	; Data Startbit

	call	nop20

	clr	p3.3			; 1	; Clock
	sjmp	timerTXEnd		; 2

; -----------------
timerTXDataBit:
; -- set data bit 0-7 and pull down clock line
	mov	a,TXBuf			; 1
	rrc	a			; 1	; next data bit to c
	mov	p3.5,c			; 2
	mov	TXBuf,a			; 1

	call	nop20

	clr	p3.3			; 1	; Clock
	sjmp	timerTXEnd

; -----------------
timerTXParityBit:
; -- set parity bit from ATTXParF and pull down clock line
	nop
	mov	c,ATTXParF		; 1	; parity bit
	mov	p3.5,c			; 2

	call	nop20

	clr	p3.3			; 1	; Clock
	sjmp	timerTXEnd		; 2

; -----------------
timerTXStopBit:
; -- set stop bit (1) and pull down clock line
	nop
	nop
	nop
	setb	p3.5			; 1	; Data Stopbit

	call	nop20

	clr	p3.3			; 1	; Clock
	sjmp	timerTXEnd		; 2

; -----------------
timerTXClockRelease:
; -- release clock line

	call	nop20

	mov	a,ATBitCount		; 1
	setb	p3.3			; 1
	cjne	a,#21,timerTXCheckBusy	; 2
	setb	p1.2			; diag: data send
	; end of TX sequence, not time critical
	sjmp	timerTXStop

timerTXCheckBusy:
; -- check if clock is released, but not after the stop bit.
; -- Host may pull down clock to abort communication at any time.
	jb	p3.3,timerTXEnd

timerTXClockBusy:
; -- clock is busy, abort communication
	setb	ATCommAbort		; AT communication aborted flag
	clr	p1.2			; diag: data not send
;	sjmp	timerTXStop

; -----------------
timerTXStop:
; -- stop timer auto-reload
	clr	TFModF
	clr	tr0
	setb	p3.5			; just for safety, clean up data line state
;	sjmp	timerTXEnd

; --------------------------- done
timerTXEnd:				; total 7
; -- done
	inc	ATBitCount		; 1
	pop	psw			; 2
	pop	acc			; 2
	reti				; 2

; --------------------------- host-to-device communication
timerHostToDev:
; -- switch on bit-number
; -----------------
	jb	ATBitCount.0,timerRXClockRelease	; 2,10
	mov	dptr,#timerHostToDevJT		; 2,12
	mov	a,ATBitCount			; 1,13
	jmp	@a+dptr				; 2,15
timerHostToDevJT:
	sjmp	timerRXStartBit		; 2,17
	sjmp	timerRXDataBit
	sjmp	timerRXDataBit
	sjmp	timerRXDataBit
	sjmp	timerRXDataBit
	sjmp	timerRXDataBit
	sjmp	timerRXDataBit
	sjmp	timerRXDataBit
	sjmp	timerRXDataBit
	sjmp	timerRXParityBit
	sjmp	timerRXACKBit
	sjmp	timerRXCleanup
	sjmp	timerRXClockBusy	; safety

; -----------------
timerRXStartBit:
; -- check start bit, must be zero
	jb	p3.5,timerRXClockBusy

	; pull down clock line
	clr	p3.3			; 1	; Clock
	sjmp	timerRXEnd

; -----------------
timerRXDataBit:
; -- read bit 1-8 pull down clock line
; -- new data bit
	mov	a,ATRXBuf
	mov	c,p3.5
	rrc	a
	mov	ATRXBuf,a

; -- pull down clock line
	clr	p3.3			; 1	; Clock
	sjmp	timerRXEnd

; -----------------
timerRXParityBit:
; -- read and check parity bit 9 and pull down clock line
; -- check parity
	mov	a,ATRXBuf
	jb	p,timerRXParityBitPar
	jnb	p3.5,timerRXClockBusy		; parity error
; -- pull down clock line
	clr	p3.3			; 1	; Clock
	sjmp	timerRXEnd

timerRXParityBitPar:
	jb	p3.5,timerRXClockBusy		; parity error
; -- pull down clock line
	clr	p3.3			; 1	; Clock
	sjmp	timerRXEnd

; -----------------
timerRXAckBit:
; -- check bit 10, stop-bit, must be 1.
; -- write ACK-bit and pull down clock line
	jnb	p3.5,timerRXClockBusy

	; ACK-Bit
	clr	p3.5			; 1
	nop
	nop
	nop
	clr	p3.3			; 1	; Clock
	sjmp	timerRXEnd		; 2

; -----------------
timerRXCleanup:
; -- end of RX clock sequence after 12 clock pulses
	clr	TFModF

; -- release the data line
	setb	p3.5

; -- datagram received, stop timer auto-reload
	setb	ATCmdReceivedF			; full message received
	clr	tr0
	sjmp	timerRXEnd

; -----------------
timerRXClockRelease:
; -- release clock line
	nop
	nop
	nop
	mov	a,ATBitCount		; 1
	setb	p3.3			; 1
	cjne	a,#21,timerRXCheckBusy
	setb	p1.1			; diag: host-do-dev ok
	sjmp	timerRXEnd

timerRXCheckBusy:
; -- check if clock is released, but not after the last bit.
; -- Host may pull down clock to abort communication at any time.
	jb	p3.3,timerRXEnd

timerRXClockBusy:
; -- clock is busy, abort communication
	setb	ATCommAbort		; AT communication aborted flag
	clr	p1.1			; diag: host-do-dev abort

	clr	TFModF
	clr	tr0
	setb	p3.5			; just for safety, clean up data line state
;	sjmp	timerRXEnd

; -----------------
timerRXEnd:				; total 7
; -- done
	inc	ATBitCount		; 1
	pop	psw			; 2
	pop	acc			; 2
	reti				; 2

;----------------------------------------------------------
; WY85 to AT translaton table
;----------------------------------------------------------
WY852ATxlt0	DB	 70h,  6bh,  77h,  61h,  3eh,  0dh,  5ah,  05h,   71h,  73h,  4ah,  1ah,  46h,  2dh,  52h,  06h
WY852ATxlt1	DB	 75h,  74h,  7ch,  21h,  45h,  1dh,  5dh,  04h,   72h,  69h,  79h,  22h,  4eh,  24h,  4ch,  0ch
WY852ATxlt2	DB	 6bh,  72h,  6ch,  2ah,  55h,  15h,  29h,  03h,    0h,   0h,  76h,  7eh,  00h,   0h,   0h,  11h
WY852ATxlt3	DB	 4bh,  42h,  3bh,  12h,  33h,  34h,   0h,  0bh,   74h,  5bh,  54h,  66h,  4dh,  70h,  14h,  83h
WY852ATxlt4	DB	 3dh,  36h,  2eh,  25h,  71h,  2ch,  58h,  0ah,   4ah,  49h,  41h,  69h,  0eh,  35h,  1ch,  01h
WY852ATxlt5	DB	 79h,  7bh,  7dh,  31h,  16h,  3ch,  1bh,  09h,   5ah,  7ah,  75h,  32h,  1eh,  43h,  2bh,  78h
WY852ATxlt6	DB	 6ch,  7ah,  7dh,  3ah,  26h,  44h,  23h,  07h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
WY852ATxlt7	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; WY85 to AT translaton table
; Bit-Table for two-byte-AT-Scancodes
; bit 0: E0-Escape
; bit 1: E0,12,E0-Escape (PrtScr)
; bit 2: send E1,14,77,E1,F0,14,F0,77 (Pause)
;----------------------------------------------------------
WY852ATxlte0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  01h,  00h,  00h,  00h,  00h,  00h
WY852ATxlte1	DB	 01h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   01h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
WY852ATxlte2	DB	 01h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  04h,  00h,  00h,  02h,  00h,  00h,  00h
WY852ATxlte3	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   01h,  00h,  00h,  00h,  00h,  01h,  00h,  00h
WY852ATxlte4	DB	 00h,  00h,  00h,  00h,  01h,  00h,  00h,  00h,   00h,  00h,  00h,  01h,  00h,  00h,  00h,  00h
WY852ATxlte5	DB	 00h,  00h,  01h,  00h,  00h,  00h,  00h,  00h,   01h,  01h,  00h,  00h,  00h,  00h,  00h,  00h
WY852ATxlte6	DB	 01h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
WY852ATxlte7	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

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
	clr	p1.0
	ret

;----------------------------------------------------------
; Compare new received data with stored data,
; generate translated scancodes for changed bits.
;----------------------------------------------------------
DeltaKeyState:
	; -- check: bits 149 and 150 must be 1, bits 151-159 must be 0
	clr	c
	mov	a,#18
	add	a,#WY85BitBuf1
	mov	r0,a
	mov	a,@r0
	anl	a,#0e0h
	cjne	a,#060h,DeltaKeyStateEnd
	inc	r0
	mov	a,@r0
	jnz	DeltaKeyStateEnd

	; -- translation table offset
	mov	WY85XltPtr,#0
	; -- 16 byte
	mov	WY85ByteCount,#WY85ByteNum

DeltaKeyStateByteLoop:
	clr	p1.4
	; -- get data from input buffer
	clr	c
	mov	a,#WY85ByteNum
	subb	a,WY85ByteCount
	add	a,#WY85BitBuf1
	mov	r0,a
	mov	a,@r0
	mov	WY85InBuf,a

	; -- get data from state buffer
	clr	c
	mov	a,#WY85ByteNum
	subb	a,WY85ByteCount
	add	a,#WY85BitBuf2
	mov	r0,a
	mov	a,@r0
	mov	WY85XORBuf,a

	; -- store input data to state buffer
	mov	a,WY85InBuf
	mov	@r0,a

	; -- XOR input and state buffer
	xrl	a,WY85XORBuf
	mov	WY85XORBuf,a

	; -- changes?
	jnz	DeltaKeyStateByteChange

	; -- no changes: inc XLT-Pointer by 8
	mov	a,WY85XltPtr
	clr	c
	add	a,#8
	mov	WY85XltPtr,a
	sjmp	DeltaKeyStateByteLoopEnd

	; -- bits changed: do bit analysis
DeltaKeyStateByteChange:
	clr	p1.3
	mov	WY85BitCount,#8

DeltaKeyStateBitLoop:
	clr	p1.3
	jnb	WY85XORBuf.0,DeltaKeyStateBitLoopEnd
;	clr	p1.0

	; -- get make/break bit
	mov	c,WY85InBuf.0
	cpl	c
	mov	ATTXBreakF,c

	; -- send data
	mov	a,WY85XltPtr
	mov	RawBuf,a
	call	TranslateToBuf
DeltaKeyStateBitLoopEnd:

	; -- rotate XORed and input octet
	mov	a,WY85InBuf
	rr	a
	mov	WY85InBuf,a
	mov	a,WY85XORBuf
	rr	a
	mov	WY85XORBuf,a

	; -- inc XLT-Pointer
	inc	WY85XltPtr

;	setb	p1.0
	setb	p1.3

	djnz	WY85BitCount,DeltaKeyStateBitLoop

DeltaKeyStateByteLoopEnd:
	setb	p1.4
	djnz	WY85ByteCount,DeltaKeyStateByteLoop

DeltaKeyStateEnd:
	; -- clear received data flag
	clr	RXCompleteF
	ret

;----------------------------------------------------------
; Get received data and translate it into the ring buffer
;----------------------------------------------------------
TranslateToBuf:
	mov	a,RawBuf

	; check for multi-byte scancodes
	mov	dptr,#WY852ATxlte0
	movc	a,@a+dptr
	mov	c,acc.0
	mov	ATTXMasqF,c
	mov	c,acc.1
	mov	ATTXMasqPrtScrF,c
	mov	c,acc.2
	mov	ATTXMasqPauseF,c

	mov	a,RawBuf

	; get AT scancode
	mov	dptr,#WY852ATxlt0
	movc	a,@a+dptr
	mov	OutputBuf,a

	; clear received data flag
	clr	RXCompleteF

	; keyboard disabled?
	jb	ATKbdDisableF,TranslateToBufEnd

	; check for PrtScr Argh!
	jnb	ATTXMasqPrtScrF,TranslateToBufNoPrtScr
	jnb	ATTXBreakF,TranslateToBufPrtScrMake
	mov	r2,#0E0h
	call	RingBufCheckInsert
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2,#07Ch
	call	RingBufCheckInsert
	mov	r2,#0E0h
	call	RingBufCheckInsert
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2,#012h
	call	RingBufCheckInsert
	sjmp	TranslateToBufEnd
TranslateToBufPrtScrMake:
	mov	r2,#0E0h
	call	RingBufCheckInsert
	mov	r2,#012h
	call	RingBufCheckInsert
	mov	r2,#0E0h
	call	RingBufCheckInsert
	mov	r2,#07ch
	call	RingBufCheckInsert
	sjmp	TranslateToBufEnd
TranslateToBufNoPrtScr:

	; check for Pause, only Make-Code *AAAARRRGH*
	jnb	ATTXMasqPauseF,TranslateToBufNoPause
	jb	ATTXBreakF,TranslateToBufNoPause
	mov	r2,#0E1h
	call	RingBufCheckInsert
	mov	r2,#014h
	call	RingBufCheckInsert
	mov	r2,#077h
	call	RingBufCheckInsert
	mov	r2,#0E1h
	call	RingBufCheckInsert
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2,#014h
	call	RingBufCheckInsert
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2,#077h
	call	RingBufCheckInsert
	sjmp	TranslateToBufEnd
TranslateToBufNoPause:

	; dont send zero scancodes
	mov	a, OutputBuf
	jz	TranslateToBufIgnoreZero

	; check for 0xE0 escape code
	jnb	ATTXMasqF,TranslateToBufNoEsc
	mov	r2,#0E0h
	call	RingBufCheckInsert

TranslateToBufNoEsc:
	; check for 0xF0 release / break code
	jnb	ATTXBreakF,TranslateToBufNoRelease
	mov	r2,#0F0h
	call	RingBufCheckInsert

TranslateToBufNoRelease:
	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert
TranslateToBufIgnoreZero:
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

	; -- get data from buffer
	mov	a,RingBufPtrOut
	add	a,#RingBuf
	mov	r0,a
	mov	a,@r0

	; -- send data
	mov	TXBuf,a		; 8 data bits
	mov	c,p
	cpl	c
	mov	ATTXParF,c	; odd parity bit
	clr	ATHostToDevF	; timer in TX mode
	setb	ATTXActiveF	; diag: TX is active
	call	timer0_init

	; -- wait for completion
BufTXWaitSent:
	jb	TFModF,BufTXWaitSent
	clr	ATTXActiveF		; diag
	jb	ATCommAbort,BufTXEnd	; check on communication abort

;	; diag: send also on serial line
;	mov	a,@r0
;	mov	sbuf,a
;	clr	ti
;BufTXWaitDiagSend:
;	jnb	ti,BufTXWaitDiagSend

	; -- store last transmitted word for resend-feature
	mov	a,@r0
	mov	ATRXResendBuf,a

	; -- increment output pointer
	inc	RingBufPtrOut
	anl	RingBufPtrOut,#RingBufSizeMask

BufTXEnd:
	ret

;----------------------------------------------------------
; check and respond to received AT commands
; used bits: internal: ATCmdLedF, ATCmdScancodeF external ATCmdResetF
;----------------------------------------------------------
ATCmdProc:
	; -- check for new data
	jb	ATCmdReceivedF,ATCPGo
	ljmp	ATCPDone

ATCPGo:
;	; -- diag: send received AT command via serial line
;	mov	sbuf,ATRXBuf
;	clr	ti
;ATCPWait:
;	jnb	ti,ATCPWait

	; -- get received AT command
	mov	a,ATRXBuf
	clr	ATCmdReceivedF

	; -- argument for 0xed command: set keyboard LED
	jnb	ATCmdLedF,ATCPNotEDarg
	clr	ATCmdLedF
	; NumLock
	mov	c,acc.1
	cpl	c
	mov	p1.5,c
	; CapsLock
	mov	c,acc.2
	cpl	c
	mov	p1.6,c
	; ScrollLock
	mov	c,acc.0
	cpl	c
	mov	p1.7,c
	sjmp	ATCPSendAck
ATCPNotEDarg:
	; -- argument for 0xf0 command: set scancode.
	jnb	ATCmdScancodeF,ATCPNotF0Arg
	clr	ATCmdScancodeF
	jnz	ATCPSendAck
	; -- Argument 0x0: send ACK and scancode
	mov	r2,#0FAh
	call	RingBufCheckInsert
	; send 0x02, the default scancode
	mov	r2,#02h
	call	RingBufCheckInsert
	sjmp	ATCPDone
ATCPNotF0Arg:
	; -- command 0xed: set keyboard LED command. set bit for next argument processing and send ACK
	cjne	a,#0edh,ATCPNotED
	setb	ATCmdLedF
	sjmp	ATCPSendAck
ATCPNotED:
	; -- command 0xee: echo command. send 0xee
	cjne	a,#0EEh,ATCPNotEE
	mov	r2,#0EEh
	call	RingBufCheckInsert
	sjmp	ATCPDone
ATCPNotEE:
	; -- command 0xf0: scan code set. set bit for next argument processing and send ACK
	cjne	a,#0f0h,ATCPNotF0
	setb	ATCmdScancodeF
	sjmp	ATCPSendAck
ATCPNotF0:
	cjne	a,#0f1h,ATCPNotF1
	sjmp	ATCPSendAck
ATCPNotF1:
	; -- command 0xf2: keyboard model detection. send ACK,xab,x83
	cjne	a,#0f2h,ATCPNotF2
	mov	r2,#0FAh
	call	RingBufCheckInsert
	mov	r2,#0ABh
	call	RingBufCheckInsert
	; keyboard model MF2: x41h, PS2: x83h
	mov	r2,#083h
	call	RingBufCheckInsert
	sjmp	ATCPDone
ATCPNotF2:
	; -- command 0xf3: typematic repeat rate. send ACK and ignore
	cjne	a,#0f3h,ATCPNotF3
	sjmp	ATCPSendAck
ATCPNotF3:
	; -- command 0xf4: keyboard enable. clear TX buffer, send ACK
	cjne	a,#0f4h,ATCPNotF4
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0
	clr	ATKbdDisableF
	sjmp	ATCPSendAck
ATCPNotF4:
	; -- command 0xf5: keyboard disable. send ACK and set ATKbdDisableF
	cjne	a,#0f5h,ATCPNotF5
	setb	ATKbdDisableF
	sjmp	ATCPSendAck
ATCPNotF5:
	; -- command 0xf6: keyboard enable. clear TX buffer, send ACK
	cjne	a,#0f6h,ATCPNotF6
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0
	clr	ATKbdDisableF
	sjmp	ATCPSendAck
ATCPNotF6:
	; -- command 0xfe: resend last word
	cjne	a,#0feh,ATCPNotFE
	mov	r2,ATRXResendBuf
	call	RingBufCheckInsert
	sjmp	ATCPDone
ATCPNotFE:
	; -- command 0xff: keyboard reset
	cjne	a,#0ffh,ATCPNotFF
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0
	setb	ATCmdResetF
	clr	ATKbdDisableF
	sjmp	ATCPSendAck
ATCPNotFF:
	sjmp	ATCPSendAck

ATCPSendAck:
	mov	r2,#0FAh
	call	RingBufCheckInsert
;	sjmp	ATCPDone

ATCPDone:
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
; init uart with timer 2 as baudrate generator
; 9600 BPS at 3.6864MHz -> ?
; 9600 BPS at 18.432MHz -> RCAP2H,RCAP2L=#0FFh,#0c4h
;----------------------------------------------------------
uart_timer2_init:
	mov	scon, #050h	; uart mode 1 (8 bit), single processor

	orl	t2con, #34h	; Timer 2: internal baudrate generate mode RX/TX
	mov	rcap2h,#0FFh
	mov	rcap2l,#0C4h
	clr	es		; disable serial interrupt

	ret

;----------------------------------------------------------
; init timer 1 for interval timing (fast 8 bit reload)
; interval is 17 microseconds
;----------------------------------------------------------
timer1_init:
	clr	tr1

	; --- diag trigger
	clr	p3.7
	nop
	setb	p3.7

	setb	TF1ModF			; see timer 1 interrupt code
	mov	r6,#8			; 8 bits per word
	mov	WY85TRBitCount,#160	; clock counter
	mov	WY85TRWordCount,#0

	anl	tmod, #0fh	; clear all lower bits
	orl	tmod, #20h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th1, #interval_t1_30u_24M
	mov	tl1, #interval_t1_30u_24M
	setb	et1		; (IE.3) enable timer 1 interrupt

	setb	p3.2

	setb	WY85ClockF
	setb	tr1		; go
	ret

;----------------------------------------------------------
; init timer 1 in 16 bit mode
;----------------------------------------------------------
timer1_20ms_init:
	clr	tr1
	anl	tmod, #0fh	; clear all upper bits
	orl	tmod, #10h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 1, 16bit
	mov	th1, #interval_th_20m_11059_2k
	mov	tl1, #interval_tl_20m_11059_2k
	setb	et1		; (IE.3) enable timer 1 interrupt
	setb	MiscSleepT1F
	clr	TF1ModF		; see timer 1 interrupt code
	setb	tr1		; go
	ret

;----------------------------------------------------------
; init timer 0 for interval timing (fast 8 bit reload)
; need 40-50mus intervals
;----------------------------------------------------------
timer0_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #02h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th0, #interval_t0_45u_11059_2k
	mov	tl0, #interval_t0_45u_11059_2k
	setb	et0		; (IE.1) enable timer 0 interrupt
	setb	TFModF		; see timer 0 interrupt code
	clr	ATCommAbort	; communication abort flag
	mov	ATBitCount,#0
	setb	tr0		; go
	ret

;----------------------------------------------------------
; init timer 0 in 16 bit mode for inter-char delay of 0.13ms
;----------------------------------------------------------
timer0_diag_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
	mov	th0, #interval_th_130u_11059_2k
	mov	tl0, #interval_tl_130u_11059_2k
	setb	et0		; (IE.1) enable timer 0 interrupt
	clr	TFModF		; see timer 0 interrupt code
	setb	MiscSleepT0F
	setb	tr0		; go
	ret

;----------------------------------------------------------
; init timer 0 in 16 bit mode for faked POST delay of of 20ms
;----------------------------------------------------------
timer0_20ms_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all upper bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
	mov	th0, #interval_th_20m_11059_2k
	mov	tl0, #interval_tl_20m_11059_2k
	setb	et0		; (IE.1) enable timer 0 interrupt
	clr	TFModF		; see timer 0 interrupt code
	setb	MiscSleepT0F
	setb	tr0		; go
	ret

;----------------------------------------------------------
; Id
;----------------------------------------------------------
RCSId	DB	"$Id: kbdbabel_wy85_ps2_8051.asm,v 1.2 2007/06/28 10:36:21 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom

	; -- enable interrupts
	setb	ea

	; -- some delay of 500ms to eleminate stray data sent by the PC/XT-Keyboard on power-up
	mov	r0,#25
InitResetDelayLoop:
	call	timer0_20ms_init
InitResetDelay:
	jb	MiscSleepT0F,InitResetDelay
	djnz	r0,InitResetDelayLoop

	; -- init UART and timer0/1
;	acall	uart_timer2_init
	acall	timer1_init
	acall	timer0_diag_init

	; -- enable interrupt int0
	setb	ex0		; external interupt 0 enable
	setb	it0		; falling edge trigger for int 0

	; -- disable interrupt int1
	clr	ex1		; external interupt 1 enable

	; -- clear all flags
	mov	B20,#0
	mov	B21,#0
	mov	B22,#0
	mov	B23,#0
	setb	ATKbdDisableF

	; -- init the ring buffer
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0

	; -- cold start flag
	setb	ATCmdResetF

; ----------------
Loop:
	; -- check WY85-Pause
	jb	TF1ModF, LoopWY85Clock
	jb	MiscSleepT1F,LoopWY85Done
	acall	timer1_init
	sjmp	LoopWY85Done

	; -- check if 160 WY85-Clocks are sent, start delay timer when finished
LoopWY85Clock:
	jb	WY85ClockF,LoopWY85Done
	call	timer1_20ms_init

LoopWY85Done:
	; -- check Keyboard receive status
	jb	RXCompleteF,LoopProcessData

	; -- check on new AT data received
	jb	ATCmdReceivedF,LoopProcessATcmd

	; -- check if AT communication active.
	jb	TFModF,Loop

	; -- check AT line status, clock line must not be busy
	jnb	p3.3,Loop

	; -- check data line for RX or TX status
	jb	p3.5,LoopATTX
	sjmp	LoopATRX

;----------------------------------------------------------
; helpers for the main loop
;----------------------------------------------------------
; --- Keyboard data received, process the received scancode into output ring buffer
LoopProcessData:
	call	DeltaKeyState
	sjmp	Loop

; -----------------
LoopProcessATcmd:
; -- AT command processing
	call	ATCmdProc
	sjmp	loop

; ----------------
LoopATRX:
; -- Host-do-Device communication
	; -- diag: host-do-dev ok
	setb	p1.1

	; -- receive data on the AT line
	mov	ATRXCount,#0
	mov	ATRXBuf,#0
;	clr     ATHostToDevIntF
	setb	ATHostToDevF
	call	timer0_init

	; wait for completion
LoopTXWaitSent:
	jb	TFModF,LoopTXWaitSent
LoopCheckATEnd:
	ljmp	Loop

; ----------------
LoopATTX:
; -- Device-to-Host communication
	; -- send data on the AT line
	; some delay 0.15ms
	call	timer0_diag_init
LoopTXWaitDelay:
	jb	MiscSleepT0F,LoopTXWaitDelay

LoopSendData:
	; send data
	call	BufTX

	; -- keyboard reset/cold start: send AAh after some delay
	jnb	ATCmdResetF,LoopTXWaitDelayEnd
	clr	ATCmdResetF
;	clr	ATKbdDisableF
	; -- optional delay after faked cold start
	; yes, some machines will not boot without this, e.g. IBM PS/ValuePoint 433DX/D
	call	timer0_20ms_init
LoopTXResetDelay:
	jb	MiscSleepT0F,LoopTXResetDelay

	; -- init the WY85-state buffer
	call	DeltaKeyState
	clr	ATKbdDisableF
	; -- send "self test passed"
	mov	r2,#0AAh
	call	RingBufCheckInsert
LoopTXWaitDelayEnd:
	ljmp	Loop

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	"   Copyright 2007 by Alexander Kurz"
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
