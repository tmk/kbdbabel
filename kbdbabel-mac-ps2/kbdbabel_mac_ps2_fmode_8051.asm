; ---------------------------------------------------------------------
; Macintosh 128k/512k/Plus to AT/PS2 keyboard transcoder
; with F-Mode feature for full PS2-Emulation
; for 8051 type processors.
;
; $Id: kbdbabel_mac_ps2_fmode_8051.asm,v 1.1 2009/08/17 09:18:02 akurz Exp $
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
; ScrollLock	- p1.7	(Pin 8 on DIL40, Pin 19 on AT89C2051 PDIP20)
; CapsLock	- p1.6	(Pin 7 on DIL40, Pin 18 on AT89C2051 PDIP20)
; NumLock	- p1.5	(Pin 6 on DIL40, Pin 17 on AT89C2051 PDIP20)
; F-Mode	- p1.4	(Pin 4 on DIL40, Pin 16 on AT89C2051 PDIP20)
; Mac Ext Interrupt active		- p1.3
; AT TX Communication abort	- p1.2
; AT RX Communication abort	- p1.1
; Mac communication watchdog	- p1.0
;
; Build using the macroassembler by Alfred Arnold
; $ asl -L kbdbabel_mac_ps2_fmode_8051.asm -o kbdbabel_mac_ps2_fmode_8051.p
; $ p2bin -l \$ff -r 0-\$7ff kbdbabel_mac_ps2_fmode_8051
; write kbdbabel_mac_ps2_fmode_8051.bin on an empty 27C256 or AT89C2051
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
	include	kbdbabel_intervals.inc

;----------------------------------------------------------
; Variables / Memory layout
;----------------------------------------------------------
;------------------ octets
B20		sfrb	20h	; bit adressable space
B21		sfrb	21h
B22		sfrb	22h
B23		sfrb	23h
;		equ	24h
;		equ	25h
MacBitBuf	equ	26h	; bi-directional Mac communication bit buffer
MacResetTTL	equ	27h	; long pause
ATBitCount	sfrb	28h	; AT scancode TX counter
RawBuf		equ	30h	; raw Mac scancode
OutputBuf	equ	31h	; AT scancode
TXBuf		equ	32h	; AT scancode TX buffer
RingBufPtrIn	equ	33h	; Ring Buffer write pointer, starting with zero
RingBufPtrOut	equ	34h	; Ring Buffer read pointer, starting with zero
ATRXBuf		equ	35h	; AT host-to-dev buffer
ATRXCount	equ	36h
ATRXResendBuf	equ	37h	; for AT resend feature

;------------------ bits
ATTXMasqF	bit	B20.2	; TX-AT-Masq-Char-Bit (send two byte scancode)
ATKbdDisableF	bit	B20.3	; Keyboard disable
ATTXBreakF	bit	B20.4	; Release/Break-Code flag
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
MacRXCompleteF	bit	B22.0	; full and correct byte-received
MiscSleepT1F	bit	B22.1	; sleep timer active flag, timer 1
MacTFModF	bit	B22.2	; Mac timer modifier, similar to MacClkPostF
MacClkPostF	bit	B22.3	; post-datagram sleep flag, similar to MacTFModF
MacClkRXCompleteF	bit	B22.4	; Host-Clock-Driven read finished
MacClkTXCompleteF	bit	B22.5	; Device-Clock-Driven write finished
MacTxF		bit	B22.6	; external interrupt RX/TX modifier / TX-Flag
MacMod2F	bit	B22.7	; 9e scancode received.
MacMod3F	bit	B23.0	; 8e9e scancode received.
MacStoredBreakF	bit	B23.1	; stored break bit for shift-scancode, *aaargh*
XltFF		bit	B23.2	; Switch for Keyboard F-Mode
XltFOverrideF	bit	B23.3	; Override Keyboard F-Mode for Linux Magic SysRQ-Keys

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
; write data bits to the keyboard
; Get Bits by rotation from MacBitBuf.
; Num Bits is in r7
;----------------------------------------------------------
HandleInt0:
	push	acc
	push	psw
	clr	p1.3

	jb	MacTxF,HandleInt0TX

; --------------------------- get and save data samples
	mov	a,MacBitBuf
	rr	a
	mov	c,p3.4		; read a data bit
	mov	acc.7,c
	mov	MacBitBuf,a

