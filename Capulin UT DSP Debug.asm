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
* to test them in Code Composer or similar.
*
* In order to use the IDE debugger to step through code, this file must be
* compiled and linked.  If it is simply included in the main file using the
* ".include" directive, the debugger will revert to using an inelegant
* disassembly window and will not allow the user to step through the original
* asm code.
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

storeRegistersAndHalt:

	pshm	ST0							; save registers modified during store process
	pshm	AR1
	pshm	AR0							; AR0 must be last pushed as it is pop/pushed for storing

	stm     #debuggerVariables, AR0     ; start of Register buffer

	mar		*AR0+						; skip debug status flags
	mvkd	AG, *AR0+
	mvkd	AH, *AR0+
	mvkd	AL, *AR0+
	mvkd	BG, *AR0+
	mvkd	BH, *AR0+
	mvkd	BL, *AR0+

	mvkd	ST0, *AR0+
	mvkd	ST1, *AR0+

	mvkd	PMST, *AR0+

	mvkd	AR0, *AR0+				; dummy save as AR0 has been changed during use as a pointer
	mvkd	AR1, *AR0+
	mvkd	AR2, *AR0+
	mvkd	AR3, *AR0+
	mvkd	AR4, *AR0+
	mvkd	AR5, *AR0+
	mvkd	AR6, *AR0+
	mvkd	AR7, *AR0+

	popm	AR1							; retrieve the stored AR0 into AR1 so it can be properly saved
	pshm	AR1							; save it again for final restore back to AR0

	stm     #debuggerVariables, AR0     ; back to start as this is a known basepoint
	mar		*+AR0(10)					; point to AR0 storage variable
										; use mar to move AR0 as *+ARx(x) can't be used with mvkd to save to memory 			
										; mapped registers

	mvkd	AR1, *AR0+					; store the original AR0 value (currently in AR1)


	stm     #debuggerVariables, AR0
	orm		#01h, *AR0					; set the debug halt flag
debuggerHalt:							; loop while flag is set
	bitf	*AR0, #01h
	bc	debuggerHalt, TC

	popm	AR0
	popm	AR1
	popm	ST0

	ret

; end of storeRegistersAndHalt
;-----------------------------------------------------------------------------

; end of debuggerCode
;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	.endif			; .if debugger
