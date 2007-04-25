; ---------------------------------------------------------------------
; DEC LK to AT/PS2 keyboard transcoder for 8051 type processors.
;
; $KbdBabel: kbdbabel_lk_ps2_8051.asm,v 1.6 2007/04/25 08:33:23 akurz Exp $
;
; Clock/Crystal: 11.0592MHz.
; alternatively 18.432MHz and 14.7456 may be used.
; 3.6864MHz or 7.3728 will be too slow to drive the AT/PS2 timer.
;
; DEC LK Keyboard connect:
; Using a max232 line driver connected to serial port lines
; RxD - p3.0 (Pin 10 on DIL40, Pin 2 on AT89C2051 PDIP20)
; TxD - p3.1 (Pin 11 on DIL40, Pin 3 on AT89C2051 PDIP20)
;
; AT Host connect:
; DATA - p3.5	(Pin 15 on DIL40, Pin 9 on AT89C2051 PDIP20)
; CLOCK - p3.3	(Pin 13 on DIL40, Pin 7 on AT89C2051 PDIP20, Int 1)
;
; LED-Output connect:
; LEDs are connected with 220R to Vcc
; ScrollLock	- p1.7	(Pin 8 on DIL40, Pin 19 on AT89C2051 PDIP20)
; CapsLock	- p1.6	(Pin 7 on DIL40, Pin 18 on AT89C2051 PDIP20)
; NumLock	- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; ?		- p1.4
; ?		- p1.3
; AT TX Communication abort	- p1.2
; AT RX Communication abort	- p1.1
; TX buffer full		- p1.0
;
; Build:
; $ asl kbdbabel_lk_ps2_8051.asm -o kbdbabel_lk_ps2_8051.p
; $ p2bin -l \$ff kbdbabel_lk_ps2_8051
; write kbdbabel_lk_ps2_8051.bin on an empty 27C256 or AT89C2051
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
MiscRXCompleteF	bit	20h.1	; full and correct byte-received
ATTXBreakF	bit	20h.3	; Release/Break-Code flag
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
ATCmdLedF	bit	21h.6	; AT command processing: set LED
ATCmdScancodeF	bit	21h.7	; AT command processing: set scancode
ATKbdDisableF	bit	22h.0	; Keyboard disable
LKLEDSetF	bit	22h.1	; SetLed command to for keyboard: argument
LKLEDCtrl1F	bit	22h.2	; SetLed command to for keyboard: command 1
LKLEDCtrl2F	bit	22h.3	; SetLed command to for keyboard: command 1
LKLEDCtrl3F	bit	22h.4	; SetLed command to for keyboard: command 1
LKSKeyF		bit	22h.5	; shift or control key

LKModSL		bit	23h.0	; LK modifier state storage: left shift
LKModSR		bit	23h.1	; LK modifier state storage: right shift
LKModAL		bit	23h.2	; LK modifier state storage: left alt
LKModAR		bit	23h.3	; LK modifier state storage: right alt
LKModC		bit	23h.4	; LK modifier state storage: ctrl

;------------------ octets
LKModAll	equ	23h	; collective access to stored LK modifier flags
LKModBuf	equ	24h	; translated received modifier codes
LKLEDBuf	equ	25h	; must be bit-adressable
KbBitBufL	equ	26h
KbBitBufH	equ	27h
KbClockMin	equ	28h
KbClockMax	equ	29h
ATBitCount	equ	2ah	; AT scancode TX counter
RawBuf		equ	30h	; raw input scancode
OutputBuf	equ	31h	; AT scancode
TXBuf		equ	32h	; AT scancode TX buffer
RingBufPtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	35h	; AT host-to-dev buffer
ATRXCount	equ	36h
ATRXResendBuf	equ	37h	; for AT resend feature
LKMetronomBuf	equ	38h	; LK metronom feature / typematic buffer
ATBrkLedSBuf	equ	39h	; "send the break code later" buffer for Caps/Scroll/NumLock keys
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
uart_t1_4800_11059_2k		equ	244