; -- dec the bit counter
	djnz	r7,Int0Return
	mov	r7,#8
	mov	a,MacBitBuf
	mov	RawBuf,a
	setb	MacRXCompleteF
	setb	MacClkRXCompleteF
	sjmp	Int0Return
; --------------------------- write data to the keyboard
HandleInt0TX:
; -- write to keyboard
	mov	a,MacBitBuf
	mov	c,acc.0
	mov	p3.4,c		; write a data bit
	rr	a
	mov	MacBitBuf,a

; -- dec the bit counter
	djnz	r7,Int0Return
	setb	MacClkTXCompleteF
	mov	r7,#8

; --------------------------- done
Int0Return:
	setb	p1.3
	pop	psw
	pop	acc
	reti

;----------------------------------------------------------
; timer 1 int handler:
;----------------------------------------------------------
HandleTF1:
	push	acc
	push	psw

	jb	MacTFModF,timer1AsTTLClock
; --------------------------- timer is used as 300mus 16-bit alarm clock
	; stop timer
	clr	tr1
	clr	MiscSleepT1F
	sjmp	timer1Return

; --------------------------- timer is used as 15*20ms 16-bit alarm clock
timer1AsTTLClock:
	clr	tr1
	clr	MiscSleepT1F
	dec	MacResetTTL

; --------------------------- done
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
;
; TFModF=1:
; timer is used in 8-bit-auto-reload-mode to generate
; the AT scancode clock timings.
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
; Notes for the keyboard-layout:
;
; In normal mode all keys 1:1 except
;  key left of "1" -> Escape
;  CapsLock-Switch -> F-Mode-Switch
;
; In F-Mode
;  1-0-keys and the two keys right of them -> F1-F12
;  ADM3a-Arrows: HJKL -> Left,Down,Up,Right
;  U -> PageUp
;  N -> PageDown
;  A -> Home
;  E -> End
;  D -> Del
;  I -> Ins
;  X -> NumLock
;  C -> CapsLock
;  V -> ScrollLock
;  Z/Y -> SysRq/PrintScreen
;  P -> Pause
;  Ä/" -> #/
;  </\ -> ^/~
;----------------------------------------------------------

;----------------------------------------------------------
; Mac to AT translaton table
; using significant bits 1-6 only: anl a,#7e; rr a;
; special handling for 9e and 8e 9e
;----------------------------------------------------------
Mac2ATxlt0	DB	 1ch,  3ch,  35h,  0dh,  21h,  42h,  55h,   0h	; 80
Mac2ATxlt1	DB	 33h,  5ah,  26h,  11h,  15h,  4ah,  3eh,   0h	; 90
Mac2ATxlt2	DB	 23h,  43h,  16h,  76h,   0h,  61h,  3dh,  14h	; a0
Mac2ATxlt3	DB	 1ah,  3bh,  36h,   0h,  24h,  3ah,  5bh,   0h	; b0
Mac2ATxlt4	DB	 1bh,  54h,  2ch,  29h,  2ah,  4ch,  46h,  58h	; c0
Mac2ATxlt5	DB	 34h,  4bh,  25h,   0h,  1dh,  31h,  45h,   0h	; d0
Mac2ATxlt6	DB	 2bh,  4dh,  1eh,  66h,  32h,  41h,  4eh,   0h	; e0
Mac2ATxlt7	DB	 22h,  52h,  2eh,  11h,  2dh,  49h,  44h,   0h	; f0

;----------------------------------------------------------
; Mac to AT translaton table, F-Mode
; using significant bits 1-6 only: anl a,#7e; rr a;
; special handling for 9e and 8e 9e
;----------------------------------------------------------
Mac2ATxltF0	DB	 6ch,  7dh,   0h,  0dh,  58h,  75h,  07h,   0h
Mac2ATxltF1	DB	 6bh,  5ah,  04h,  11h,   0h,   0h,  0ah,   0h
Mac2ATxltF2	DB	 71h,  70h,  05h,  76h,   0h,  0eh,  83h,  14h
Mac2ATxltF3	DB	  0h,  72h,  0bh,   0h,  69h,   0h,   0h,   0h
Mac2ATxltF4	DB	  0h,   0h,   0h,  29h,  7eh,   0h,  01h,   0h
Mac2ATxltF5	DB	  0h,  74h,  0ch,   0h,   0h,  7ah,  09h,   0h
Mac2ATxltF6	DB	  0h,   0h,  06h,  66h,   0h,   0h,  78h,   0h
Mac2ATxltF7	DB	 77h,  5dh,  03h,  11h,   0h,   0h,   0h,   0h

