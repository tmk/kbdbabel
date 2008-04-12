; ---------------------------------------------------------------------
; IBM-3104B Terminal 87 key Keyboard with DA-15-f-plug
; to AT/PS2 keyboard transcoder for 8051 type processors.
; Build using a german IBM 6124530 Keyboard.
;
; $Id: kbdbabel_ibm3104_ps2_8051.asm,v 1.1 2008/04/12 09:18:44 akurz Exp $
;
; Clock/Crystal: 24MHz.
;
; IBM Terminal Keyboard DA-15-connect:
; This two pins may need externals 4.7k resistors as pullup.
; pin 1,15	- PE
; pin 2		- Vcc +5V
; pin 3		- p3.1 "PowerOn Reset"
; pin 4		- p1.1 "Data Available"	(Pin 2 on DIL40, Pin 13 on AT89C2051 PDIP20)
; pin 5		- p3.4 "Data"
; pin 6		- Vcc +12V
; pin 7,8,14	- GND
; pin 9		- p3.2 "Clock"
; pin 10	- p1.3 "Ack"		(Pin 4 on DIL40, Pin 15 on AT89C2051 PDIP20)
; pin 11	- p1.2 "Command Strobe"	(Pin 3 on DIL40, Pin 14 on AT89C2051 PDIP20)
; pin 12	- p1.0 "Command 0"	(Pin 1 on DIL40, Pin 12 on AT89C2051 PDIP20)
; pin 13	- p3.7 "Command 1"
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
; Error		- p1.4	(Pin 5 on DIL40, Pin 16 on AT89C2051 PDIP20)
;
; Build using the macroassembler by Alfred Arnold
; $ asl -L kbdbabel_ibm3104_ps2_8051.asm -o kbdbabel_ibm3104_ps2_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_ibm3104_ps2_8051
; write kbdbabel_ibm3104_ps2_8051.bin on an empty 27C256 or AT89C2051
;
; Copyright 2008 by Alexander Kurz
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
RawBuf		equ	30h	; raw PC/XT scancode
OutputBuf	equ	31h	; AT scancode
TXBuf		equ	32h	; AT scancode TX buffer
RingBufPtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	35h	; AT host-to-dev buffer
ATRXCount	equ	36h
ATRXResendBuf	equ	37h	; for AT resend feature

;------------------ bits
KbdRXBitF	bit	B20.0	; RX-bit-buffer
KbdRXCompleteF	bit	B20.1	; full and correct byte-received
KbdRXActiveF	bit	B20.2	; receive in progress flag
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
IBMTermModKF	bit	B22.1	; IBM Terminal key is Modifier key (sending break on release)
IBMTermInitF	bit	B22.2	; Init the keyboard
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
; int 0, connected to keyboard clock line.
; With a falling signal on the clock line there are 13mus
; left to read the data line. Using a 3.6864 MHz Crystal
; this will be less than 5 processor cycles.
;----------------------------
	org	03h	; external interrupt 0
	jnb	P3.4, HandleInt0	; this is time critical
	setb	KbdRXBitF
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

	; receive in progress flag
	setb	KbdRXActiveF
; --------------------------- diag: check if RX happens during AT-TX
	; check if flag is set
	jnb	ATTXActiveF,interCharFlagOk
;	clr	p1.3
	sjmp	interCharTestEnd
interCharFlagOk:
;	setb	p1.3
interCharTestEnd:
; --------------------------- get and save data samples
; -- write to mem, first 8 bits
	mov	c,KbdRXBitF	; new bit
	mov	a,KbBitBuf
	rrc	a
	mov	KbBitBuf,a

; -- diag: write data bits to LED-Port
;	mov	a,KbBitBuf
;	xrl	a,0FFh
;	mov	p1,a

; -- reset bit buffer
	clr	KbdRXBitF

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
;	setb	p1.6		; error LED off
;	; -- diag
;	clr	p1.7
;	nop
;	setb	p1.7

	mov	a,KbBitBuf
	mov	RawBuf,a
	mov	r7,#0
	setb	KbdRXCompleteF	; fully received flag
	clr	KbdRXActiveF	; receive in progress flag
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
;	setb	p1.4c			; diag: data send
	; end of TX sequence, not time critical
	sjmp	timerTXStop

timerTXCheckBusy:
; -- check if clock is released, but not after the stop bit.
; -- Host may pull down clock to abort communication at any time.
	jb	p3.3,timerTXEnd

timerTXClockBusy:
; -- clock is busy, abort communication
	setb	ATCommAbort		; AT communication aborted flag
;	clr	p1.4c			; diag: data not send
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
;	setb	p1.4b			; diag: host-do-dev ok
	sjmp	timerRXEnd

timerRXCheckBusy:
; -- check if clock is released, but not after the last bit.
; -- Host may pull down clock to abort communication at any time.
	jb	p3.3,timerRXEnd

timerRXClockBusy:
; -- clock is busy, abort communication
	setb	ATCommAbort		; AT communication aborted flag
