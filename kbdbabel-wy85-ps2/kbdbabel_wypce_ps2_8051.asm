; ---------------------------------------------------------------------
; Wyse WY-PCE to AT/PS2 keyboard transcoder for 8051 type processors
;
; $Id: kbdbabel_wypce_ps2_8051.asm,v 1.2 2008/05/02 06:39:18 akurz Exp $
;
; Clock/Crystal: 24MHz.
;
; Wyse Keyboard connect:
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
; $ asl -L kbdbabel_wypce_ps2_8051.asm -o kbdbabel_wypce_ps2_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_wypce_ps2_8051
; write kbdbabel_wypce_ps2_8051.bin on an empty 27C256 or AT89C2051
;
; Copyright 2007, 2008 by Alexander Kurz
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
InputBitBuf	equ	24h	; Keyboard input bit buffer
ATBitCount	sfrb	25h	; AT scancode TX counter
RawBuf		equ	26h	; raw scancode
OutputBuf	equ	27h	; AT scancode
TXBuf		equ	28h	; AT scancode TX buffer
DKSHelperBuf	sfrb	29h	; DeltaKeyState bit compare helper buffer, must be bit-adressable
DKSXORBuf	sfrb	2ah	; DeltaKeyState XOR-result helper buffer, must be bit-adressable
RingBufPtrIn	equ	2eh	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	2fh	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	30h	; AT host-to-dev buffer
ATRXCount	equ	31h
ATRXResendBuf	equ	32h	; for AT resend feature
RXBitCount	equ	33h	; Interrupt handler Bit Count
RXWordCount	equ	34h	; Interrupt handler Word Count
DKSBitCount	equ	35h	; DeltaKeyState Bit counter
DKSByteCount	equ	36h	; DeltaKeyState Byte counter
DKSXltOffset	equ	37h	; DeltaKeyState Scancode-Translation-Table-Offset
DKSBytes	equ	16	; Readonly, Number of state bytes to be processed

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
TF1ModF		bit	B22.2	; Keyboard RX-Timer Modifier:  Sleep=0, Clock-Generator=1
MiscSleepT1F	bit	B22.3	; sleep timer active flag, timer 1
RXActiveF	bit	B22.4	; Keyboard Clock transmit active
ATLedScrollF	bit	B22.5
ATLedNumF	bit	B22.6
ATLedCapsF	bit	B22.7


;------------------ arrays
KeyStateBuf1	equ	38h	; size is 20 byte
KeyStateBuf2	equ	4ch	; size is 20 byte
RingBuf		equ	60h
RingBufSizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	70h	; the stack

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
	reti
;	ljmp	HandleInt0
;----------------------------
	org	0bh	; handle TF0
	ljmp	HandleTF0
;----------------------------
	org	13h	; Int 1
	reti
;	ljmp	HandleInt1
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
; timer 1 int handler used for different purposes
; depending on TF1ModF
;
; TF1ModF=0:
; timer is used as 16-bit alarm clock for 20ms intervals.
; Stop the timer after overflow, MiscSleepT1F is cleared
;
; TF1ModF=1:
; timer is used in 8-bit-auto-reload-mode to generate
; 152-160 Wyse scancode clock cycles with 15-40 microseconds timings.
; In worst case this routine takes 40 processor cycles.
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
	mov	a,r5		; 1,9
	rr	a		; 1
	mov	c,p3.4		; 1
	mov	acc.7,c		; 2
	mov	r5,a		; 1,14

	; --- 8 bits each byte
	djnz	r6,timer1NotSaveWord	; 2,16
	mov	r6,#8			; 1

	; --- store 8 bit to the 20-byte-buffer
;	clr	p1.0
	xch	a,r1		; 1
	mov	a,RXWordCount	; 2
	add	a,#KeyStateBuf1	; 2
	xch	a,r1		; 1
	cpl	a		; 1
	mov	@r1,a		; 1
	inc	RXWordCount	; 2
;	setb	p1.0

timer1NotSaveWord:
	clr	p3.2		; 1,18/28
	; --- 152-160-clocks
	djnz	RXBitCount,timer1NotFin	; 2,20/30

	; --- 152-160 clocks finished
	clr	RXActiveF
	setb	RXCompleteF
	clr	tr1
	sjmp	timer1Return