;----------------------------------------------------------
; Mac to AT translaton table
; Bit-Table for multi-byte-AT-Scancodes
;
; bit 0: E0-Escape
; bit 1: send Make E0,12,E0,7C / BreakE0,F0,7C,E0,F0,12 (PrtScr)
; bit 2: send Make E1,14,77,E1,F0,14,F0,77 (Pause)
; bit 3: F-Mode-Switch
; bit 4-6: same as bit 0-2 but for F-Mode
; bit 7: override F-Mode-Switch (for Linux Magic-SysRQ-Keys)
;----------------------------------------------------------
Mac2ATxlte0	DB	 10h,  10h, 0a0h,   0h,   0h,  10h,   0h,   0h
Mac2ATxlte1	DB	 10h,   0h,   0h,  11h,   0h,   0h,   0h,   0h
Mac2ATxlte2	DB	 10h,  10h,   0h,   0h,   0h,   0h,   0h,   0h
Mac2ATxlte3	DB	  0h,  10h,   0h,   0h,  10h,   0h,   0h,   0h
Mac2ATxlte4	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,  08h
Mac2ATxlte5	DB	  0h,  10h,   0h,   0h,   0h,  10h,   0h,   0h
Mac2ATxlte6	DB	  0h,  40h,   0h,   0h,   0h,   0h,   0h,   0h
Mac2ATxlte7	DB	  0h,   0h,   0h,   0h,   0h,   0h,   0h,   0h

;----------------------------------------------------------
; Mac to AT translaton table for two-bit scancodes
; using significant bits 2-6 only: anl a,#7c; rr a; rr a;
; special handling for 9e
;----------------------------------------------------------
Mac2ATxltB20	DB	  0h,   0h,  72h,  74h	; 80
Mac2ATxltB21	DB	  0h,  72h,  5ah,  7dh	; 90
Mac2ATxltB22	DB	 74h,  70h,   0h,   0h	; a0
Mac2ATxltB23	DB	 6bh,  6bh,  7bh,   0h	; b0
Mac2ATxltB24	DB	 71h,   0h,   0h,  6ch	; c0
Mac2ATxltB25	DB	  0h,  7ah,  75h,   0h	; d0
Mac2ATxltB26	DB	  0h,  69h,   0h,  75h	; e0
Mac2ATxltB27	DB	 76h,  73h,   0h,   0h	; f0

;----------------------------------------------------------
; Mac to AT translaton table
; Bit-Table for multi-byte-AT-Scancodes
;----------------------------------------------------------
Mac2ATxltB2e0	DB	  0h,   0h,  01h,   0h
Mac2ATxltB2e1	DB	  0h,   0h,  01h,   0h
Mac2ATxltB2e2	DB	 01h,   0h,   0h,   0h
Mac2ATxltB2e3	DB	 01h,   0h,   0h,   0h
Mac2ATxltB2e4	DB	  0h,   0h,   0h,   0h
Mac2ATxltB2e5	DB	  0h,   0h,  01h,   0h
Mac2ATxltB2e6	DB	  0h,   0h,   0h,   0h
Mac2ATxltB2e7	DB	  0h,   0h,   0h,   0h

;----------------------------------------------------------
; Mac to AT translaton table for three-bit scancodes
; using significant bits 3-6 only: anl a,#78; rr a; rr a; rr a;
;----------------------------------------------------------
Mac2ATxltB30	DB	  0h,  77h	; 80
Mac2ATxltB31	DB	  0h,   0h	; 90
Mac2ATxltB32	DB	 7ch,   0h	; a0
Mac2ATxltB33	DB	 79h,   0h	; b0
Mac2ATxltB34	DB	  0h,   0h	; c0
Mac2ATxltB35	DB	  0h,  4ah	; d0
Mac2ATxltB36	DB	  0h,   0h	; e0
Mac2ATxltB37	DB	  0h,   0h	; f0