; 4800BPS @18.432MHz -> tl1 and th1 = #236 with SMOD=1	; (256-2*18432/384/4.8)
uart_t1_4800_18432k		equ	236

; 9600BPS @18.432MHz -> tl1 and th1 = #246 with SMOD=1	; (256-2*18432/384/9.6)
uart_t1_9600_18432k		equ	246

;------------------ bitrates generated with timer 2
; 9600 BPS at 18.432MHz -> RCAP2H,RCAP2L=#0FFh,#0c4h	; (256-18432/32/9.6)
uart_t2h_9600_18432k		equ	255
uart_t2l_9600_18432k		equ	196

;------------------ AT scancode timing intervals generated with timer 0 in 8 bit mode
; 85mus@11.0592MHz -> th0 and tl0=178 or 78 processor cycles	; (256-11059.2*0.085/12)
interval_t0_85u_11059_2k	equ	178

; 80mus@11.0592MHz -> th0 and tl0=183 or 73 processor cycles	; (256-11059.2*0.08/12)
interval_t0_80u_11059_2k	equ	183

; 75mus@11.0592MHz -> th0 and tl0=187 or 69 processor cycles	; (256-11059.2*0.075/12)
interval_t0_75u_11059_2k	equ	187

; 80mus@12.000MHz -> th0 and tl0=176 or 80 processor cycles	; (256-12000*0.08/12)
interval_t0_45u_12M		equ	176

; 80mus@18.432MHz -> th0 and tl0=134 or 122 processor cycles	; (256-18432*0.08/12)
interval_t0_40u_18432k		equ	134

; 80mus@24.000MHz -> th0 and tl0=96 or 160 processor cycles	; (256-24000*0.08/12)
interval_t0_40u_24M		equ	96

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

;----------------------------------------------------------
; start
;----------------------------------------------------------
	org	0	; cold start
	ljmp	Start
;----------------------------------------------------------
; interrupt handlers
;----------------------------------------------------------
;----------------------------
;	org	03h	; external interrupt 0
;	ljmp	HandleInt0
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
; int1 handler:
; trigger on host-do-device transmission signal
;----------------------------------------------------------
;HandleInt1:
;	setb	ATHostToDevIntF
;	reti

;----------------------------------------------------------
; timer 0 int handler used for different purposes
; depending on ATTFModF and ATHostToDevF
;
; ATTFModF=0:
; timer is used as 16-bit alarm clock.
; Stop the timer after overflow, cleanup RX buffers
; and clear MiscSleepF
;
; ATTFModF=1:
; timer is used in 8-bit-auto-reload-mode to generate
; the AT scancode clock timings.
;
; ATTFModF=1, ATHostToDevF=0:
; device-to-host communication: send datagrams on the AT line.
; Each run in this mode will take 36 processor cycles.
; Extra nops between Data and Clock bit assignment for signal stabilization.
;
; ATTFModF=1, ATHostToDevF=1:
; host-do-device communication: receive datagrams on the AT line.
;----------------------------------------------------------
HandleTF0:
	jb	ATTFModF,timerAsClockTimer	; 2,2

; --------------------------- timer is used as 16-bit alarm clock
timerAsAlarmClock:
; -- stop timer 0
	clr	tr0
	clr	MiscSleepF
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
	mov	dptr,#timerDevToHostJT		; 2,10
	mov	a,ATBitCount			; 1,11
	rl	a				; 1,12
	jmp	@a+dptr				; 2,14

timerDevToHostJT:
	sjmp	timerTXStartBit		; 2,16
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
	call	ATTX_delay_clk
	clr	p3.3			; 1	; Clock
	sjmp	timerTXClockRelease	; 2

; -----------------
timerTXDataBit:
; -- set data bit 0-7 and pull down clock line
	mov	a,TXBuf			; 1
	rrc	a			; 1	; next data bit to c
	mov	p3.5,c			; 2
	mov	TXBuf,a			; 1
	call	ATTX_delay_clk
	clr	p3.3			; 1	; Clock
	sjmp	timerTXClockRelease	; 2