timer1NotFin:
	setb	p3.2		; 1,21/31

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
; Notes on the keyboard-mapping
;
; The "#" key on my test keyboard is broken: "Select" -> #
;----------------------------------------------------------
;----------------------------------------------------------
; WY-PCE to AT translaton table
;----------------------------------------------------------
WYPCE2ATxlt0	DB	 6ch,  49h,  42h,  3ch,  2eh,  5dh,  09h,  76h,   79h,  55h,  5ah,  35h,  11h,  1eh,  0eh,  16h
WYPCE2ATxlt1	DB	 5ah,  41h,  07h,  44h,  77h,  58h,  14h,  61h,   71h,  78h,  4ah,  43h,  4ch,  59h,   0h,  12h
WYPCE2ATxlt2	DB	 70h,  7dh,  7bh,  7ch,  52h,  5dh,  14h,  29h,   4ah,  1ah,  4bh,  4eh,  11h,  5bh,  7eh,  54h
WYPCE2ATxlt3	DB	 69h,  32h,  3bh,  2ch,  26h,  70h,  83h,  66h,   72h,  3ah,  33h,  4dh,  25h,  6ch,  0bh,  74h
WYPCE2ATxlt4	DB	 7ah,  31h,  34h,  2dh,  45h,  7dh,  03h,  75h,   6bh,  2ah,  23h,  1dh,  36h,  71h,  0ch,  72h
WYPCE2ATxlt5	DB	 73h,  22h,  2bh,  24h,  3dh,  69h,  04h,  6bh,   74h,  21h,  1bh,  15h,  3eh,  7ah,  06h,   0h
WYPCE2ATxlt6	DB	 75h,  01h,  1ch,  0ah,  46h,  05h,   0h,  0dh,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
WYPCE2ATxlt7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

;----------------------------------------------------------
; WY-PCE to AT translaton table
; Bit-Table for two-byte-AT-Scancodes
; bit 0: E0-Escape
; bit 1: E0,12,E0-Escape (PrtScr)
; bit 2: send E1,14,77,E1,F0,14,F0,77 (Pause)
;----------------------------------------------------------
WYPCE2ATxlte0	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
WYPCE2ATxlte1	DB	 01h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
WYPCE2ATxlte2	DB	  0h,   0h,   0h,   0h,   0h,   0h,  01h,   0h,   01h,   0h,   0h,   0h,  01h,   0h,   0h,   0h
WYPCE2ATxlte3	DB	  0h,   0h,   0h,   0h,   0h,  01h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,  01h,   0h,  01h
WYPCE2ATxlte4	DB	  0h,   0h,   0h,   0h,   0h,  01h,   0h,  01h,    0h,   0h,   0h,   0h,   0h,  01h,   0h,  01h
WYPCE2ATxlte5	DB	  0h,   0h,   0h,   0h,   0h,  01h,   0h,  01h,    0h,   0h,   0h,   0h,   0h,  01h,   0h,  02h
WYPCE2ATxlte6	DB	  0h,   0h,   0h,   0h,   0h,   0h,  04h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
WYPCE2ATxlte7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

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
	; -- check keyboard id
	clr	c
	mov	a,#18
	add	a,#KeyStateBuf1
	mov	r0,a
	mov	a,@r0
;	anl	a,#083h
	cjne	a,#083h,DeltaKeyStateEnd	; 83h is the Wyse-PCE keyboard id

	; -- translation table offset
	mov	DKSXltOffset,#0
	; -- 16 byte
	mov	DKSByteCount,#DKSBytes

DeltaKeyStateByteLoop:
	clr	p1.4
	; -- get data from input buffer
	clr	c
	mov	a,#DKSBytes
	subb	a,DKSByteCount
	add	a,#KeyStateBuf1
	mov	r0,a
	mov	a,@r0
	mov	DKSHelperBuf,a

	; -- get data from state buffer
	clr	c
	mov	a,#DKSBytes
	subb	a,DKSByteCount
	add	a,#KeyStateBuf2
	mov	r0,a
	mov	a,@r0
	mov	DKSXORBuf,a

	; -- store input data to state buffer
	mov	a,DKSHelperBuf
	mov	@r0,a

	; -- XOR input and state buffer
	xrl	a,DKSXORBuf
	mov	DKSXORBuf,a

	; -- changes?
	jnz	DeltaKeyStateByteChange

	; -- no changes: inc XLT-Offset by 8
	mov	a,DKSXltOffset
	clr	c
	add	a,#8
	mov	DKSXltOffset,a
	sjmp	DeltaKeyStateByteLoopEnd

	; -- bits changed: do bit analysis