;----------------------------------------------------------
; Mac to AT translaton table
; Bit-Table for multi-byte-AT-Scancodes
;----------------------------------------------------------
Mac2ATxltB3e0	DB	  0h,   0h
Mac2ATxltB3e1	DB	  0h,   0h
Mac2ATxltB3e2	DB	  0h,   0h
Mac2ATxltB3e3	DB	  0h,   0h
Mac2ATxltB3e4	DB	  0h,   0h
Mac2ATxltB3e5	DB	  0h,  01h
Mac2ATxltB3e6	DB	  0h,   0h
Mac2ATxltB3e7	DB	  0h,   0h

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
;----------------------------------------------------------
TranslateToBuf:
	; translate from Mac to AT scancode
	; buffer scancode and clear received data flag
	mov	a,RawBuf
	mov	r3,a
	clr	MacRXCompleteF

	; save make/break bit 0
	mov	c,acc.0
	mov	ATTXBreakF,c

	; ignore make/break bit 0
	anl	a,#0feh

	; -- check bit 7, must be 1
	jb	acc.7,TranslateToBufBit7ok
	ljmp	TranslateToBufEnd

TranslateToBufBit7ok:

	; -- check 9e escape scancode
	cjne	a,#09eh,TranslateToBufNot9e
	setb	MacMod2F
	ljmp	TranslateToBufEnd
TranslateToBufNot9e:

	; -- bad hack for the Mac-<Shift>-Key
	; note: the 8e-scancode is used as escape-code as well.
	; AAAARRGH!
	jnb	MacMod3F,TranslateToBufNoStored8e
	jb	MacMod2F,TranslateToBufNoStored8e
	clr	MacMod3F
	mov	c,MacStoredBreakF
	jnc	TranslateToShiftNoBreak
	mov	r2, #0F0h
	call	RingBufCheckInsert
TranslateToShiftNoBreak:
	mov	r2, #12h
	call	RingBufCheckInsert

	; translate from Mac to AT scancode
	mov	a,r3
	anl	a,#0feh
TranslateToBufNoStored8e:

	; -- check 8e escape scancode
	cjne	a,#08eh,TranslateToBufNot8e
	setb	MacMod3F
	; note: the 8e-scancode is used for shift as well. Store make/break-bit here. *aaargh*
	mov	c,ATTXBreakF
	mov	MacStoredBreakF,c
	ljmp	TranslateToBufEnd
TranslateToBufNot8e:

	; -- check idle scancode
	cjne	a,#0deh,TranslateToBufNotde
	clr	MacMod2F
	clr	MacMod3F
	ljmp	TranslateToBufEnd
TranslateToBufNotde:

	jnb	MacMod3F,TranslateToBufJumperNotE3
	ljmp	TranslateToBufE3
TranslateToBufJumperNotE3:
	jb	MacMod2F,TranslateToBufE2


	; --- single Mac scancode
	; ignore obsolete bit 7
	anl	a,#7fh
	rr	a
	mov	r4,a

	; check for PrtScr, Pause and 2-byte AT-scancodes
	mov	dptr,#Mac2ATxlte0
	movc	a,@a+dptr
	jb	acc.3,TranslateToBufFMod
	mov	dptr,#Mac2ATxlt0

	; -- check F-Mode
	jnb	XltFF,TranslateToBufNotF

	; -- check F-Mode override
	jnb	acc.7,TranslateToBufNotFModeOverrideKey
	mov	c,ATTXBreakF
	cpl	c
	mov	XltFOverrideF,c
	mov	dptr,#Mac2ATxltF0
	sjmp	TranslateToBufNotFModeOverride

TranslateToBufNotFModeOverrideKey:
	mov	dptr,#Mac2ATxltF0

	; -- override F-Mode for Linux Magic SysRQ-Keys
	jnb	XltFOverrideF,TranslateToBufNotFModeOverride
	mov	dptr,#Mac2ATxlt0
	swap	a
TranslateToBufNotFModeOverride:

	swap	a
TranslateToBufNotF
	jb	acc.1,TranslateToBufPrtScr
	jb	acc.2,TranslateToBufPause
	mov	c,acc.0
	mov	ATTXMasqF,c

	; get AT scancode
	mov	a,r4
;	mov	dptr,#Mac2ATxlt0
	movc	a,@a+dptr
	mov	OutputBuf,a
	sjmp	TranslateToBufGo


	; ------ helpers for PrtScr and Pause
TranslateToBufPrtScr:
	; AT-Scancode for Print Screen
	jnb	ATTXBreakF,TranslateToBufPrtScrMake
	call	ATPrtScrBrk
	sjmp	TranslateToBufEnd
TranslateToBufPrtScrMake:
	call	ATPrtScrMake
	sjmp	TranslateToBufEnd

TranslateToBufPause:
	; AT-Scancode for Pause, only Make-Code is sent
	jb	ATTXBreakF,TranslateToBufEnd
	call	ATPause
	sjmp	TranslateToBufEnd

