; ---------------------------------------------------------------------
; Acorn A5000 to AT/PS2 keyboard transcoder for 8051 type processors.
;
; $KbdBabel: kbdbabel_a5000_ps2_8051.asm,v 1.1 2007/11/10 23:49:32 akurz Exp $
;
; Clock/Crystal: 24MHz (test) 12MHz (planned later).
;
; A5000 Keyboard connect:
; The reset-line is pulled up with 4k7
; Pin 1 (Reset)	- p3.2 (Pin 12 on DIL40, Pin 6 on AT89C2051 PDIP20, Int 0)
; Inverted serial signal using transistors and 4.7k resistors
; is connected to the serial port lines
; Pin 5 (TxD)	- p3.0 (Pin 10 on DIL40, Pin 2 on AT89C2051 PDIP20, RD)
; Pin 6 (RxD)	- p3.1 (Pin 11 on DIL40, Pin 3 on AT89C2051 PDIP20, TX)
;
; AT Host connect:
; DATA		- p3.5	(Pin 15 on DIL40, Pin 9 on AT89C2051 PDIP20)
; CLOCK		- p3.3	(Pin 13 on DIL40, Pin 7 on AT89C2051 PDIP20, Int 1)
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
; Build using the macroassembler by Alfred Arnold
; $ asl -L kbdbabel_a5000_ps2_8051.asm -o kbdbabel_a5000_ps2_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_a5000_ps2_8051
; write kbdbabel_a5000_ps2_8051.bin on an empty 27C256 or AT89C2051
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
A5kKbdLeds	sfrb	24h	; A5000 LED buffer
ATBitCount	sfrb	28h	; AT scancode TX counter
RawBuf		equ	30h	; raw input scancode
OutputBuf	equ	31h	; AT scancode
TXBuf		equ	32h	; AT scancode TX buffer
RingBufPtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	35h	; AT host-to-dev buffer
ATRXCount	equ	36h
ATRXResendBuf	equ	37h	; for AT resend feature
;KbClockIntBuf	equ	33h
A5kKbdId	equ	34h
A5kRxBuf	equ	35h

;------------------ bits
MiscRXCompleteF	bit	B20.1	; full and correct byte-received
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
A5kRxBreakF	bit	B22.1	; Make/Break bit
A5kResetF	bit	B22.2	; keyboard reset key pressed: do reset
A5kKbdSetLedF	bit	B22.3	; send LED control command to keyboard

;------------------ arrays
RingBuf		equ	40h
RingBufSizeMask	equ	0fh	; 16 byte ring-buffer size

;------------------ stack
StackBottom	equ	50h	; the stack

;------------------ constants
;-------- Commands to Acorn-Keyboard, copy from linux-2.4.35/drivers/acorn/char/keyb_arc.c
ACmdHRST	equ	0ffh	; reset keyboard
ACmdRAK1	equ	0feh	; reset response
ACmdRAK2	equ	0fdh	; reset response
ACmdBACK	equ	03fh	; Ack for first keyboard pair
ACmdSMAK	equ	033h	; Last data byte ack (key scanning + mouse movement scanning)
ACmdMACK	equ	032h	; Last data byte ack (mouse movement scanning)
ACmdSACK	equ	031h	; Last data byte ack (key scanning)
ACmdNACK	equ	030h	; Last data byte ack (no scanning, mouse data)
ACmdRQMP	equ	022h	; Request mouse data
ACmdPRST	equ	021h	; nothing
ACmdRQID	equ	020h	; Request ID

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
; The reset switch on the A5000-Keyboard has been pressed.
;----------------------------------------------------------
HandleInt0:
	mov	p1,#0

; -- wait till reset key is released
	jnb	p3.2,HandleInt0

	setb	A5kResetF

	mov	p1,#0ffh
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
; serial interrupt handler:
;----------------------------------------------------------
HandleRITI:
	clr	p3.7
	nop
	setb	p3.7
	reti;

