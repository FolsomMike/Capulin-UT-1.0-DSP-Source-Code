

debug 	.set 0		; set to zero to ignore debug code
					; set to 1, 2, 3 etc. to choose the desired debug
					; code section -- see function debugCode for more info

debugger .set 1		; set to zero if on-board debugging not used
					; set to 1 to activate the debugger


	.global	debugCode

;-----------------------------------------------------------------------------
; Debugger
;

	.global	initDebugger
	.global storeAllRegisters
	.global debuggerVariables

	.global AG_Register
	.global AH_Register
	.global AL_Register
	.global BG_Register
	.global BH_Register
	.global BL_Register

	.global ST0_Register
	.global ST1_Register

	.global PMST_Register

	.global AR0_Register
	.global AR1_Register
	.global AR2_Register
	.global AR3_Register
	.global AR4_Register
	.global AR5_Register
	.global AR6_Register
	.global AR7_Register

DEBUGGER_VARIABLES_BUFFER_SIZE		.equ	50

;end of Debugger
;-----------------------------------------------------------------------------