TranslateToBufFMod:
	; Dummy-Translation: switch F-Mode
	jnb	ATTXBreakF,TranslateToBufFModEnd
	clr	XltFF
	setb	p1.4
	clr	XltFOverrideF
	sjmp	TranslateToBufEnd
TranslateToBufFModEnd:
	setb	XltFF
	clr	p1.4
	sjmp	TranslateToBufEnd


TranslateToBufE2:
	; --- double Mac scancode
	clr	MacMod2F
	; ignore obsolete bit 6,7
	anl	a,#7ch
	rr	a
	rr	a
	mov	r4,a

	; check for PrtScr, Pause and 2-byte AT-scancodes
	mov	dptr,#Mac2ATxltB2e0
	movc	a,@a+dptr
	jb	acc.3,TranslateToBufFMod
;	jnb	XltFF,TranslateToBufNotFE2
;	swap	a
;TranslateToBufNotFE2
	jb	acc.1,TranslateToBufPrtScr
	jb	acc.2,TranslateToBufPause
	mov	c,acc.0
	mov	ATTXMasqF,c

	; get AT scancode
	mov	a,r4
	mov	dptr,#Mac2ATxltB20
	movc	a,@a+dptr
	mov	OutputBuf,a
	sjmp	TranslateToBufGo

TranslateToBufE3:
	; --- triple Mac scancode
	clr	MacMod3F
	; check for 9e-Flag. If not set, ignore.
	jb	MacMod2F,TranslateToBufE3andE2
	sjmp	TranslateToBufEnd
TranslateToBufE3andE2:
	clr	MacMod2F

	; ignore obsolete bit 5,6,7
	anl	a,#78h
	rr	a
	rr	a
	rr	a
	mov	r4,a

	; check for PrtScr, Pause and 2-byte AT-scancodes
	mov	dptr,#Mac2ATxltB3e0
	movc	a,@a+dptr
	jb	acc.3,TranslateToBufFMod
;	jnb	XltFF,TranslateToBufNotFE3
;	swap	a
;TranslateToBufNotFE3
	jb	acc.1,TranslateToBufPrtScr
	jb	acc.2,TranslateToBufPause
	mov	c,acc.0
	mov	ATTXMasqF,c

	; get AT scancode
	mov	a,r4
	mov	dptr,#Mac2ATxltB30
	movc	a,@a+dptr
	mov	OutputBuf,a
	sjmp	TranslateToBufGo

TranslateToBufGo:
	; keyboard disabled?
	jb	ATKbdDisableF,TranslateToBufEnd

	; dont send zero scancodes
	mov	a,OutputBuf
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
; init timer 1 in 16 bit mode for watchdog intervals of 20ms
;----------------------------------------------------------
timer1_20ms_init:
	clr	tr1
	anl	tmod, #0fh	; clear all upper bits
	orl	tmod, #10h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 1, 16bit
	mov	th1, #interval_th_20m_11059_2k
	mov	tl1, #interval_tl_20m_11059_2k
	setb	MacTFModF	; see timer 1 interrupt code
	setb	MiscSleepT1F
	setb	et1		; (IE.3) enable timer 1 interrupt
	setb	tr1		; go
	ret

;----------------------------------------------------------
; init timer 1 in 16 bit mode for post-word-transfer intervals of 300mus
;----------------------------------------------------------
timer1_300u_init:
	clr	tr1
	anl	tmod, #0fh	; clear all upper bits
	orl	tmod, #10h	; M0,M1, bit4,5 in TMOD, timer 1 in mode 1, 16bit
	mov	th1, #interval_th_300u_11059_2k
	mov	tl1, #interval_tl_300u_11059_2k
	clr	MacTFModF	; see timer 1 interrupt code
	setb	MiscSleepT1F
	setb	et1		; (IE.3) enable timer 1 interrupt
	setb	tr1		; go
	ret


;----------------------------------------------------------
; init timer 0 for interval timing (fast 8 bit reload)
; need 75-85mus intervals
;----------------------------------------------------------
timer0_init:
	clr	tr0
	anl	tmod, #0f0h	; clear all lower bits
	orl	tmod, #02h;	; 8-bit Auto-Reload Timer, mode 2
	mov	th0, #interval_t0_85u_11059_2k
	mov	tl0, #interval_t0_85u_11059_2k
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
RCSId	DB	"$Id: kbdbabel_mac_ps2_fmode_8051.asm,v 1.1 2009/08/17 09:18:02 akurz Exp $"

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

	; -- interrupt handler reset
	mov	r7,#8

	; -- watchdog reset
	mov	MacResetTTL,#16
	call	timer1_20ms_init
	setb	MacTxF