; -----------------
timerTXParityBit:
; -- set parity bit from ATTXParF and pull down clock line
	nop
	mov	c,ATTXParF		; 1	; parity bit
	mov	p3.5,c			; 2
	call	ATTX_delay_clk
	clr	p3.3			; 1	; Clock
	sjmp	timerTXClockRelease	; 2

; -----------------
timerTXStopBit:
; -- set stop bit (1) and pull down clock line
	nop
	nop
	nop
	setb	p3.5			; 1	; Data Stopbit
	call	ATTX_delay_clk
	clr	p3.3			; 1	; Clock
	sjmp	timerTXClockRelease	; 2

; -----------------
timerTXClockRelease:
; -- release clock line
	call	ATTX_delay_release
	mov	a,ATBitCount		; 1
	cjne	a,#10,timerTXCheckBusy	; 2
	setb	p3.3			; 1
	setb	p1.2			; diag: data send
	; end of TX sequence, not time critical
	sjmp	timerTXStop

timerTXCheckBusy:
; -- check if clock is released, but not after the stop bit.
; -- Host may pull down clock to abort communication at any time.
	setb	p3.3			; 1
	jb	p3.3,timerTXEnd

timerTXClockBusy:
; -- clock is busy, abort communication
	setb	ATCommAbort		; AT communication aborted flag
	clr	p1.2			; diag: data not send
;	sjmp	timerTXStop

; -----------------
timerTXStop:
; -- stop timer auto-reload
	clr	ATTFModF
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
	mov	dptr,#timerHostToDevJT		; 2,10
	mov	a,ATBitCount			; 1,11
	rl	a				; 1,12
	jmp	@a+dptr				; 2,14
timerHostToDevJT:
	sjmp	timerRXStartBit		; 2,16
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
	sjmp	timerRXClockRelease

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
	sjmp	timerRXClockRelease

; -----------------
timerRXParityBit:
; -- read and check parity bit 9 and pull down clock line
; -- check parity
	mov	a,ATRXBuf
	jb	p,timerRXParityBitPar
	jnb	p3.5,timerRXClockBusy		; parity error
; -- pull down clock line
	clr	p3.3			; 1	; Clock
	sjmp	timerRXClockRelease

timerRXParityBitPar:
	jb	p3.5,timerRXClockBusy		; parity error
; -- pull down clock line
	clr	p3.3			; 1	; Clock
	sjmp	timerRXClockRelease

; -----------------
timerRXAckBit:
; -- check bit 10, stop-bit, must be 1.
; -- write ACK-bit and pull down clock line
	jnb	p3.5,timerRXClockBusy

	; ACK-Bit
	clr	p3.5			; 1
	call	ATTX_delay_clk
	clr	p3.3			; 1	; Clock
	sjmp	timerRXClockRelease	; 2

; -----------------
timerRXCleanup:
; -- end of RX clock sequence after 12 clock pulses
	clr	ATTFModF

; -- release the data line
	setb	p3.5

; -- datagram received, stop timer auto-reload
	setb	ATCmdReceivedF			; full message received
	clr	tr0
	sjmp	timerRXEnd

; -----------------
timerRXClockRelease:
; -- release clock line
	call	ATTX_delay_release
	mov	a,ATBitCount		; 1
	cjne	a,#10,timerRXCheckBusy
	setb	p3.3			; 1
	setb	p1.1			; diag: host-do-dev ok
	sjmp	timerRXEnd

timerRXCheckBusy:
; -- check if clock is released, but not after the last bit.
; -- Host may pull down clock to abort communication at any time.
	setb	p3.3			; 1
	jb	p3.3,timerRXEnd

timerRXClockBusy:
; -- clock is busy, abort communication
	setb	ATCommAbort		; AT communication aborted flag
	clr	p1.1			; diag: host-do-dev abort

	clr	ATTFModF
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
; DEC LK to AT translaton table
; Position: DEC-LK scancode, Value: AT-PS2 scancode
; note: Prog1 0a1h=Esc, Prog2 0a2h=NumLock, Prog3 0a3h=ScrollLock
;----------------------------------------------------------

