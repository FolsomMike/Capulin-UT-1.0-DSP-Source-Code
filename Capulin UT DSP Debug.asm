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
******************************************************************************

	.include "Globals.asm"	; global symbols such as "debug"


	.global	pointToGateInfo
	.global	calculateGateIntegral
	.global	BRC
	.global	Variables1
	.global	scratch1
	.global	debugCode

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

;debug mks - remove this section - testing for slow AScan processing

;	call	setAScanScale
;	call	processAScanSlowInit
;$2	call	processAScanSlow
;	b		$2

; setup the various parameters and gate info
; this entire section must be blocked out for normal operation
; as the gates are already set up by the time this code is reached
; and this will overwrite them
;
; block out by setting debug to 0


	ld		#Variables1, DP	; point to Variables1 page

; setup the FPGA data transfer size and related variables by
; faking data received from the host

	stm		#SERIAL_PORT_RCV_BUFFER, AR3
	nop										; pipeline protection
	nop

	mar		*AR3+					; skip past the packet size byte

	ld		#0, A					; high byte of unpacked data packet size
	stl		A, *AR3+

	ld		#40, A					; low byte of unpacked data packet size
	stl		A, *AR3-

	mar		*AR3-					; point back to packet size
	
	call	setADSampleSize		

; store some data in the raw buffer used to transfer data from the FPGA
; this data is packed -- two data bytes per word

	stm		#FPGA_AD_SAMPLE_BUFFER, AR3

	ld		#20, A			; number of samples to store
	stlm	A, BRC
	ld		#0, A			; start sample values at 0

	rptb	$4				; store 20 ascending values
	stl		A, *AR3+
	add		#1, A
$4: nop						; rptb fails if block ends on 2 word instruction


	ld		fpgaADSampleBufEnd, A 	; get pointer to end of FPGA sample buffer
	stlm	A, AR3
	nop								; pipeline protection
	nop
	ld		#81h, A
	stl		A, *AR3			; set FPGA data ready/packet count flag

; enable gate processing by faking data received from the host

	stm		#SERIAL_PORT_RCV_BUFFER, AR3
	nop										; pipeline protection
	nop

	mar		*AR3+					; skip past the packet size byte

	ld		#0, A
	or		#GATES_ENABLED, A
	
	stl		A, -8, *AR3+			; high byte of Flags1 set bit mask
	and		#0ffh, A				; mask off high byte
	stl		A, *AR3-				; low byte of Flags1 set bit mask

	mar		*AR3-					; point back to packet size
	
	call	setFlags1		

; set up gate 0 for use in testing

	ld		#0h, A			; use gate 0 for testing
	call	pointToGateInfo	; point AR2 to the gate's parameter list

	mar		*AR2-			; move back to gate ID

	ld		#99h, A			; change to an ID number easily seen
	stl		A, *AR2+		;   for debug purposes

	ld		#0c081h, A		; gate flags -- active, flag on max, find peak
	stl		A, *AR2+

	mar		*AR2+			; skip entry MSW of gate start point

	ld		#0000h, A		; LSW of gate start point in time
	stl		A, *AR2+

	mar		*AR2+			; skip gate adjusted start point entry

	ld		#3h, A			; width of gate divided by 3
	stl		A, *AR2+

	ld		#5, A			; height of gate
	stl		A, *AR2+

; Main Code Test


	call	getPeakData

; if debug = 1, return to execute main code
; this is a good, extensive test method as it checks the actual
; processing code

	.if		debug = 1

	ret

	.endif


; WARNING WARNINIG WARNING WARNING WARNINIG WARNING

; following code will not work until a call to setGateAdjustedStart
; is added to set the true gate position in the memory buffer
; call it right here!

; put sample data into the new data buffer and the 3 averaging buffers

	ld		#9h, A			; actual width of the gate
	sub		#1, A			; subtract 1 to account for loop behavior
	stlm	A, BRC

; set up AR3, AR4, AR5, AR6 to point to the averaging buffers


;WARNING
; point to gate and load adjusted start from there instead of scratch1
; code which set scratch1 has been removed
	ld		scratch1, A		; get the gate adjusted start location stored previously
;WARNING

	stlm	A, AR3
	add		#2000h, A		; buffer 1
	stlm	A, AR4
	add		#2000h, A		; buffer 2
	stlm	A, AR5
	add		#2000h, A		; buffer 3
	stlm	A, AR6

	ld		#1h, A

	; place an ascending value in the buffers

	rptb	$3

	stl		A, *AR3+
	stl		A, *AR4+
	stl		A, *AR5+
	stl		A, *AR6+
	add		#1, A
$3: nop						; rptb fails if block ends on 2 word instruction
							;  (this may be a simulator problem only)

;point AR2 to gate parameters and scratch1 to gate index as expected by
; calculateGateIntegral (in this case use gate 0)

$2:	ld		#0h, A			; use gate 0 for testing
	call	pointToGateInfo	; point AR2 to the gate's parameter list

	call	calculateGateIntegral

;	call	averageGate

	b		$2


; this loop reached if no code above is defined or the code does not have a freeze loop

deadLoop:

	b	deadLoop

; end of debugCode
;-----------------------------------------------------------------------------


	.endif			; .if debug