DeltaKeyStateByteChange:
	clr	p1.3
	mov	DKSBitCount,#8

DeltaKeyStateBitLoop:
	clr	p1.3
	jnb	DKSXORBuf.0,DeltaKeyStateBitLoopEnd
;	clr	p1.0

	; -- get make/break bit
	mov	c,DKSHelperBuf.0
	cpl	c
	mov	ATTXBreakF,c

	; -- send data
	mov	a,DKSXltOffset
	mov	RawBuf,a
	call	TranslateToBuf
DeltaKeyStateBitLoopEnd:

	; -- rotate XORed and input octet
	mov	a,DKSHelperBuf
	rr	a
	mov	DKSHelperBuf,a
	mov	a,DKSXORBuf
	rr	a
	mov	DKSXORBuf,a

	; -- inc XLT-Offset
	inc	DKSXltOffset

;	setb	p1.0
	setb	p1.3

	djnz	DKSBitCount,DeltaKeyStateBitLoop

DeltaKeyStateByteLoopEnd:
	setb	p1.4
	djnz	DKSByteCount,DeltaKeyStateByteLoop

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
	mov	dptr,#WYPCE2ATxlte0
	movc	a,@a+dptr
	mov	c,acc.0
	mov	ATTXMasqF,c
	mov	c,acc.1
	mov	ATTXMasqPrtScrF,c
	mov	c,acc.2
	mov	ATTXMasqPauseF,c

	mov	a,RawBuf

	; get AT scancode
	mov	dptr,#WYPCE2ATxlt0
	movc	a,@a+dptr
	mov	OutputBuf,a

	; clear received data flag
	clr	RXCompleteF

	; keyboard disabled?
	jb	ATKbdDisableF,TranslateToBufEnd

	; check for PrtScr Argh!
	jnb	ATTXMasqPrtScrF,TranslateToBufNoPrtScr
	jnb	ATTXBreakF,TranslateToBufPrtScrMake
	call	ATPrtScrBrk
	sjmp	TranslateToBufEnd
TranslateToBufPrtScrMake:
	call	ATPrtScrMake
	sjmp	TranslateToBufEnd
TranslateToBufNoPrtScr:

	; check for Pause, only Make-Code *AAAARRRGH*
	jnb	ATTXMasqPauseF,TranslateToBufNoPause
	jb	ATTXBreakF,TranslateToBufNoPause
	call	ATPause
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

	; inter-character delay 0.13ms
	call	timer0_130u_init
BufTXWaitDelay:
	jb	MiscSleepT0F,BufTXWaitDelay

	; abort if new receive from keyboard is in progress
	jb	RXActiveF,BufTXEnd

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
	call	timer0_40u_init

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
	mov	ATLedNumF,c
	cpl	c
	mov	p1.5,c
	; CapsLock
	mov	c,acc.2
	mov	ATLedCapsF,c
	cpl	c
	mov	p1.6,c
	; ScrollLock
	mov	c,acc.0
	mov	ATLedScrollF,c
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
; check if there is AT data to send
;----------------------------------------------------------
ATTX:
; -- Device-to-Host communication
	; -- check if there is data to send, send data
	call	BufTX

	; -- keyboard reset/cold start: send AAh after some delay
	jnb	ATCmdResetF,ATTXWaitDelayEnd
	clr	ATCmdResetF
	; -- optional delay after faked cold start
	; yes, some machines will not boot without this, e.g. IBM PS/ValuePoint 433DX/D
	call	timer0_20ms_init
ATTXResetDelay:
	jb	MiscSleepT0F,ATTXResetDelay

	; -- init the key-state buffer
	call	DeltaKeyState

	; -- send "self test passed"
	mov	r2,#0AAh
	call	RingBufCheckInsert
ATTXWaitDelayEnd:
	ret

;----------------------------------------------------------
; helper, send AT/PS2 PrtScr Break
;----------------------------------------------------------
ATPrtScrBrk:
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

	ret

