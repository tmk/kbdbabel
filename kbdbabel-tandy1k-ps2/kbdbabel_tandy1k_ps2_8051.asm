; ---------------------------------------------------------------------
; Tandy 1000 Personal Computer to AT/PS2 keyboard transcoder
; for 8051 type processors.
;
; $KbdBabel: kbdbabel_tandy1k_ps2_8051.asm,v 1.1 2007/11/05 09:37:44 akurz Exp $
;
; Clock/Crystal: 24MHz or alternative 22.1184MHz or 18.432MHz.
; Note: Tandy 1000 Keyboard data bits are sampled on negative
; clock slope of the inverted clock line.
; There are less than 7 microseconds to samle the data bit.
; 12MHz or less is not sufficient to do this.
;
; Tandy 1000 Keyboard connect:
; Inverted Clock signal using a transistor and 4.7k resistors
; CLOCK - p3.2  (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
; DATA - p3.4	(Pin 14 on DIL40, Pin 8 on AT89C2051 PDIP20)
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
; PC Error	- p1.4
; PC Warn	- p1.3
; AT TX Communication abort	- p1.2
; AT RX Communication abort	- p1.1
; TX buffer full		- p1.0
;
; Build using the macroassembler by Alfred Arnold
; $ asl -L kbdbabel_tandy1k_ps2_8051.asm -o kbdbabel_tandy1k_ps2_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_tandy1k_ps2_8051
; write kbdbabel_tandy1k_ps2_8051.bin on an empty 27C256 or AT89C2051
;
; Copyright 2007 by Alexander Kurz
;
; This is free software.
; You may copy and redistibute this software according to the
; GNU general public license version 3 or any later verson.
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
KbBitBuf	sfrb	24h
KbClockMin	equ	26h
KbClockMax	equ	27h
ATBitCount	sfrb	28h	; AT scancode TX counter
RawBuf		equ	30h	; raw PC scancode
OutputBuf	equ	31h	; AT scancode
TXBuf		equ	32h	; AT scancode TX buffer
RingBufPtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	35h	; AT host-to-dev buffer
ATRXCount	equ	36h
ATRXResendBuf	equ	37h	; for AT resend feature

;------------------ bits
PCRXBitF	bit	B20.0	; RX-bit-buffer
PCRXCompleteF	bit	B20.1	; full and correct byte-received
PCRXActiveF	bit	B20.2	; receive in progress flag
ATTXBreakF	bit	B20.3	; Release/Break-Code flag
ATTXMasqF	bit	B20.4	; TX-AT-Masq-Char-Bit (send two byte scancode)
ATTXParF	bit	B20.5	; TX-AT-Parity bit
TFModF		bit	B20.6	; Timer modifier: alarm clock or clock driver
MiscSleepT0F	bit	B20.7	; sleep timer active flag
ATCommAbort	bit	B21.0	; AT communication aborted
ATHostToDevIntF	bit	B21.1	; host-do-device init flag triggered by ex1 / unused.
ATHostToDevF	bit	B21.2	; host-to-device flag for timer
ATTXActiveF	bit	B21.3	; AT TX active
ATCmdReceivedF	bit	B21.4	; full and correct AT byte-received
ATCmdResetF	bit	B21.5	; reset
ATCmdLedF	bit	B21.6	; AT command processing: set LED
ATCmdScancodeF	bit	B21.7	; AT command processing: set scancode
ATKbdDisableF	bit	B22.0	; Keyboard disable
ATTXMasqPrtScrF	bit	B22.1	; TX-AT-Masq-Char-Bit (for PrtScr-Key)
ATTXMasqPauseF	bit	B22.2	; TX-AT-Masq-Char-Bit (for Pause-Key, not implemented here)
Tandy2kCapsLF	bit	B22.3	; Switch translation behaviour
Tandy2kNumLF	bit	B22.4	; Switch translation behaviour
;------------------ arrays
RingBuf		equ	40h
RingBufSizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	50h	; the stack

;----------------------------------------------------------
; start
;----------------------------------------------------------
	org	0	; cold start
	ljmp	Start
;----------------------------------------------------------
; interrupt handlers
;----------------------------------------------------------
;----------------------------
; int 0, connected to the inverted keyboard clock line.
; With a raising signal on the clock line there are 7mus
; left to read the data line.
;----------------------------
	org	03h	; external interrupt 0
	jnb	P3.4, HandleInt0	; this is time critical
	setb	PCRXBitF
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
; read one data bit triggered by the keyboard clock line
; rotate bit into KbBitBuf.
; Last clock sample interval is stored in r6
; rotate bit into 22h, 23h.
; Num Bits is in r7
; buffer: r5
;----------------------------------------------------------
HandleInt0:
	push	acc
	push	psw

;	clr	p3.7
;	nop
;	setb	p3.7

	; receive in progress flag
	setb	PCRXActiveF
; --------------------------- diag: check if RX happens during AT-TX
	; check if flag is set
	jnb	ATTXActiveF,interCharFlagOk
	clr	p1.3
	sjmp	interCharTestEnd
interCharFlagOk:
	setb	p1.3
interCharTestEnd:
; --------------------------- get and save data samples
; -- write to mem, first 8 bits
	mov	c,PCRXBitF	; new bit
	mov	a,KbBitBuf
	rrc	a
	mov	KbBitBuf,a

; -- diag: write data bits to LED-Port
;	mov	a,KbBitBuf
;	xrl	a,0FFh
;	mov	p1,a

; -- reset bit buffer
	clr	PCRXBitF

; --------------------------- reset the timer
	; stop timer 1
	clr	tr1

	; reset timer value
	mov	th1, #interval_th_11_bit
	mov	tl1, #interval_tl_11_bit

	; start timer 1
	setb	tr1

; --------------------------- check bit number
; -- checks by bit number
	mov	a,r7
	subb	a,#07h
	jnz	Int0IncReturn

; -- special handling for last bit: output
	setb	p1.4		; error LED off
	mov	a,KbBitBuf
	mov	RawBuf,a
	mov	r7,#0
	setb	PCRXCompleteF	; fully received flag
	clr	PCRXActiveF	; receive in progress flag
	sjmp	Int0Return

; --------------------------- done
Int0IncReturn:
; -- inc the bit counter
	inc	r7
Int0Return:
	pop	psw
	pop	acc
	reti

;----------------------------------------------------------
; timer 1 int handler:
; timer is used to measure the clock-signal-interval length
; Stop the timer after overflow, cleanup RX buffers
; RX timeout at 18.432MHz with th1,tl1=0f8h,00h -> 1.3ms
;----------------------------------------------------------
HandleTF1:
	; stop timer
	clr	tr1

	; cleanup buffers
	mov	KbBitBuf,#0
	mov	r7,#0

	; reset timer value
	mov	th1, #interval_th_11_bit
	mov	tl1, #interval_tl_11_bit

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
; Tandy 1000 Personal Computer to AT translaton table
;----------------------------------------------------------
Tandy1k2ATxlt0	DB	  0h, 076h, 016h, 01eh, 026h, 025h, 02eh, 036h,  03dh, 03eh, 046h, 045h, 04eh, 055h, 066h,  0dh
Tandy1k2ATxlt1	DB	015h, 01dh, 024h, 02dh, 02ch, 035h, 03ch, 043h,  044h, 04dh, 054h, 05bh, 05ah, 014h, 01ch, 01bh
Tandy1k2ATxlt2	DB	023h, 02bh, 034h, 033h, 03bh, 042h, 04bh, 04ch,  052h, 075h, 012h, 06bh, 01ah, 022h, 021h, 02ah
Tandy1k2ATxlt3	DB	032h, 031h, 03ah, 041h, 049h, 04ah, 059h,   0h,  011h, 029h, 058h,  05h,  06h,  04h,  0ch,  03h
Tandy1k2ATxlt4	DB	00bh, 083h,  0ah,  01h,  09h, 077h, 07eh, 06ch,  075h, 07dh, 072h, 06bh, 073h, 074h, 074h, 069h
Tandy1k2ATxlt5	DB	072h, 07ah, 070h, 071h,   0h, 070h, 071h, 05ah,  06ch,  78h,  07h,   0h,   0h,   0h,   0h,   0h
Tandy1k2ATxlt6	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
Tandy1k2ATxlt7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

;----------------------------------------------------------
; Tandy 1000 Personal Computer to AT translaton table extension
; Bit-Table for multi-byte-AT-Scancodes
;
; bit 0: E0-Escape
; bit 1: send Make E0,12,E0,7C / BreakE0,F0,7C,E0,F0,12 (PrtScr)
; bit 2: send Make E1,14,77,E1,F0,14,F0,77 (Pause)
; bit 3: toggle CapsLock
; bit 4: toggle NumLock
;----------------------------------------------------------
Tandy1k2ATxlte0	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
Tandy1k2ATxlte1	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
Tandy1k2ATxlte2	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,  01h,   0h,  01h,   0h,   0h,   0h,   0h
Tandy1k2ATxlte3	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,  02h,    0h,   0h,  08h,   0h,   0h,   0h,   0h,   0h
Tandy1k2ATxlte4	DB	  0h,   0h,   0h,   0h,   0h,  10h,   0h,   0h,    0h,   0h,  01h,   0h,   0h,   0h,  01h,   0h
Tandy1k2ATxlte5	DB	  0h,   0h,   0h,  01h,  04h,  01h,   0h,  01h,   01h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
Tandy1k2ATxlte6	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
Tandy1k2ATxlte7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

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
TranslateToBufTandy1k:
	; translate from Tandy 1000 to AT scancode
	mov	a,RawBuf

	; save make/break bit 7
	mov	c,acc.7
	mov	ATTXBreakF,c

	; ignore make/break bit 7
	anl	a,#7fh

	; check for 2-byte scancodes
	mov	r4,a
	mov	dptr,#Tandy1k2ATxlte0
	movc	a,@a+dptr
	mov	c,acc.0
	mov	ATTXMasqF,c
	mov	c,acc.1
	mov	ATTXMasqPrtScrF,c
	mov	c,acc.2
	mov	ATTXMasqPauseF,c
	mov	c,acc.3
	mov	Tandy2kCapsLF,c
	mov	c,acc.4
	mov	Tandy2kNumLF,c
	mov	a,r4

	; get AT scancode
	mov	dptr,#Tandy1k2ATxlt0
	movc	a,@a+dptr
	mov	OutputBuf,a

	; clear received data flag
	clr	PCRXCompleteF

	; keyboard disabled?
	jnb	ATKbdDisableF,TranslateToBufNotDisabled
	ljmp	TranslateToBufEnd
TranslateToBufNotDisabled:

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

	; check for special CapsLock
	jnb	Tandy2kCapsLF,TranslateToBufNoCapsLock
	mov	r2, OutputBuf
	call	RingBufCheckInsert
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2, OutputBuf
	call	RingBufCheckInsert
	sjmp	TranslateToBufEnd
TranslateToBufNoCapsLock:

	; check for special NumLock
	jnb	Tandy2kNumLF,TranslateToBufNoNumLock
	mov	r2, OutputBuf
	call	RingBufCheckInsert
	mov	r2,#0F0h
	call	RingBufCheckInsert
	mov	r2, OutputBuf
	call	RingBufCheckInsert
	sjmp	TranslateToBufEnd
TranslateToBufNoNumLock:

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
; init timer 1 for PC interval timing
;----------------------------------------------------------
timer1_init:
;	anl	tmod, #0fh	; clear all upper bits
	orl	tmod, #10h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 1, 16bit
	mov	th1, #interval_th_11_bit
	mov	tl1, #interval_tl_11_bit
	setb	et1		; (IE.3) enable timer 1 interrupt
	setb	tr1		; timer 1 run
	ret

;----------------------------------------------------------
; init timer 0 for interval timing (fast 8 bit reload)
; need 40-50mus intervals
;----------------------------------------------------------
timer0_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #02h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th0, #interval_t0_40u_24M
	mov	tl0, #interval_t0_40u_24M
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
	orl	tmod, #01h;	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
	mov	th0, #interval_th_128u_24M
	mov	tl0, #interval_tl_128u_24M
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
	orl	tmod, #01h;	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
	mov	th0, #interval_th_20m_24M
	mov	tl0, #interval_tl_20m_24M
	setb	et0		; (IE.1) enable timer 0 interrupt
	clr	TFModF		; see timer 0 interrupt code
	setb	MiscSleepT0F
	setb	tr0		; go
	ret

;----------------------------------------------------------
; Id
;----------------------------------------------------------
RCSId	DB	"$Id: kbdbabel_tandy1k_ps2_8051.asm,v 1.1 2007/11/05 09:42:10 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom

	; -- enable interrupts
	setb	ea

	; -- some delay of 500ms to eleminate stray data sent by the PC-Keyboard on power-up
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

	; -- enable interrupts int0
	setb	ex0		; external interupt 0 enable
	setb	it0		; falling edge trigger for int 0

	; -- clear all flags
	mov	B20,#0
	mov	B21,#0
	mov	B22,#0
	mov	B23,#0

	; -- init the ring buffer
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0

	; -- cold start flag
	setb	ATCmdResetF

; ----------------
Loop:
	; -- check PC receive status
	jb	PCRXCompleteF,LoopProcessTandy2kData

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
; ----------------
LoopProcessTandy2kData:
; -- PC data received, process the received scancode into output ring buffer
	call	TranslateToBufTandy1k
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
	jb	PCRXActiveF,LoopTXWaitDelayEnd	; new receive in progress
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
GPL03	DB	"   the Free Software Foundation; either version 3, or (at your option)"
GPL04	DB	"   any later version."
GPL05	DB	"   "
GPL06	DB	"   This program is distributed in the hope that it will be useful,"
GPL07	DB	"   but WITHOUT ANY WARRANTY; without even the implied warranty of"
GPL08	DB	"   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the"
GPL09	DB	"   GNU General Public License for more details."
GPL10	DB	"   "
; ----------------
	end