lk2atxlt0	DB	000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
lk2atxlt1	DB	000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
lk2atxlt2	DB	000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
lk2atxlt3	DB	000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
lk2atxlt4	DB	000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
lk2atxlt5	DB	000h, 000h, 000h, 000h, 000h, 000h, 005h, 006h,  004h, 00ch, 003h, 000h, 000h, 000h, 000h, 000h
lk2atxlt6	DB	000h, 000h, 000h, 000h, 00bh, 002h, 00ah, 001h,  009h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
lk2atxlt7	DB	000h, 078h, 007h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
lk2atxlt8	DB	000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 06ch, 070h, 071h, 069h, 07dh, 07ah
lk2atxlt9	DB	000h, 000h, 070h, 000h, 071h, 079h, 069h, 072h,  07ah, 06bh, 073h, 074h, 07ch, 06ch, 075h, 07dh
lk2atxlta	DB	07bh, 076h, 077h, 07eh, 04ah, 000h, 000h, 06bh,  074h, 072h, 075h, 059h, 011h, 000h, 012h, 014h
lk2atxltb	DB	058h, 000h, 011h, 000h, 000h, 000h, 000h, 000h,  000h, 000h, 000h, 000h, 066h, 05ah, 00dh, 00eh
lk2atxltc	DB	016h, 015h, 01ch, 01ah, 000h, 01eh, 01dh, 01bh,  022h, 061h, 000h, 026h, 024h, 023h, 021h, 000h
lk2atxltd	DB	025h, 02dh, 02bh, 02ah, 029h, 000h, 02eh, 02ch,  034h, 032h, 000h, 036h, 035h, 033h, 031h, 000h
lk2atxlte	DB	03dh, 03ch, 03bh, 03ah, 000h, 03eh, 043h, 042h,  041h, 000h, 046h, 044h, 04bh, 049h, 000h, 045h
lk2atxltf	DB	04dh, 000h, 04ch, 04ah, 000h, 055h, 05bh, 05dh,  000h, 04eh, 054h, 076h, 000h, 000h, 000h, 000h

;----------------------------------------------------------
; DEC LK to AT translaton table
; special features
; Bit-translation Table for LK shift and control keys
; state buffers are:
;   bit 0: LKModSL	; shift left
;   bit 1: LKModSR	; shift right
;   bit 2: LKModAL	; alt left
;   bit 3: LKModAR	; alt right
;   bit 4: LKModC	; ctrl left
;   bit 6: keyboard LED modifying code, Caps/Num/Scroll Lock
;   bit 7: all modifiers released
;----------------------------------------------------------
lk2atxlts0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts1	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts2	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts3	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts4	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts7	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts8	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlts9	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltsa	DB	 00h,  00h,  40h,  40h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  02h,  04h,  00h,  01h,  10h
lk2atxltsb	DB	 40h,  00h,  08h, 0f0h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltsc	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltsd	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltse	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltsf	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