;	clr	p1.4b			; diag: host-do-dev abort

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
; IBM 3104 Terminal to AT translaton table
;
; mapping notes:
; CapsLock->Ctrl, Alt->AltGr
; Grdst->Esc, TabR->Del
; Dup->Home, ^a->End, FeldMarke->PgUp, Xa->PgDn, DatFreig->NumLock
;----------------------------------------------------------
IBM31042toATxlt0	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,   5ah,  61h,   0h,   0h,  69h,  7ah,  75h,  5dh
IBM31042toATxlt1	DB	 29h,  55h,  52h,  72h,  4ah,  5bh,  6bh,   0h,   77h,   0h,  74h,  54h,   0h,   0h,   0h,   0h
IBM31042toATxlt2	DB	 45h,  16h,  1eh,  26h,  25h,  2eh,  36h,  3dh,   3eh,  46h,   0h,   0h,   0h,   0h,   0h,   0h
IBM31042toATxlt3	DB	 4eh,  66h,  49h,  41h,  76h,  71h,  0dh,   0h,    0h,   0h,   0h,   0h,   0h,  0eh,   0h,   0h
IBM31042toATxlt4	DB	 6ch,  75h,  7dh,  6bh,  73h,  74h,  69h,  72h,   7ah,  5ah,  70h,  71h,  14h,  12h,  59h,  11h
IBM31042toATxlt5	DB	 05h,  06h,  04h,  0ch,  03h,  0bh,  83h,  0ah,    0h,   0h,   0h,   0h,   0h,   0h,  7dh,  6ch
IBM31042toATxlt6	DB	 1ch,  32h,  21h,  23h,  24h,  2bh,  34h,  33h,   43h,  3bh,  42h,  4bh,  3ah,  31h,  44h,  4dh
IBM31042toATxlt7	DB	 15h,  2dh,  1bh,  2ch,  3ch,  2ah,  1dh,  22h,   35h,  1ah,   0h,   0h,   0h,   0h,  4ch,   0h

;----------------------------------------------------------
; IBM 3104 Terminal to AT translaton table
; Bit-Table for multi-byte-AT-Scancodes
;
; bit 0: E0-Escape
; bit 1: send Make E0,12,E0,7C / BreakE0,F0,7C,E0,F0,12 (PrtScr)
; bit 2: send Make E1,14,77,E1,F0,14,F0,77 (Pause)
; bit 4: modifier key: keyboard will send make and break
;----------------------------------------------------------
IBM31042toATxlte0	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,  01h,  01h,  01h,   0h
IBM31042toATxlte1	DB	  0h,   0h,   0h,  01h,   0h,   0h,  01h,   0h,    0h,   0h,  01h,   0h,   0h,   0h,   0h,   0h
IBM31042toATxlte2	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
IBM31042toATxlte3	DB	  0h,   0h,   0h,   0h,   0h,  01h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
IBM31042toATxlte4	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,  01h,   0h,   0h,  10h,  10h,  10h,  11h
IBM31042toATxlte5	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,  01h,  01h
IBM31042toATxlte6	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h
IBM31042toATxlte7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h,    0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

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
	clr	p1.4
	ret

;----------------------------------------------------------
; Get received data and translate it into the ring buffer
;----------------------------------------------------------
TranslateToBufIBMTerm:
	; translate from IBM Terminal to AT scancode
	mov	a,RawBuf
	clr	KbdRXCompleteF
	cpl	a	; 0V->1, 5V->0

;	; -- diag write to LED
;	mov	c,acc.0
;	mov	p1.7,c

	; check bit 7
	jnb	acc.7,TranslateToBufNotB7
	setb	ATTXBreakF
TranslateToBufNotB7:

	; clear bit 7
	anl	a,#07fh

	; save raw scancode and clear received data flag
	mov	r3,a

	; keyboard disabled?
	jb	ATKbdDisableF,TranslateToBufEnd

	; check for 2-byte scancodes
	mov	dptr,#IBM31042toATxlte0
	movc	a,@a+dptr
	jb	acc.1,TranslateToBufPrtScr
	jb	acc.2,TranslateToBufPause
	mov	c,acc.0
	mov	ATTXMasqF,c
	mov	c,acc.4
	mov	IBMTermModKF,c
	sjmp	TranslateToBufNormal

TranslateToBufPrtScr:
	; AT-Scancode for Print Screen
	call	ATPrtScrMake
	call	ATPrtScrBrk
	sjmp	TranslateToBufEnd

TranslateToBufPause:
	; AT-Scancode for Pause, only Make-Code is sent
	jb	ATTXBreakF,TranslateToBufEnd
	call	ATPause
	sjmp	TranslateToBufEnd

