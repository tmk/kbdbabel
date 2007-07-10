; ---------------------------------------------------------------------
; KbdBabel Common constants and definitions
; for various keyboard interval und timing issues.
;
; $KbdBabel: kbdbabel_intervals.inc,v 1.2 2007/07/09 22:19:59 akurz Exp $
;
; Copyright 2007 by Alexander Kurz
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 3, or (at your option)
; any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;----------------------------------------------------------

;----------------------------------------------------------
; misc 8-bit constants
;----------------------------------------------------------
;------------------ AT scancode timing intervals generated with timer 0 in 8 bit mode
; --- double cycle (21*40mus), usable with >12MHz controller speed
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

; --- single cycle (10*80mus), for <12MHz controller speed
; 85mus@11.0592MHz -> th0 and tl0=178 or 78 processor cycles	; (256-11059.2*0.085/12)
interval_t0_85u_11059_2k	equ	178

; 80mus@11.0592MHz -> th0 and tl0=183 or 73 processor cycles	; (256-11059.2*0.08/12)
interval_t0_80u_11059_2k	equ	183

; 75mus@11.0592MHz -> th0 and tl0=187 or 69 processor cycles	; (256-11059.2*0.075/12)
interval_t0_75u_11059_2k	equ	187

; 80mus@12.000MHz -> th0 and tl0=176 or 80 processor cycles	; (256-12000*0.08/12)
interval_t0_80u_12M		equ	176

; do not use:
; 80mus@18.432MHz -> th0 and tl0=134 or 122 processor cycles	; (256-18432*0.08/12)
;interval_t0_80u_18432k		equ	134

; do not use:
; 80mus@24.000MHz -> th0 and tl0=96 or 160 processor cycles	; (256-24000*0.08/12)
;interval_t0_80u_24M		equ	96

;------------------ WY-85 interval generation with timer 1 in 8 bit mode
; 17mus@24.000MHz -> th0 and tl0=222 or 34 processor cycles	; (256-24000*0.017/12)
interval_t1_17u_24M		equ	222

; 25mus@24.000MHz -> th0 and tl0=206 or 50 processor cycles	; (256-24000*0.025/12)
interval_t1_25u_24M		equ	206

; 30mus@24.000MHz -> th0 and tl0=196 or 60 processor cycles	; (256-24000*0.03/12)
interval_t1_30u_24M		equ	196

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

;------------------ Mac scancode timing intervals generated with timer 1 in 8 bit mode
; 200mus@11.0592MHz -> th0 and tl0=72 or 184 processor cycles	; (256-11059.2*0.2/12)
interval_t1_200u_11059_2k	equ	72

; 150mus@11.0592MHz -> th0 and tl0=118 or 138 processor cycles	; (256-11059.2*0.15/12)
interval_t1_150u_11059_2k	equ	118

;----------------------------------------------------------
; misc 16-bit constants
;----------------------------------------------------------
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

; 40mus@11.0592MHz -> th0,tl0=0ffh,dch	; (65536-11059.2*0.04/12)
interval_th_40u_11059_2k	equ	255
interval_tl_40u_11059_2k	equ	220

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

; 40mus@18.432MHz -> th0,tl0=0ffh,C3h	; (256-18432*0.04/12) (65536-18432*0.04/12)
interval_th_40u_18432k		equ	255
interval_tl_40u_18432k		equ	194

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

; 40mus@22.1184MHz -> th0,tl0=0ffh,b7h	; (65536-22118.4*0.04/12)
interval_th_40u_22118_4k	equ	255
interval_tl_40u_22118_4k	equ	183

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

; 40mus@24MHz -> th0,tl0=0ffh,b0h	; (65536-24000*0.04/12)
interval_th_40u_24M		equ	255
interval_tl_40u_24M		equ	176

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
; constants for UART bitrate generation
;----------------------------------------------------------
;------------------ bitrates generated with timer 1 in 8 bit mode
; --- 1.2kBPS: Sun
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

; --- 4.8kBPS: DEC LK
; 4800BPS @11.0592MHz -> tl1 and th1 = #244 with SMOD=1	; (256-2*11059.2/384/4.8)
uart_t1_4800_11059_2k		equ	244

; 4800BPS @18.432MHz -> tl1 and th1 = #236 with SMOD=1	; (256-2*18432/384/4.8)
uart_t1_4800_18432k		equ	236

; --- 7.8125kBPS: Atari ST
; 7812.5BPS @12MHz -> tl1 and th1 = #248 with SMOD=1	; (256-2*12000/384/7.8125)
uart_t1_7k8125_12M		equ	248

; 7812.5BPS @24MHz -> tl1 and th1 = #240 with SMOD=1	; (256-2*24000/384/7.8125)
uart_t1_7k8125_24M		equ	240

; 9600BPS @18.432MHz -> tl1 and th1 = #246 with SMOD=1	; (256-2*18432/384/9.6)
uart_t1_9600_18432k		equ	246

;------------------ bitrates generated with timer 2
; 9600 BPS at 18.432MHz -> RCAP2H,RCAP2L=#0FFh,#0c4h	; (256-18432/32/9.6)
uart_t2h_9600_18432k		equ	255
uart_t2l_9600_18432k		equ	196