;----------------------------------------------------------
; DEC LK to AT translaton table
; Bit-Table for two-byte-AT-Scancodes
; Note: even in the small 89c2051 there is enough program memory space for
;	this space-consuming lookup table. Does not look nice,
;	but it is easy to read and will execute fast.
;----------------------------------------------------------
lk2atxlte0	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte1	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte2	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte3	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte4	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte5	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte6	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte7	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlte8	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  01h,  01h,  01h,  01h,  01h,  01h
lk2atxlte9	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltea	DB	 00h,  00h,  00h,  00h,  01h,  00h,  00h,  01h,   01h,  01h,  01h,  00h,  01h,  00h,  00h,  00h
lk2atxlteb	DB	 00h,  00h,  01h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltec	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxlted	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltee	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
lk2atxltef	DB	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h,   00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h

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
; Get received data and translate it into the ring buffer
;----------------------------------------------------------
TranslateToBufLK:
	; translate from DEC LK to AT scancode
	mov	a,RawBuf

	; --  translate LK to AT scancode
	; check for 2-byte PS2-scancodes
	mov	r4,a
	mov	dptr,#LK2ATxlte0
	movc	a,@a+dptr
	mov	c,acc.0
	mov	ATTXMasqF,c
	mov	a,r4

	; --------- check for LK shift and control keys
	; converting LK shift/ctrl/alt state to PS2 requires a bit more code.
	; LK scancodes do not feature Make- and Break-Codes like PS2
	; Instead a scancode is send for each key-press and key-release.
	; On release of all shift/alt/ctrl-keys 0b3h is sent marked in lk2atxlts with bit 7 set.
	;
	; get modifier code
	mov	r4,a
	mov	dptr,#LK2ATxlts0
	movc	a,@a+dptr
	mov	LKModBuf,a

	anl	a, #0bfh	; ignore bit 6 from lk2atxlts
	jnz	TranslateToBufLKMod
	jmp	TranslateToBufLKModEnd
TranslateToBufLKMod:
	; check for all modifiers cleared
	jb	acc.7, TranslateToBufLKClrMod

	; ------ Make or Multi-Modifier
	; either a new modifier is pressed or
	; am modifier is released while an other modifier is still held down
	;
	; -- send E0 Escape codes for multi-mod release, e.g. Alt-R
	mov	a,LKModBuf
	jnb	acc.3, TranslateToBufLKNoMultiAR
	mov	r2,#0E0h
	call	RingBufCheckInsert

TranslateToBufLKNoMultiAR:
	; --- send break on key release
	anl	a,LKModAll
	jz	TranslateToBufLKNoMultiModRelease
	mov	r2,#0F0h
	call	RingBufCheckInsert

TranslateToBufLKNoMultiModRelease:
	mov	a,LKModBuf
	jb	acc.0, TranslateToBufLKToggleSL
	jb	acc.1, TranslateToBufLKToggleSR
	jb	acc.2, TranslateToBufLKToggleAL
	jb	acc.3, TranslateToBufLKToggleAR
	jb	acc.4, TranslateToBufLKToggleC
	sjmp	TranslateToBufLKToggleEnd

	; --- toggle modifiers
TranslateToBufLKToggleSL:
	mov	r2,#012h
	call	RingBufCheckInsert
	cpl	LKModSL
	sjmp	TranslateToBufLKToggleEnd
TranslateToBufLKToggleSR:
	mov	r2,#059h
	call	RingBufCheckInsert
	cpl	LKModSR
	sjmp	TranslateToBufLKToggleEnd
TranslateToBufLKToggleAL:
	mov	r2,#011h
	call	RingBufCheckInsert
	cpl	LKModAL
	sjmp	TranslateToBufLKToggleEnd
TranslateToBufLKToggleAR:
	mov	r2,#011h
	call	RingBufCheckInsert
	cpl	LKModAR
	sjmp	TranslateToBufLKToggleEnd
TranslateToBufLKToggleC:
	mov	r2,#014h
	call	RingBufCheckInsert
	cpl	LKModC

TranslateToBufLKToggleEnd:
	ljmp	TranslateToBufLKEnd


TranslateToBufLKClrMod:
	; ------ Clear all Modifiers
	; the last modifier key is released here.
	;
	; -- check on what cannot happen ...
	mov	a,LKModAll
	jz	TranslateToBufLKReleaseEnd

	; -- Escape-code for Alt-R
	jnb	acc.3, TranslateToBufLKClrModEXAR
	; send E0 escape code
	mov	r2,#0E0h
	call	RingBufCheckInsert