; ----------------
Loop:
	; -- check Mac Keyboard receive status
	jb	MacRXCompleteF,LoopProcessMacData

	; -- check on new AT data received
	jb	ATCmdReceivedF,LoopProcessATcmd

	; -- check if AT communication active.
	jb	TFModF,Loop

	; -- Mac Host do device requires this
	jb	MacClkTXCompleteF,LoopPostTXComplete

	; -- Mac Host do device requires this
	jb	MacClkRXCompleteF,LoopPostRXComplete

	; -- post-datagram delay handling
	jnb	MacClkPostF,LoopNotMacClkPostF
	jnb	MiscSleepT1F,LoopPostRXTXSleep
LoopNotMacClkPostF:

	; -- Mac communication TTL handling
	jnb	MacTFModF,LoopNotMacTFModF
	jnb	MiscSleepT1F,LoopTTLProcess
LoopNotMacTFModF:

	; -- check AT line status, clock line must not be busy
	jnb	p3.3,Loop

	; -- check for AT RX data
	jnb	p3.5,LoopATRX

	; -- send data, if data is present
	call	ATTX

;	; -- check if AT communication active.
;	jb	TFModF,Loop

;	; -- may do other things while idle here ...

	sjmp	loop

;----------------------------------------------------------
; helpers for the main loop
;----------------------------------------------------------
; --- Keyboard data received, process the received scancode into output ring buffer
LoopProcessMacData:
	call	TranslateToBuf
	sjmp	Loop

; --- run the delay timer for 300mus
LoopPostTXComplete:
	setb	MacClkPostF
	clr	MacClkTXCompleteF
	call	timer1_300u_init
	sjmp	Loop

; --- run the delay timer for 300mus
LoopPostRXComplete:
	setb	MacClkPostF
	clr	MacClkRXCompleteF
	call	timer1_300u_init
	sjmp	Loop

; --- 300mus delay after communication finished
LoopPostRXTXSleep:
;	clr	p1.99
	clr	MacClkPostF

	; -- interrupt handler reset
	mov	r7,#8

	; -- watchdog reset
	mov	MacResetTTL,#16
	call	timer1_20ms_init

	; -- toggle RX and TX	; @@@@@@@@@@@@@@ FIXME
	jnb	MacTxF,LoopPostTXSleep

	; -- device-to-host
	clr	MacTxF
	setb	p3.4
;	setb	p1.99
	sjmp	Loop

LoopPostTXSleep:
	; --- host-to-devicee
	mov	MacBitBuf,#8h
	setb	MacTxF
	clr	p3.4
;	setb	p1.99
	sjmp	Loop

; --- Mac communication watchdog
LoopTTLProcess:
	mov	a,MacResetTTL
	jnz	LoopTTLProcessNZ
	; -- TTL expired: communication reset/initialization
	clr	p1.0
	; -- watchdog reset
	mov	MacResetTTL,#16
	call	timer1_20ms_init

	; -- interrupt handler init
	mov	r7,#8
	mov	MacBitBuf,#8h
	setb	MacTxF
	; -- pull down data line
	clr	p3.4
	setb	p1.0
	sjmp	Loop

LoopTTLProcessNZ:
	call	timer1_20ms_init
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
	setb	ATHostToDevF
	call	timer0_init

	; wait for completion
LoopTXWaitSent:
	jb	TFModF,LoopTXWaitSent
LoopCheckATEnd:
	ljmp	Loop

; ----------------

;----------------------------------------------------------
; Still space on the ROM left for the license?
;----------------------------------------------------------
LIC01	DB	" Copyright 2007 by Alexander Kurz"
LIC02	DB	" "
GPL01	DB	" This program is free software; you can redistribute it and/or modify"
GPL02	DB	" it under the terms of the GNU General Public License as published by"
GPL03	DB	" the Free Software Foundation; either version 3, or (at your option)"
GPL04	DB	" any later version."
GPL05	DB	" "
GPL06	DB	" This program is distributed in the hope that it will be useful,"
GPL07	DB	" but WITHOUT ANY WARRANTY; without even the implied warranty of"
GPL08	DB	" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the"
GPL09	DB	" GNU General Public License for more details."
GPL10	DB	" "
; ----------------
	end