TranslateToBufNormal:
	; get AT scancode
	mov	a,r3
	mov	dptr,#IBM31042toATxlt0
	movc	a,@a+dptr
	mov	OutputBuf,a

	; dont send zero scancodes
	mov	a, OutputBuf
	jz	TranslateToBufIgnoreZero

	; check for modifier keys
	jb	IBMTermModKF,IBMTermModKey

	; --- non-modifier key sends make only: emulate make and break
	clr	ATTXBreakF
	; check for 0xE0 escape code
	jnb	ATTXMasqF,TranslateToBufNoEscMake
	mov	r2,#0E0h
	call	RingBufCheckInsert
TranslateToBufNoEscMake:

	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert

	; check for 0xE0 escape code
	jnb	ATTXMasqF,TranslateToBufNoEscBreak
	mov	r2,#0E0h
	call	RingBufCheckInsert
TranslateToBufNoEscBreak:

	; break
	mov	r2,#0F0h
	call	RingBufCheckInsert

	; normal data byte
	mov	r2, OutputBuf
	call	RingBufCheckInsert

	sjmp	TranslateToBufEnd


	; --- modifier key sending make and break
IBMTermModKey:
	; check for 0xE0 escape code
	jnb	ATTXMasqF,TranslateToBufNoEsc
	mov	r2,#0E0h
	call	RingBufCheckInsert
TranslateToBufNoEsc:

	; check for 0xF0 release / break code
	jnb	ATTXBreakF,TranslateToBufNoRelease
	clr	ATTXBreakF
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

	; abort if new PC receive is in progress
	jb	KbdRXActiveF,BufTXEnd	; new receive in progress

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
; helper, send AT/PS2 PrtScr Make
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
; helper
;----------------------------------------------------------
IBM3104SendInit:
	setb	p1.2
	setb	p1.0	; cmd0
	setb	p3.7	; cmd1

	clr	p1.2
	nop
	nop
	nop
	setb	p1.2

	ret

;----------------------------------------------------------
; init timer 1 for PC/XT interval timing
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
timer0_130u_init:
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
RCSId	DB	"$KbdBabel: kbdbabel_ibm3104_ps2_8051.asm,v 1.1 2008/04/11 10:40:59 akurz Exp $"

;----------------------------------------------------------
; main
;----------------------------------------------------------
Start:
	; -- init the stack
	mov	sp,#StackBottom

	; -- enable interrupts
	setb	ea

	; -- reset the IBM3104-keyboard
	clr	p3.1
	clr	p1.4

	; -- some delay of 500ms to eleminate stray data sent by the PC/XT-Keyboard on power-up
	mov	r0,#25
InitResetDelayLoop:
	call	timer0_20ms_init
InitResetDelay:
	clr	p3.1
	jb	MiscSleepT0F,InitResetDelay
	djnz	r0,InitResetDelayLoop

	; -- init UART and timer0/1
;	acall	uart_timer2_init
	acall	timer1_init
	acall	timer0_130u_init

	; @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ vvv test
	clr	ex1	; external interupt 1 disabled

	; -- reset the IBM3104-keyboard
	setb	p3.1
	setb	p1.4
	acall	nop20
	acall	IBM3104SendInit

	; -- some delay
	call	timer0_20ms_init
InitIBM3104Delay:
	jb	p1.1,InitIBM3104DelayNoAck
	; -- diag
	clr	p1.4

	clr	p1.3
	call	nop20
	setb	p1.3

	; -- diag
	setb	p1.4

;	setb	p1.1
InitIBM3104DelayNoAck:
	jb	MiscSleepT0F,InitIBM3104Delay
	; @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ ^^^ test

	; -- enable interrupts int0
	setb	ex0	; external interupt 0 enable
	setb	it0	; falling edge trigger for int 0
	setb	ex1	; external interupt 1 enable
	setb	it1	; falling edge trigger for int 1

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
;	setb	IBMTermInitF

; ----------------
Loop:
	; -- diag
;	clr	p1.5
;	nop
;	setb	p1.5

; --	send ACK
	jb	p1.1,LoopNoAck
	clr	p1.3
	call	nop20
	setb	p1.3
LoopNoAck:

	; -- check PC/XT receive status
	jb	KbdRXCompleteF,LoopProcessPCXTData

	; -- check on new AT data received
	jb	ATCmdReceivedF,LoopProcessATcmd

	; -- check if AT communication active.
	jb	TFModF,Loop

	; -- check AT line status, clock line must not be busy
	jnb	p3.3,Loop

	; -- check for AT RX data
	jnb	p3.5,LoopATRX

	; -- stay in idle mode when PC RX is active
	jb	KbdRXActiveF,Loop

	; -- send data, if data is present
	call	ATTX

;	; -- check if AT communication active.
;	jb	TFModF,Loop

;	; -- may do other things while idle here ...

	sjmp	Loop

;----------------------------------------------------------
; helpers for the main loop
;----------------------------------------------------------
; ----------------
LoopProcessPCXTData:
; -- Keyboard data received, process the received scancode into output ring buffer
	call	TranslateToBufIBMTerm
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
;	setb	p1.4b

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

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	"   Copyright 2008 by Alexander Kurz"
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