;----------------------------------------------------------
; Acorn A5000 to AT translaton table
;----------------------------------------------------------
A5k2ATxlt0	DB	 76h,  05h,  06h,  04h,  0ch,  03h,  0bh,  83h,   0ah,  01h,  09h,  78h,  07h,   0h,  7eh,   0h
A5k2ATxlt1	DB	 0eh,  16h,  1eh,  26h,  25h,  2eh,  36h,  3dh,   3eh,  46h,  45h,  4eh,  55h,  61h,  66h,  70h
A5k2ATxlt2	DB	 6ch,  7dh,  77h,  4ah,  7ch,   0h,  0dh,  15h,   1dh,  24h,  2dh,  2ch,  35h,  3ch,  43h,  44h
A5k2ATxlt3	DB	 4dh,  54h,  5bh,  5dh,  71h,  69h,  7ah,  6ch,   75h,  7dh,  7bh,  58h,  1ch,  1bh,  23h,  2bh
A5k2ATxlt4	DB	 34h,  33h,  3bh,  42h,  4bh,  4ch,  52h,  5ah,   6bh,  73h,  74h,  79h,  12h,  61h,  1ah,  22h
A5k2ATxlt5	DB	 21h,  2ah,  32h,  31h,  3ah,  41h,  49h,  4ah,   59h,  75h,  69h,  72h,  7ah,  14h,  11h,  29h
A5k2ATxlt6	DB	 11h,  14h,  6bh,  72h,  74h,  70h,  71h,  5ah,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
A5k2ATxlt7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

;----------------------------------------------------------
; Acorn A5000 to AT translaton table
; Bit-Table for two-byte-AT-Scancodes
; bit 0: E0-Escape
; bit 1: send Make E0,12,E0,7C / BreakE0,F0,7C,E0,F0,12 (PrtScr)
; bit 2: send Make E1,14,77,E1,F0,14,F0,77 (Pause)
;----------------------------------------------------------
A5k2ATxlte0	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,  02h,   0h,  04h
A5k2ATxlte1	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,  01h
A5k2ATxlte2	DB	 01h,  01h,   0h,  01h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
A5k2ATxlte3	DB	  0h,   0h,   0h,   0h,  01h,  01h,  01h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
A5k2ATxlte4	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
A5k2ATxlte5	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,  01h,   0h,   0h,   0h,   0h,   0h,   0h
A5k2ATxlte6	DB	 01h,  01h,  01h,  01h,  01h,   0h,   0h,  01h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
A5k2ATxlte7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

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
TranslateToBufA5k:
	; save make/break bit 7
	mov	c,A5kRxBreakF
	mov	ATTXBreakF,c

	; translate from Atari ST to AT scancode
	mov	a,RawBuf

	; check 2-byte scancodes
	mov	r4,a
	mov	dptr,#A5k2ATxlte0
	movc	a,@a+dptr
	mov	c,acc.0
	mov	ATTXMasqF,c
	mov	a,r4

	; get AT scancode
	mov	dptr,#A5k2ATxlt0
	movc	a,@a+dptr

	; save AT scancode
	mov	OutputBuf,a

	; clear received data flag
	clr	MiscRXCompleteF

	; keyboard disabled?
	jb	ATKbdDisableF,TranslateToBufA5kEnd

	; check for 0xE0 escape code
	jnb	ATTXMasqF,TranslateToBufA5kNoEsc
	mov	r2,#0E0h
	call	RingBufCheckInsert

TranslateToBufA5kNoEsc:
	; check for 0xF0 release / break code
	jnb	ATTXBreakF,TranslateToBufA5kNoRelease
	mov	r2,#0F0h
	call	RingBufCheckInsert

TranslateToBufA5kNoRelease:
	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert

TranslateToBufA5kEnd:
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
;	clr	ti
;	mov	sbuf,ATRXBuf
;ATCPWait:
;	jnb	ti,ATCPWait

	; -- get received AT command
	mov	a,ATRXBuf
	clr	ATCmdReceivedF

	; -- argument for 0xed command: set keyboard LED
	jnb	ATCmdLedF,ATCPNotEDarg
	clr	ATCmdLedF

	mov	A5kKbdLeds,#0

	; -- set build-in LEDs
	; NumLock
	mov	c,acc.1
	mov	A5kKbdLeds.1,c
	cpl	c
	mov	p1.5,c
	; CapsLock
	mov	c,acc.2
	mov	A5kKbdLeds.0,c
	cpl	c
	mov	p1.6,c
	; ScrollLock
	mov	c,acc.0
	mov	A5kKbdLeds.2,c
	cpl	c
	mov	p1.7,c

	setb	A5kKbdSetLedF
	ljmp	ATCPSendAck

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
	; -- send "self test passed"
	mov	r2,#0AAh
	call	RingBufCheckInsert
ATTXWaitDelayEnd:
	ret

;----------------------------------------------------------
; initialize the acorn keyboard
; if the initialization fails in 20ms, try again
;----------------------------------------------------------
a5000_init:
	clr	A5kKbdId
	clr	es		; disable serial interrupt
	call	timer0_20ms_init

	; -- step 1: HRST
	clr	ti
	mov	sbuf,#ACmdHRST
a5000_initWaitTIHRST:
	jnb	ti,a5000_initWaitTIHRST

a5000_initWaitRIHRST:
	jnb	MiscSleepT0F,a5000_init
	jnb	ri,a5000_initWaitRIHRST
	mov	a,sbuf
	clr	ri
	cjne	a,#ACmdHRST,a5000_init

	; -- step 2: RAK1
	clr	ti
	mov	sbuf,#ACmdRAK1
a5000_initWaitTIRAK1:
	jnb	ti,a5000_initWaitTIRAK1

a5000_initWaitRIRAK1:
	jnb	MiscSleepT0F,a5000_init
	jnb	ri,a5000_initWaitRIRAK1
	mov	a,sbuf
	clr	ri
	cjne	a,#ACmdRAK1,a5000_init

	; -- step 3: RAK2
	clr	ti
	mov	sbuf,#ACmdRAK2
a5000_initWaitTIRAK2:
	jnb	ti,a5000_initWaitTIRAK2

a5000_initWaitRIRAK2:
	jnb	MiscSleepT0F,a5000_init
	jnb	ri,a5000_initWaitRIRAK2
	mov	a,sbuf
	clr	ri
	cjne	a,#ACmdRAK2,a5000_init

	; -- step 3: NACK, RQID
	clr	ti
	mov	sbuf,#ACmdNACK
a5000_initWaitTINACK:
	jnb	ti,a5000_initWaitTINACK

	mov	r3,#16
a5000_initDelay:
	call	nop20
	djnz	r3,a5000_initDelay

	clr	ti
	mov	sbuf,#ACmdRQID
a5000_initWaitTIRQID:
	jnb	ti,a5000_initWaitTIRQID

a5000_initWaitRIRQID:
	jnb	MiscSleepT0F,a5000_init
	jnb	ri,a5000_initWaitRIRQID
	mov	a,sbuf
	clr	ri
	cjne	a,#ACmdHRST,a5000_initRQIDok
	sjmp	a5000_init
a5000_initRQIDok:
	mov	A5kKbdId,a

	; -- step 4: send SMAK
	clr	ti
	mov	sbuf,#ACmdSMAK