TranslateToBufLKClrModEXAR:
	; -- send break code
	mov	r2,#0F0h
	call	RingBufCheckInsert

	mov	a,LKModAll
	jb	acc.0, TranslateToBufLKReleaseSL
	jb	acc.1, TranslateToBufLKReleaseSR
	jb	acc.2, TranslateToBufLKReleaseAL
	jb	acc.3, TranslateToBufLKReleaseAR
	jb	acc.4, TranslateToBufLKReleaseC
	sjmp	TranslateToBufLKReleaseEnd

	; --- release modifiers
TranslateToBufLKReleaseSL:
	mov	r2,#012h
	call	RingBufCheckInsert
	sjmp	TranslateToBufLKReleaseEnd
TranslateToBufLKReleaseSR:
	mov	r2,#059h
	call	RingBufCheckInsert
	sjmp	TranslateToBufLKReleaseEnd
TranslateToBufLKReleaseAL:
	mov	r2,#011h
	call	RingBufCheckInsert
	sjmp	TranslateToBufLKReleaseEnd
TranslateToBufLKReleaseAR:
	mov	r2,#011h
	call	RingBufCheckInsert
	sjmp	TranslateToBufLKReleaseEnd
TranslateToBufLKReleaseC:
	mov	r2,#014h
	call	RingBufCheckInsert

TranslateToBufLKReleaseEnd:
	mov	LKModAll, #0
	sjmp	TranslateToBufLKEnd

TranslateToBufLKModEnd:


	; --------- process non-modifier keys
	; get AT scancode
	mov	a,RawBuf

	; --- LK typematic / metronome feature
	cjne	a,#0b4h, TranslateToBufLKNoMetronom
	mov	a,LKMetronomBuf
	sjmp	TranslateToBufLKGo
TranslateToBufLKNoMetronom:
	mov	LKMetronomBuf,a


TranslateToBufLKGo:
	mov	dptr,#LK2ATxlt0
	movc	a,@a+dptr
	mov	OutputBuf,a

	; clear received data flag
	clr	MiscRXCompleteF

	; keyboard disabled?
	jb	ATKbdDisableF,TranslateToBufLKEnd

	; ------ send make scancode
	; check for 0xE0 escape code
	jnb	ATTXMasqF,TranslateToBufLKNoEsc
	mov	r2,#0E0h
	call	RingBufCheckInsert

TranslateToBufLKNoEsc:
	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert

	; --- do not send the break code for some special keys now
	; the LED modifying keys ... (argh!)
	jnb	LKModBuf.6,TranslateToBufSendBreak
	mov	a, OutputBuf
	mov	ATBrkLedSBuf, a
	sjmp	TranslateToBufLKEnd

TranslateToBufSendBreak:
	; ------ send break scancode
	; check for 0xE0 escape code
	jnb	ATTXMasqF,TranslateToBufLKNoEsc2
	mov	r2,#0E0h
	call	RingBufCheckInsert

TranslateToBufLKNoEsc2:
	; send break code
	mov	r2,#0F0h
	call	RingBufCheckInsert

	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert

TranslateToBufLKEnd:
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
	jb	ATTFModF,BufTXWaitSent
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
	jnb	ATCmdLedF,ATCPNotLEDarg
	clr	ATCmdLedF
	mov	LKLEDBuf,#0

	; -- process LK-Keyboard LED data
	mov	LKLEDBuf,#080h
	; CapsLock
	mov	c,acc.2
	mov	LKLEDBuf.2,c
	; NumLock mapped to Compose
	mov	c,acc.1
	mov	LKLEDBuf.1,c
	; ScrollLock
	mov	c,acc.0
	mov	LKLEDBuf.3,c
	; will send data later. not every PS2-Device will tolerate 2ms serial delay before the ACK.
	setb	LKLEDCtrl1F
	setb	LKLEDCtrl2F
	setb	LKLEDCtrl3F
	setb	LKLEDSetF

	; -- set build-in LEDs
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

	ljmp	ATCPSendAck

ATCPNotLEDarg:
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
; helper: delay clock line status change for 10 microseconds
; FIXME: this is X-tal frequency dependant
;----------------------------------------------------------
ATTX_delay_clk:
	nop
	nop
	nop
	nop

	ret

