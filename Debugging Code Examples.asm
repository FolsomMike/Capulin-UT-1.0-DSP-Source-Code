
;debug mks -- test circular buffer
;	ld		#0aa55h, A
;	call	storeWordInMapBuffer
;	ld		#055aah, A
;	call	storeWordInMapBuffer
;debug mks


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