a5000_initWaitTISMAK:
	jnb	ti,a5000_initWaitTISMAK

	clr	tr0
	clr	A5kResetF

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
; init uart with timer 1 as baudrate generator
; Acorn A5000 31.25 kbps
;----------------------------------------------------------
uart_timer1_init:
	mov	scon, #050h	; uart mode 1 (8 bit), single processor
	orl	tmod, #020h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 2, 8bit-auto-reload
	orl	pcon, #080h	; SMOD, bit 7 in PCON
	mov	th1, #uart_t1_31k25_24M
	mov	tl1, #uart_t1_31k25_24M
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
RCSId	DB	"$Id: kbdbabel_a5000_ps2_8051.asm,v 1.1 2007/11/11 00:01:45 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom

	; -- init UART and timer0/1
	acall	uart_timer1_init

	; -- enable interrupts int0
	setb	ea

	; -- enable interrupts int0
	setb	ex0		; external interupt 0 enable
	setb	it0		; falling edge trigger for int 0

	; -- clear all flags
	mov	B20,#0
	mov	B21,#0
	mov	B22,#0
	mov	B23,#0
	mov	A5kKbdLeds,#0

	; -- init the ring buffer
	mov	RingBufPtrIn,#0
	mov	RingBufPtrOut,#0

	; -- cold start flag
	setb	ATCmdResetF

	acall	a5000_init

;	; -- enable serial interrupt
;	setb	es

; ----------------
Loop:
	; -- check if reset key was pressed
	jb	A5kResetF,Start

	; -- check input receive status
	jb	RI,LoopProcessA5kData

	; -- check on new AT data received
	jb	ATCmdReceivedF,LoopProcessATcmd

	; -- check if AT communication active.
	jb	TFModF,Loop

	; -- check AT line status, clock line must not be busy
	jnb	p3.3,Loop

	; -- check for AT RX data
	jnb	p3.5,LoopATRX

	; -- send data, if data is present
	call	ATTX

	; -- check if commands may be sent to the Keyboard
	jb	A5kKbdSetLedF,LoopSetA5kLED

	sjmp	Loop

;----------------------------------------------------------
; helpers for the main loop
;----------------------------------------------------------
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
;	clr	ATHostToDevIntF
	setb	ATHostToDevF
	call	timer0_init

	; wait for completion
LoopTXWaitSent:
	jb	TFModF,LoopTXWaitSent
LoopCheckATEnd:
	ljmp	Loop

; ----------------
LoopSetA5kLED:
; -- set keyboard LEDs
	; sending multiple bytes of LED control code takes too long e.g. on sun-keyboards.
	; about 2ms due to 2 bytes @ 1200bps.
	; some PS2-to-USB-adaptors do not tolerate this delay in AT communication.

	; -- return if serial transmission is active
	jnb	ti,LoopSetA5kLEDEnd

	; -- send LED data
	clr	ti
	mov	a,A5kKbdLeds
	mov	sbuf,a
	clr	A5kKbdSetLedF

LoopSetA5kLEDEnd:
	setb	p1.4
	ljmp	Loop

; ---------------- @@@@@@@@@@@@ FIXME
LoopProcessA5kData:
# --- idle
	mov	A5kRxBuf,#0
	mov	a,sbuf
	clr	ri
	anl	a,#0fh
	swap	a
	mov	A5kRxBuf,a

	clr	ti
	mov	sbuf,#ACmdBACK
a5000_initWaitTITestLoop1:
	jnb	ti,a5000_initWaitTITestLoop1

# --- key
a5000_initWaitTestLoop2:
	jnb	ri,a5000_initWaitTestLoop2
	mov	a,sbuf
	mov	c,acc.4
	mov	A5kRxBreakF,c
	clr	ri
	anl	a,#0fh
	orl	a,A5kRxBuf
	mov	A5kRxBuf,a
;	mov	p1,a

	clr	ti
	mov	sbuf,#ACmdSMAK
a5000_initWaitTITestLoop2:
	jnb	ti,a5000_initWaitTITestLoop2

	mov	a,A5kRxBuf
	mov	RawBuf,a	
	setb	MiscRXCompleteF
	call	TranslateToBufA5k

	sjmp Loop

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
