*****************************************************************************
*
*	Capulin UT DSP Debug.asm
*  	Mike Schoonover 5/19/2011
*
*	Description
*	===========
*
*	This is debug code for the DSP software for the Capulin Series UT boards.
*	
*	Target DSP type is Texas Instruments TMS320VC5441.
*
*	Instructions
*	============
*
* IMPORTANT NOTE
*
* This code is used to setup sample data and call various functions in order
* to test them.
*
* To activate this code, set symbol "debug" to non-zero in the file 
* "Globals.asm".  Different values may select different code sections for
* compilation -- search the code below for details.  All files which contain
* debug code should include this file to control the insertion of such code.
*
* The assembler will not allow a symbol used in an .if statement to be
* located in a different file using .def/.ref/.global -- the symbol must be
* defined in each file.  This is solved by placing the symbol in "Globals.asm"
* and having each file include that file.
*
* All code in this file should be contained within the ".if debug/.endif"
* section so that it is not compiled when unneeded.
*
* The debuggerCode section includes code used for debugging on the actual
* board. To use this debugger, symbol "debugger" must be defined in Globals.asm.
*
******************************************************************************

	.mmregs					; definitions for all the C50 registers

	.include	"TMS320VC5441.asm"

	.include "Globals.asm"	; global symbols such as "debug", "debugger"

	.global	pointToGateInfo
	.global	calculateGateIntegral
	.global	BRC
	.global	Variables1
	.global	scratch1

	.global	setADSampleSize
	.global fpgaADSampleBufEnd
	.global SERIAL_PORT_RCV_BUFFER
	.global	FPGA_AD_SAMPLE_BUFFER
	.global	GATES_ENABLED
	.global	setFlags1
	.global	getPeakData

	.text

	.if 	debug

;-----------------------------------------------------------------------------
; debugCode
;
; This code is used to debug various parts of the program.
;
; To use, find the line "debug .set 0" near the top of this file and change
; to "debug .set 1".  This will cause this function to be compiled and a
; branch at the top of mainLoop will also be compiled to jump here.  Use
; the appropriate number instead of 1 to select the different sections of
; debug code.
;
; The debug code below may contain different sections to test different parts
; of the program.  In general, the gate/DAC parameters are set up with values
; required for the test and then the appropriate functions called.
;
; It may be a good idea to create a unique register setup for each different
; section in order to switch quickly between tests.
;
; Depending on the section enabled, the debug code may return back to run
; the main program or it may call specific functions to emulate program
; operation as needed.
;

; set debug to 1, 2, 3, etc. to switch in the desired testing section below

debugCode:



; this loop reached if no code above is defined or the code does not have a freeze loop

deadLoop:

	b	deadLoop

; end of debugCode
;-----------------------------------------------------------------------------


	.endif			; .if debug

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	.if 	debugger

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------
; debuggerCode
;
; This code is used by the debugger. The symbol "debugger" must be defined
; in Globals.asm for this code to be included.
;

; This method stores all registers in memory so they can be accessed for
; display or modification by the host debug controller.

;-----------------------------------------------------------------------------
; initDebugger
;
; Performs various setup functions for the debugger.
;

initDebugger:


	; clear buffer used for storing CPU registers

	stm     #debuggerVariables, AR1        ; top of buffer

	rptz    A, #(DEBUGGER_VARIABLES_BUFFER_SIZE - 1)	;clear A
	stl     A, *AR1+									;and fill buffer

	ret

; end of initDebugger
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; storeRegistersAndHalt
;
; Stores all registers in buffer debuggerVariables so they can be retrieved
; for display by the debugger.
;
; Call this by executing "intr	2" anywhere in the code.
;
; If executing "intr 2" inside an interrupt routine, it should only be done just
; before the rete instruction. The "intr 2" call will re-enable global interrupts.
; Even trying to disable them immediately after the call won't work -- a pending
; interrupt will be caught between the "intr 2" and the next instruction setting
; the INTM flag. If the call is made earlier in the routing, the global interrupts
; being enabled will allow other interrupts to be processed (including a recursive
; call back the the current routine) which can cause problems in some code.
;
; A second version of this function which did not use rete could be called from
; interrupt routines using trap instead of intr. The trap opcode does not affect
; the intm flag. This would require both routines to always be updated together,
; which is a pain.
;

storeRegistersAndHalt:

	pshm	ST0							; save registers modified during store process
	pshm	AR0
	pshm	AR1							; AR0 must be last pushed as it is pop/pushed for storing

	stm     #debuggerVariables, AR1     ; start of Register buffer

	mar		*AR1+						; skip debug status flags
	mvkd	AG, *AR1+
	mvkd	AH, *AR1+
	mvkd	AL, *AR1+
	mvkd	BG, *AR1+
	mvkd	BH, *AR1+
	mvkd	BL, *AR1+
	mvkd	T, *AR1+

	mvkd	ST0, *AR1+
	mvkd	ST1, *AR1+

	mvkd	PMST, *AR1+
	mvkd	BRC, *AR1+

	pshm	AR0						; store value in Stack Pointer
	mvmm 	SP, AR0
	mar     *+AR0(+4)				; add 4 to Stack Pointer displayed to get value when function was entered
	mvkd	AR0, *AR1+				; this accounts for the effect of registers pushed by this debug function
	popm	AR0

	mvkd	AR0, *AR1+

	popm	AR0						; retrieve the stored AR1 into AR0 so AR1 can be saved
	pshm	AR0						; put copy back on stack for retrieval on exit
	mvkd	AR0, *AR1+

	mvkd	AR2, *AR1+
	mvkd	AR3, *AR1+
	mvkd	AR4, *AR1+
	mvkd	AR5, *AR1+
	mvkd	AR6, *AR1+
	mvkd	AR7, *AR1+

	stm     #debuggerVariables, AR1
	orm		#01h, *AR1					; set the debug halt flag

debuggerHalt:							; loop while flag is set
	bitf	*AR1, #01h
	bc	debuggerHalt, TC

	popm	AR1
	popm	AR0
	popm	ST0

	rete

	.newblock						; allow re-use of $ variables

; end of storeRegistersAndHalt
;-----------------------------------------------------------------------------

; end of debuggerCode
;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	.endif			; .if debugger