;----------------------------------------------------------
; helper: delay clock release
; FIXME: this is X-tal frequency dependant
;----------------------------------------------------------
ATTX_delay_release:
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
; init uart with timer 1 as baudrate generator
; need 4800BPS
;----------------------------------------------------------
uart_timer1_init:
	mov	scon, #050h	; uart mode 1 (8 bit), single processor
	orl	tmod, #020h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 2, 8bit-auto-reload
	orl	pcon, #080h	; SMOD, bit 7 in PCON
	mov	th1, #uart_t1_4800_11059_2k
	mov	tl1, #uart_t1_4800_11059_2k
	clr	es		; disable serial interrupt
	setb	tr1

	clr	ri
	setb	ti

	ret

;----------------------------------------------------------
; init timer 0 for interval timing (fast 8 bit reload)
; need 40-50mus intervals
;----------------------------------------------------------
timer0_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #02h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th0, #interval_t0_85u_11059_2k
	mov	tl0, #interval_t0_85u_11059_2k
	setb	et0		; (IE.1) enable timer 0 interrupt
	setb	ATTFModF	; see timer 0 interrupt code
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
	orl	tmod, #01h;	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
	mov	th0, #interval_th_130u_11059_2k
	mov	tl0, #interval_tl_130u_11059_2k
;	mov	th0, #interval_th_1m_11059_2k
;	mov	tl0, #interval_tl_1m_11059_2k
	setb	et0		; (IE.1) enable timer 0 interrupt
	clr	ATTFModF	; see timer 0 interrupt code
	setb	MiscSleepF
	setb	tr0		; go
	ret

;----------------------------------------------------------
; init timer 0 in 16 bit mode for faked POST delay of of 20ms
;----------------------------------------------------------
timer0_20ms_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all upper bits
	orl	tmod, #01h;	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
	mov	th0, #interval_th_20m_11059_2k
	mov	tl0, #interval_tl_20m_11059_2k
	setb	et0		; (IE.1) enable timer 0 interrupt
	clr	ATTFModF	; see timer 0 interrupt code
	setb	MiscSleepF
	setb	tr0		; go
	ret

;----------------------------------------------------------
; Id
;----------------------------------------------------------
RCSId	DB	"$Id: kbdbabel_lk_ps2_8051.asm,v 1.3 2007/04/25 08:41:49 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom

	; -- enable interrupts
	setb	ea

	; -- init UART and timer0/1
	acall	uart_timer1_init
	acall	timer0_diag_init

	; -- clear all flags
	mov	20h,#0
	mov	21h,#0
	mov	22h,#0

	; -- init the ring buffer
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0

	; -- cold start flag
	setb	ATCmdResetF

; ----------------
Loop:
	; -- check input receive status
	jb	RI,LoopProcessLKData

	; -- check on new AT data received
	jb	ATCmdReceivedF,LoopProcessATcmd

	; -- check if AT communication active.
	jb	ATTFModF,Loop

	; -- delay flag
;	jb	MiscSleepF,Loop

	; -- check if commands may be sent to Keyboard
	jb	LKLEDSetF,LoopLKLED

	; -- check AT line status, clock line must not be busy
	jnb	p3.3,Loop

	; -- check data line for RX or TX status
	jb	p3.5,LoopATTX

	sjmp	LoopATRX

;----------------------------------------------------------
; helpers for the main loop
;----------------------------------------------------------
; ----------------
LoopProcessLKData:
; -- input data received, process the received scancode into output ring buffer
	mov	a,sbuf
	mov	RawBuf,a
	clr	RI

	; ------ dirty hack
	; send stored break code for LED modifying keys
	; a delay between make and break code is essential to avoid problems
	; with certain machines
	;
	; this is also done on LED modify-events.
	;
	mov	a, ATBrkLedSBuf
	jz	LoopLKLEDRet1
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2,ATBrkLedSBuf
	call	RingBufCheckInsert
	mov	ATBrkLedSBuf, #0
