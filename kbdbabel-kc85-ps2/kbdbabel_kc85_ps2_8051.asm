; ---------------------------------------------------------------------
; Robotron KC-85 to AT/PS2 keyboard transcoder for 8051 type processors
;
; $KbdBabel: kbdbabel_kc85_ps2_8051.asm,v 1.2 2007/06/04 09:31:07 akurz Exp $
;
; Clock/Crystal: development version with 24MHz.
;
; KC-85 Keyboard connect:
; Data - p3.2  (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
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
; KC85 timer, bit valid	- p1.4
; KC85 timer, bit	- p1.3
; AT TX Communication abort	- p1.2
; AT RX Communication abort	- p1.1
; KC85 timer timeout		- p1.0
; Int0 active			- p3.7
;
; Build using the macroassembler by Alfred Arnold
; $ asl kbdbabel_kc85_ps2_8051.asm -o kbdbabel_kc85_ps2_8051.p
; $ p2bin -l \$ff kbdbabel_kc85_ps2_8051
; write kbdbabel_kc5_ps2_8051.bin on an empty 27C256 or AT89C2051
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
;		bit	20h.0	;
;		bit	20h.1	;
ATKbdDisableF	bit	20h.2	; Keyboard disable
ATTXBreakF	bit	20h.3	; Release/Break-Code flag
ATTXMasqF	bit	20h.4	; TX-AT-Masq-Char-Bit (send two byte scancode)
ATTXParF	bit	20h.5	; TX-AT-Parity bit
TFModF		bit	20h.6	; AT Timer modifier: alarm clock or clock driver
MiscSleepT0F	bit	20h.7	; sleep timer active flag, timer 0
ATCommAbort	bit	21h.0	; AT communication aborted
ATHostToDevIntF	bit	21h.1	; host-do-device init flag triggered by ex1 / unused.
ATHostToDevF	bit	21h.2	; host-to-device flag for timer
ATTXActiveF	bit	21h.3	; AT TX active
ATCmdReceivedF	bit	21h.4	; full and correct AT byte-received
ATCmdResetF	bit	21h.5	; reset
ATCmdLedF	bit	21h.6	; AT command processing: set LED
ATCmdScancodeF	bit	21h.7	; AT command processing: set scancode
;			bit	22h.0
RXCompleteF		bit	22h.1	; full and correct byte-received
KC85DataBit		bit	22h.2	; time dependant data bit, set by TF1-Handler, to be read by INT0 handler
KC85DataBitValid	bit	22h.3	; time dependant data valid bit, set by TF1-Handler
KC85WordTimeoutF	bit	22h.4	; Timeout for 7-bit words.
KC85ClockTimeoutF	bit	22h.5	; Maximum interval time expired.
KC85ShiftF		bit	22h.6	; An extra bit for Shift
;------------------ octets
InputBitBuf	equ	24h	; Keyboard input bit buffer
ATBitCount	equ	28h	; AT scancode TX counter
RawBuf		equ	30h	; raw scancode
OutputBuf	equ	31h	; AT scancode
TXBuf		equ	32h	; AT scancode TX buffer
RingBufPtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	35h	; AT host-to-dev buffer
ATRXCount	equ	36h
ATRXResendBuf	equ	37h	; for AT resend feature
KC85ClockCount	equ	38h	; KC-85 Clock counter
KC85BitCount	equ	39h	; KC-85 Bit counter
KC85CodeStore	equ	3ah	; Scancode-buffer
;------------------ arrays
RingBuf		equ	40h
RingBufSizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	50h	; the stack

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
	clr	p3.7

	; --- check for the first pulse after inter-word timeout
	jnb	KC85WordTimeoutF,Int0WordInProgress
	mov	InputBitBuf,#0
	mov	KC85BitCount,#0
	call	timer1_init
	sjmp	Int0Return

Int0WordInProgress:
	; --- ignore invalid intervals, FIXME
	jnb	KC85DataBitValid,Int0Return
	mov	a,InputBitBuf
	rr	a
	mov	c,KC85DataBit
	mov	acc.6,c
	mov	InputBitBuf,a

	mov	KC85ClockCount,#0

	; --- check bit number
	inc	KC85BitCount
	mov	a,KC85BitCount
	cjne	a,#7,Int0Return

	; --- full word received
	mov	a,InputBitBuf
	mov	RawBuf,a
	mov	KC85CodeStore,a
	setb	RXCompleteF
;	sjmp	Int0Return

; --------------------------- done
Int0Return:
	setb	p3.7
	pop	psw
	pop	acc
	reti

;----------------------------------------------------------
; timer 1 int handler:
; KC-85 Keyboard interval timing.
; Using 125 microseconds as interval results in this state table:
; < 4.5ms	< 35 cycles	invalid
; 4.5-6.7ms	35-53 cycles	valid 0
; 6.7-8.9ms	54-71 cycles	valid 1
; 8.9-13.1	72-1 04 cycles	invalid
; 13.1-18.1ms	104-145 cycles	inter-character interval
; > 18.1ms	> 145 cycles	key-release timeout
;
; all interval values corrected by -10%. FIXME
;----------------------------------------------------------
HandleTF1:
	push	acc
	push	psw

	mov	a,KC85ClockCount
	clr	c
	inc	KC85ClockCount
	; --- check count < 32
	subb	a,#32
	jc	timer1StateInvalid
	; --- check count < 48
	subb	a,#16
	jc	timer1StateValid0
	; --- check count < 64
	subb	a,#16
	jc	timer1StateValid1
	; --- check count < 93, state invalid
	subb	a,#29
	jc	timer1StateInvalid
	; --- check count < 129
	subb	a,#36
	jc	timer1InterChar
; -----------------
; --- Repeat-Timeout: Key released: stop timer
	clr	tr1
	setb	KC85ClockTimeoutF
	sjmp	timer1Return
; -----------------
; --- inter-character timeout
timer1InterChar:
	setb	KC85WordTimeoutF
	setb	p1.0
	clr	KC85DataBitValid
	setb	p1.4
	sjmp	timer1Return

; -----------------
; --- invalid timing:
timer1StateInvalid:
	clr	KC85DataBitValid
	setb	p1.4
	sjmp	timer1Return

; -----------------
; --- valid timing with 0 bit value
timer1StateValid0:
	clr	KC85DataBit
	setb	KC85DataBitValid
	clr	p1.3
	clr	p1.4
	sjmp	timer1Return

; -----------------
; --- valid timing with 1 bit value
timer1StateValid1:
	setb	KC85DataBit
	setb	KC85DataBitValid
	clr	p1.4
	setb	p1.3
	sjmp	timer1Return

; -----------------
; --- done
timer1Return:
	pop	psw
	pop	acc
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
; KC85 to AT translaton table
; using significant bits 1-6 only: anl a,#7e; rr a;
;----------------------------------------------------------
KC852ATxlt0	DB	 1dh,  1ch,  1eh,  6bh,  6ch,  55h,  06h,  1ah
KC852ATxlt1	DB	 24h,  1bh,  26h,  0eh,  66h,  4eh,  04h,  22h
KC852ATxlt2	DB	 2ch,  2bh,  2eh,  4dh,  71h,  45h,  03h,  2ah
KC852ATxlt3	DB	 3ch,  33h,  3dh,  44h,  70h,  46h,  54h,  31h
KC852ATxlt4	DB	 43h,  3bh,  3eh,  29h,  42h,  41h,  5bh,  3ah
KC852ATxlt5	DB	 35h,  34h,  36h,   0h,  4bh,  49h,  0bh,  32h
KC852ATxlt6	DB	 2dh,  23h,  25h,  52h,  4ch,  4ah,  0ch,  21h
KC852ATxlt7	DB	 15h,  58h,  16h,  72h,  75h,  74h,  05h,  5ah

;----------------------------------------------------------
; Mac to AT translaton table
; Bit-Table for two-byte-AT-Scancodes
;----------------------------------------------------------
KC852ATxlte0	DB	 00h,  00h,  00h,  01h,  01h,  00h,  00h,  00h
KC852ATxlte1	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
KC852ATxlte2	DB	 00h,  00h,  00h,  00h,  01h,  00h,  00h,  00h
KC852ATxlte3	DB	 00h,  00h,  00h,  00h,  01h,  00h,  00h,  00h
KC852ATxlte4	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
KC852ATxlte5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
KC852ATxlte6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
KC852ATxlte7	DB	 00h,  00h,  00h,  01h,  01h,  01h,  00h,  00h

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
;	clr	p1.0
	ret

;----------------------------------------------------------
; Get received data and translate it into the ring buffer
; translate from KC85 to AT scancode
;----------------------------------------------------------
TranslateToBuf:
	; --- check break-scancode
	jnb	KC85ClockTimeoutF,TranslateToBufMake
	clr	KC85ClockTimeoutF
	mov	a,KC85CodeStore
	setb	ATTXBreakF
	sjmp	TranslateToBufMakeAndBreak

TranslateToBufMake:
	; --- regular scancode
	mov	a,RawBuf
	; clear received data flag
	clr	RXCompleteF
	clr	ATTXBreakF

TranslateToBufMakeAndBreak:
	; save shift bit 0
	mov	c,acc.0
	cpl	c
	mov	KC85ShiftF,c

	; ignore shift bit 0
	anl	a,#0feh

	; ignore obsolete bit 7
	anl	a,#7fh
	rr	a

	; check for 2-byte AT-scancodes
	mov	r4,a
	mov	dptr,#KC852ATxlte0
	movc	a,@a+dptr
	mov	c,acc.0
	mov	ATTXMasqF,c
	mov	a,r4

	; get AT scancode
	mov	dptr,#KC852ATxlt0
	movc	a,@a+dptr
	mov	OutputBuf,a
	sjmp	TranslateToBufGo

TranslateToBufGo:
	; send shift make code
	jnb	KC85ShiftF,TranslateToBufMakeNoShift
	mov	r2,#012h
	call	RingBufCheckInsert

TranslateToBufMakeNoShift:
	; keyboard disabled?
	jb	ATKbdDisableF,TranslateToBufEnd

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
	mov	a,OutputBuf
	jz	TranslateToBufIgnoreZero
	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert

	; send shift break code
	jnb	KC85ShiftF,TranslateToBufBreakNoShift
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2,#012h
	call	RingBufCheckInsert
TranslateToBufBreakNoShift:
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
;	clr	ex0		; may diable input interrupt here, better is, better dont.
;	clr	ex1
	call	timer0_init

	; -- wait for completion
BufTXWaitSent:
	jb	TFModF,BufTXWaitSent
;	setb	ex1		; enable external interupt 1
;	setb	ex0		; enable external interupt 0
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
; helper, waste 10 cpu cycles
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
; interval is 125 microseconds
;----------------------------------------------------------
timer1_init:
	clr	tr1
	anl	tmod, #0fh	; clear all lower bits
	orl	tmod, #20h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th1, #interval_t1_125u_24M
	mov	tl1, #interval_t1_125u_24M
	setb	et1		; (IE.3) enable timer 1 interrupt
	clr	KC85ClockTimeoutF
	clr	KC85WordTimeoutF
	clr	p1.0
	clr	KC85DataBitValid
	setb	p1.4
	mov	KC85ClockCount,#0
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
RCSId	DB	"$Id: kbdbabel_kc85_ps2_8051.asm,v 1.1 2007/06/04 09:39:54 akurz Exp $"

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
	acall	timer0_diag_init

	; -- enable interrupts int0
	setb	ex0		; external interupt 0 enable
	setb	it0		; falling edge trigger for int 0

	; -- clear all flags
	mov	20h,#0
	mov	21h,#0
	mov	22h,#0
	mov	23h,#0

	; -- init the ring buffer
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0

	; -- cold start flag
	setb	ATCmdResetF

; ----------------
Loop:
	; -- check Keyboard receive status
	jb	RXCompleteF,LoopProcessData

	; -- check Keyboard timeout, for Break-Code generation
	jb	KC85ClockTimeoutF,LoopProcessData

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
	call	TranslateToBuf
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
	; -- optional delay after faked cold start
	; yes, some machines will not boot without this, e.g. IBM PS/ValuePoint 433DX/D
	call	timer0_20ms_init
LoopTXResetDelay:
	jb	MiscSleepT0F,LoopTXResetDelay
	# -- send "self test passed"
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