;----------------------------------------------------------
; helper, send AT/PS2 PrtScr Break
;----------------------------------------------------------
ATPrtScrMake:
	mov	r2,#0E0h
	call	RingBufCheckInsert
	mov	r2,#012h
	call	RingBufCheckInsert
	mov	r2,#0E0h
	call	RingBufCheckInsert
	mov	r2,#07ch
	call	RingBufCheckInsert

	ret

;----------------------------------------------------------
; helper, send AT/PS2 Pause
;----------------------------------------------------------
ATPause:
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
; for Wyse Clock generation.
; interval is 25 microseconds
;----------------------------------------------------------
timer1_WyseClk_init:
	clr	tr1

	; --- diag trigger
	clr	p3.7
	nop
	setb	p3.7

	setb	TF1ModF			; see timer 1 interrupt code
	mov	r6,#8			; 8 bits per word
	mov	a,#159			; clock counter

	; --- LEDs are controlled via the clock count
	jnb	ATLedScrollF,timer1_WyseClk_noScroll
	dec	a
timer1_WyseClk_noScroll:

	jnb	ATLedNumF,timer1_WyseClk_noNum
	dec	a
	dec	a
timer1_WyseClk_noNum:

	jnb	ATLedCapsF,timer1_WyseClk_noCaps
	subb	a,#4
timer1_WyseClk_noCaps:

	mov	RXBitCount,a
	mov	RXWordCount,#0

	anl	tmod, #0fh	; clear all lower bits
	orl	tmod, #20h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th1, #interval_t1_25u_24M
	mov	tl1, #interval_t1_25u_24M
	setb	et1		; (IE.3) enable timer 1 interrupt

	setb	p3.2

	setb	RXActiveF
	setb	tr1		; go
	ret

;----------------------------------------------------------
; init timer 1 in 16 bit mode
;----------------------------------------------------------
timer1_10ms_init:
	clr	tr1
	anl	tmod, #0fh	; clear all upper bits
	orl	tmod, #10h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 1, 16bit
	mov	th1, #interval_th_10m_24M
	mov	tl1, #interval_tl_10m_24M
	setb	et1		; (IE.3) enable timer 1 interrupt
	setb	MiscSleepT1F
	clr	TF1ModF		; see timer 1 interrupt code
	setb	tr1		; go
	ret

;----------------------------------------------------------
; init timer 0 for interval timing (fast 8 bit reload)
; need 40mus intervals
;----------------------------------------------------------
timer0_40u_init:
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
timer0_130u_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
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
	orl	tmod, #01h	; M0,M1, bit0,1 in TMOD, timer 0 in mode 1, 16bit
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
RCSId	DB	"$KbdBabel: kbdbabel_wypce_ps2_8051.asm,v 1.2 2008/05/01 16:49:37 akurz Exp $"

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
;	acall	timer1_WyseClk_init
;	acall	timer0_130u_init

	; -- external interrupts
	clr	ex0		; disable external interupt 0
	clr	ex1		; disable external interupt 1

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
	; -- check Keyboard RX-Poll-Pause
	jb	TF1ModF, LoopKbdClock
	jb	MiscSleepT1F,LoopKbdDone
	acall	timer1_WyseClk_init
	sjmp	LoopKbdDone


	; -- check if Keyboard-Clocks are sent, start delay timer when finished
LoopKbdClock:
	jb	RXActiveF,LoopKbdDone
	call	timer1_10ms_init

LoopKbdDone:
	; -- check Keyboard receive status
	jb	RXCompleteF,LoopProcessData

	; -- check on new AT data received
	jb	ATCmdReceivedF,LoopProcessATcmd

	; -- check if AT communication active.
	jb	TFModF,Loop

	; -- check AT line status, clock line must not be busy
	jnb	p3.3,Loop

	; -- check for AT RX data
	jnb	p3.5,LoopATRX

	; -- stay in idle mode when Wyse data transfer is active
	jb	RXActiveF,Loop

	; -- send data, if data is present
	call	ATTX

;	; -- check if AT communication active.
;	jb	TFModF,Loop
;
;	; -- may do other things while idle here ...

	sjmp loop

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
	call	timer0_40u_init

	; wait for completion
LoopTXWaitSent:
	jb	TFModF,LoopTXWaitSent
LoopCheckATEnd:
	ljmp	Loop

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	"   Copyright 2007, 2008 by Alexander Kurz"
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