LoopLKLEDRet1:

	jb	ATCmdResetF, Loop
	setb	MiscRXCompleteF
	call	TranslateToBufLK
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
	jb	ATTFModF,LoopTXWaitSent
LoopCheckATEnd:
	ljmp	Loop


; ----------------
LoopATTX:
; -- Device-to-Host communication
	; -- send data on the AT line
	; some delay
	call	timer0_diag_init
LoopTXWaitDelay:
	jb	MiscSleepF,LoopTXWaitDelay

LoopSendData:
	; send data
	call	BufTX

	; -- keyboard reset/cold start: send AAh after some delay
	jnb	ATCmdResetF,LoopTXWaitDelayEnd
	clr	ATCmdResetF
	; -- optional delay of 20ms after faked cold start
	; yes, some machines will not boot without this, e.g. IBM PS/ValuePoint 433DX/D
	call	timer0_20ms_init
LoopTXResetDelay:
	jb	MiscSleepF,LoopTXResetDelay
	# -- send "self test passed"
	mov	r2,#0AAh
	call	RingBufCheckInsert
LoopTXWaitDelayEnd:
	ljmp	Loop

; ----------------
LoopLKLED:
; -- set keyboard LEDs
	; Adopted from the Sun-PS2-Code:
	; Sending two bytes of LED control code takes about 2ms due to 2 bytes @ 1200bps.
	; some PS2-to-USB-adaptors do not tolerate this delay in AT communication.

	; -- return if flag not set
	jnb	LKLEDSetF,LoopLKLEDEnd

	; -- return if serial transmission is active
	jnb	ti,LoopLKLEDEnd

	; -- check control-code-or-argument-bit
	jnb	LKLEDCtrl1F,LoopLKLEDCtrlE1
	; send control code1
	clr	ti
	mov	sbuf,#11h
	clr	LKLEDCtrl1F
	sjmp	LoopLKLEDEnd

LoopLKLEDCtrlE1:
	; -- check control-code-or-argument-bit
	jnb	LKLEDCtrl2F,LoopLKLEDCtrlE2
	clr	p1.4
	; send control code
	clr	ti
	mov	sbuf,#8Fh
	clr	LKLEDCtrl2F
	sjmp	LoopLKLEDEnd

LoopLKLEDCtrlE2:
	; -- check control-code-or-argument-bit
	jnb	LKLEDCtrl3F,LoopLKLEDCtrlE3
	; send control code
	clr	ti
	mov	sbuf,#13h
	clr	LKLEDCtrl3F
	sjmp	LoopLKLEDEnd

LoopLKLEDCtrlE3:
	; -- send argument
	clr	ti
	mov	sbuf,LKLEDBuf
	clr	LKLEDSetF

LoopLKLEDEnd:
	; ------ dirty hack
	; send stored break code for LED modifying keys
	; a delay between make and break code is essential to avoid problems
	; with certain machines
	mov	a, ATBrkLedSBuf
	jz	LoopLKLEDRet2
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2,ATBrkLedSBuf
	call	RingBufCheckInsert
	mov	ATBrkLedSBuf, #0
LoopLKLEDRet2:
	setb	p1.4
	ljmp	Loop

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	" Copyright 2006 by Alexander Kurz"
LIC02	DB	" "
GPL_S1	DB	" This program is free software; licensed under the terms of the GNU GPL V2"
;GPL01	DB	" This program is free software; you can redistribute it and/or modify"
;GPL02	DB	" it under the terms of the GNU General Public License as published by"
;GPL03	DB	" the Free Software Foundation; either version 2, or (at your option)"
;GPL04	DB	" any later version."
;GPL05	DB	" "
;GPL06	DB	" This program is distributed in the hope that it will be useful,"
;GPL07	DB	" but WITHOUT ANY WARRANTY; without even the implied warranty of"
;GPL08	DB	" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the"
;GPL09	DB	" GNU General Public License for more details."
;GPL10	DB	" "
; ----------------
	end
