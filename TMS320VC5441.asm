******************************************************************************
*
*	TMS320VC5441.asm
*  	Mike Schoonover 5/19/2009
*
*	Description
*	===========
*
*	This file contains register and constant definitions pertaining to the
*   TMS320VC5441 chip.
*
*	Instructions
*	============
*
*	Include this file in the source code file:
*
*		.include	"TMS320VC5441.asm"
*
*
******************************************************************************

; Miscellaneous Registers

CSIDR		.equ	3eh


; McBSP Control Registers
; From table 3-24 of TMS320VC5441 Data Manual SPRS122F

; address register - load this with the subaddress before writing to SPSD*

SPSA1		.equ	48h					; for McBSP1

; read/write register - accesses the register pointed to by SPSA*

SPSD1		.equ	49h					; for McBSP1

; subaddresses - same for all McBSPs

SPCR1		.equ	00h
SPCR2		.equ	01h
RCR1		.equ	02h
RCR2		.equ	03h
XCR1		.equ	04h
XCR2		.equ	05h
PCR			.equ	0eh

; McBSP1 registers

DRR21		.equ	40h
DRR11		.equ	41h
DXR21		.equ	42h
DXR11		.equ	43h

**************************************************
*
* 54x Register Definitions for the DMA Controller
*
**************************************************

DMPREC		.equ	54h ;Channel Priority and Enable Control Register
DMSA		.equ	55h ;Sub-bank Address Register
DMSDI		.equ	56h ;Sub-bank Data Register with autoincrement
DMSDN		.equ	57h ;Sub-bank Data Register without modification
DMSRC0		.equ	00h ;Channel 0 Source Address Register
DMDST0		.equ	01h ;Channel 0 Destination Address Register
DMCTR0		.equ	02h ;Channel 0 Element Count Register
DMSFC0		.equ	03h ;Channel 0 Sync Select and Frame Count Register
DMMCR0		.equ	04h ;Channel 0 Transfer Mode Control Register
DMSRC1		.equ	05h ;Channel 1 Source Address Register
DMDST1		.equ	06h ;Channel 1 Destination Address Register
DMCTR1		.equ	07h ;Channel 1 Element Count Register
DMSFC1		.equ	08h ;Channel 1 Sync Select and Frame Count Register
DMMCR1		.equ	09h ;Channel 1 Transfer Mode Control Register
DMSRC2		.equ	0ah ;Channel 2 Source Address Register
DMDST2		.equ	0bh ;Channel 2 Destination Address Register
DMCTR2		.equ	0ch ;Channel 2 Element Count Register
DMSFC2		.equ	0dh ;Channel 2 Sync Select and Frame Count Register
DMMCR2		.equ	0eh ;Channel 2 Transfer Mode Control Register
DMSRC3		.equ	0fh ;Channel 3 Source Address Register
DMDST3		.equ	10h ;Channel 3 Destination Address Register
DMCTR3		.equ	11h ;Channel 3 Element Count Register
DMSFC3		.equ	12h ;Channel 3 Sync Select and Frame Count Register
DMMCR3		.equ	13h ;Channel 3 Transfer Mode Control Register
DMSRC4		.equ	14h ;Channel 4 Source Address Register
DMDST4		.equ	15h ;Channel 4 Destination Address Register
DMCTR4		.equ	16h ;Channel 4 Element Count Register
DMSFC4		.equ	17h ;Channel 4 Sync Select and Frame Count Register
DMMCR4		.equ	18h ;Channel 4 Transfer Mode Control Register
DMSRC5		.equ	19h ;Channel 5 Source Address Register
DMDST5		.equ	1ah ;Channel 5 Destination Address Register
DMCTR5		.equ	1bh ;Channel 5 Element Count Register
DMSFC5		.equ	1ch ;Channel 5 Sync Select and Frame Count Register
DMMCR5		.equ	1dh ;Channel 5 Transfer Mode Control Register
DMSRCP		.equ	1eh ;Source Program Page Address
DMDSTP		.equ	1fh ;Destination Program Page Address
DMIDX0		.equ	20h ;Element Address Index Register 0
DMIDX1		.equ	21h ;Element Address Index Register 1
DMFRI0		.equ	22h ;Frame Address Index Register 0
DMFRI1		.equ	23h ;Frame Address Index Register 1
DMGSA0		.equ	24h ;Channel 0 Global Source Address Reload Register
DMGDA0		.equ	25h ;Channel 0 Global Destination Address Reload Register
DMGCR0		.equ	26h ;Channel 0 Global Element Count Reload Register
DMGFR0		.equ	27h ;Channel 0 Global Frame Count Reload Register
RSRVD1		.equ	28h	;Reserved
RSRVD2		.equ	29h	;Reserved
DMGSA1		.equ	2ah ;Channel 1 Global Source Address Reload Register
DMGDA1		.equ	2bh ;Channel 1 Global Destination Address Reload Register
DMGCR1		.equ	2ch ;Channel 1 Global Element Count Reload Register
DMGFR1		.equ	2dh ;Channel 1 Global Frame Count Reload Register
DMGSA2		.equ	2eh ;Channel 2 Global Source Address Reload Register
DMGDA2		.equ	2fh ;Channel 2 Global Destination Address Reload Register
DMGCR2		.equ	30h ;Channel 2 Global Element Count Reload Register
DMGFR2		.equ	31h ;Channel 2 Global Frame Count Reload Register
DMGSA3		.equ	32h ;Channel 3 Global Source Address Reload Register
DMGDA3		.equ	33h ;Channel 3 Global Destination Address Reload Register
DMGCR3		.equ	34h ;Channel 3 Global Element Count Reload Register
DMGFR3		.equ	35h ;Channel 3 Global Frame Count Reload Register
DMGSA4		.equ	36h ;Channel 4 Global Source Address Reload Register
DMGDA4		.equ	37h ;Channel 4 Global Destination Address Reload Register
DMGCR4		.equ	38h ;Channel 4 Global Element Count Reload Register
DMGFR4		.equ	39h ;Channel 4 Global Frame Count Reload Register
DMGSA5		.equ	3ah ;Channel 5 Global Source Address Reload Register
DMGDA5		.equ	3bh ;Channel 5 Global Destination Address Reload Register
DMGCR5		.equ	3ch ;Channel 5 Global Element Count Reload Register
DMGFR5		.equ	3dh ;Channel 5 Global Frame Count Reload Register
DMSRCDP0	.equ	3eh ;Channel 0 Extended Source Data Page Register
DMDSTDP0	.equ	3fh	;Channel 0 Extended Destination Data Page Register
DMSRCDP1	.equ	40h ;Channel 1 Extended Source Data Page Register
DMDSTDP1	.equ	41h	;Channel 1 Extended Destination Data Page Register
DMSRCDP2	.equ	42h ;Channel 2 Extended Source Data Page Register
DMDSTDP2	.equ	43h	;Channel 2 Extended Destination Data Page Register
DMSRCDP3	.equ	44h ;Channel 3 Extended Source Data Page Register
DMDSTDP3	.equ	45h	;Channel 3 Extended Destination Data Page Register
DMSRCDP4	.equ	46h ;Channel 4 Extended Source Data Page Register
DMDSTDP4	.equ	47h	;Channel 4 Extended Destination Data Page Register
DMSRCDP5	.equ	48h ;Channel 5 Extended Source Data Page Register
DMDSTDP5	.equ	49h	;Channel 5 Extended Destination Data Page Register
