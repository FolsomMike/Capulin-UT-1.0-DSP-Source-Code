*****************************************************************************
*
*	Capulin UT DSP.asm
*  	Mike Schoonover 5/19/2009
*
*	Description
*	===========
*
*	This is the DSP software for the Capulin Series UT boards.
*
*	Target DSP type is Texas Instruments TMS320VC5441.
*
*	Instructions
*	============
*
* IMPORTANT NOTE
*
* To assemble the program for use with the Capulin system, use the
* batch file located in the root source folder, such as:
* 	"aa Assemble Capulin UT DSP.bat"
* This batch files creates the necessary output hex file for loading
* into the DSPs.  Assembling in the IDE does NOT create the hex file.
* Compile and debug in the IDE, then execute the assemble batch file
* from Windows Explorer, then execute the copy batch file to copy the
* hex file to the proper location for use by the Java program.
*
* When creating a Code Composer project, the root source folder should
* be used as the project folder.  The root folder is the folder containing
* all the source code and the assemble batch file mentioned above.  If
* care is not taken, Composer will create another folder inside the root
* folder which will make things more confusing.
*
* Use Project/New, type in the project name, then browse to the root source
* folder for the "Location".  Composer may try to add the project name to
* the root folder -- remove the project name from the end of the path list.
* Double check the "Location" path to ensure that it ends with the root
* source folder before clicking "Finish".
*
* Two nearly identical .cmd files are used.  The one used by the assembler
* batch file mentioned above uses one to load the .obj file from the root
* source folder where the batch file specifies it to be placed.  The other
* cmd file has a name like "Capulin UT DSP - Debug - use in Code Composer.cmd"
*  and is loaded into the Composer project so that it loads the .obj file
* from the "Debug" folder where Composer places it by default for debug mode.
*
* NOTE: Any changes to one .cmd file should be copied to the other.
*
* After creating a project, choose Project/Build Options/Linker tab/Basic
* and set "Autoinit Model" to "No Autoinitialization" to avoid the undefined
* warning for "_c_int00".
*
* To debug in Composer, use Build All, then File/Load Program to load the
* .out file from the root source directory.  Each time the project is rebuilt
* use File/Reload Program.  After each load or reload, use Debug/Reset CPU
* to refresh the disassembly and code windows.  Use View/Memory to view
* the memory data.
*
* Debug setup and testing code is contained in "Capulin UT DSP Debug.asm",
* the code in which is not compiled unless the assembler symbol "debug" is
* defined in "Globals.asm". Search for the phrase "debugCode" and read the
* notes in "Capulin UT DSP Debug.asm" for more info.
*
* When installing Code Composer, you must the Code Composer Studio Setup
* program first.  From the center column, select the C5410 Device Simulator
* and click "Add", then "Save & Quit".  The '5410 does not fully simulate the
* '5441, but it has most of the features.  It only simulates one core of the
* four contained in the '5441.
*
*
* DMA Addressing
* 
* Each core can access its own data memory via DMA and two of its shared
* program pages. A core can run code from any of the pages it shares with
* its partner (Core A with B and C with D), but each core can only access
* some of its shared pages via DMA.
*
* Via DMA: 
* Core A can access MPAB0/MPAB1		(Debugger views as Shared Page 0/1)
* Core B can access MPAB2/MPAB3		(Debugger views as Shared Page 2/3)
* Core C can access MPCD0/MPCD1		(Debugger views as Shared Page 0/1)
* Core D can access MPCD2/MPCD3		(Debugger views as Shared Page 2/3)
*
* This also affects the HPIA bus which is used to view memory and load code
* by the host. Code for A/B in MPAB0 must be written to Core A Shared Page 0,
* while for C/D Core C Shared Page 0 is used.
*
* Thus only core A can use the DMA to modify code for Cores A/B on the fly
* as the code is stored in MPAB0.
*
* Likewise, only core C can use the DMA to modify code for Cores C/D on the fly
* as the code is stored in MPCD0.
*
* See: TMS320VC5441 Fixed-Point Digital Signal Processor Data Manual
*	Figure 3?8. Subsystem A Local DMA Memory Map
*
* Multiple DMA Channels Issue
*
* According to "TMS320VC5441 Digital Signal Processor Silicon Errata"
* manual SPRZ190B, a problem can occur when enabling a DMA channel in
* which another active channel may also be inadvertantly enabled as
* well.  If the other active channel finishes and clears its DE bit
* at the exact same time as an ORM instruction is used to enable a
* different channel, the ORM can overwrite the bit just cleared by
* the other channel. This can happen because the DMA channels run
* asynchronously to the code which is executing the ORM.
*
* Currently, this code does not have a problem because only two
* channels are being used: one to handle the serial port and one to
* write code to program memory by various functions. Since the serial
* port is in ABU mode it is always active so there is no conflict.
*
* If more DMA channels are to be used, precautions will need to be taken
* as suggested in the Errata manual.
*
******************************************************************************

	.mmregs					; definitions for all the C50 registers

	.include	"TMS320VC5441.asm"

	.include "Globals.asm"	; global symbols such as "debug", "debugger"

	; Use .global with a label here to have the label and its address listed
	;  in the .map file, .abs file, or to be used between different .asm files

	.global	Variables1
	.global	scratch1
	.global	scratch2
	.global	scratch3
	.global	scratch4

	.global wallPeakBuffer
	.global gateBuffer
	.global gateResultsBuffer

;-----------------------------------------------------------------------------
; Miscellaneous Defines
;

; IMPORTANT NOTE: SERIAL_PORT_RCV_BUFFER is a circular buffer and must be
;  placed at an allowed boundary based on the size of the buffer - see manual
; "TMS320C54x DSP Reference Set Volume 5: Enhanced Peripherals" Table 3-11
; for details:
;
; Also see "TMS320C54x DSP Reference Set Volume 1: CPU and Peripherals" section
; 5.5.3.4 Circular Address Modifications.
;
; Note: a circular buffer does not use a register to hold the base address.
;  The size of the buffer is placed in the BK register. An ARx register is
;  then pointed anywhere in the buffer. The address rolls back around by
;  zeroing some of the least significant bits of ARx based on the value in
;  the BK register -- the address rolls back around to the base adddress
;  by zeroing some of the least significant bits of ARx. This works because
;  the base address is positioned such that its least significant bits are
;  zeroed -- enough in which to fit the size value in the BK register.
;

; allowable circular buffer addressing:
; for buffer size 0100h-01FFh (256-511) -> XXXX XXX0 0000 0000 b (Table 3-11) 

SERIAL_PORT_RCV_BUFFER		.equ	0x3000	; circular buffer for serial port in
SERIAL_PORT_RCV_BUFSIZE		.equ	0x100	; size of buffer
SERIAL_PORT_XMT_BUFFER		.equ	0x3500	; buffer for serial port out


ASCAN_BUFFER				.equ	0x3700	; AScan data set stored here
FPGA_AD_SAMPLE_BUFFER		.equ	0x4000	; FPGA stores AD samples here
PROCESSED_SAMPLE_BUFFER		.equ	0x8000	; processed data stored here

; IMPORTANT NOTE: MAP_BUFFER is a circular buffer and must be placed at an
; allowed boundary based on the size of the buffer - see notes for
; SERIAL_PORT_RCV_BUFFER for details
;
; allowable circular buffer addressing:
; for buffer size 0400h?07FFh (1024?2047) XXXX X000 0000 0000 b (Table 3-11)
;
; The DSP stores samples in the MAP_BUFFER for later transfer to the host.
; The MAP_BUFFER is meant to reside in data page MD*1.
; (* = A/B/C/D depending on core)
; MD*0 is switched into 8000h-ffffh when DMMR = 0
; MD*1 is switched into 8000h-ffffh when DMMR = 1
; MD*0 and MD*1 can be viewed in the Chart software's debugger window:
; MD*0 is accessed via Local Page 0; MD*1 vai Local Page 1
; In the debugger, Local Page 0 and 2 are mirrored, 2 and 3 are mirrored
; due to the nature of the HPIA bus addressing.

MAP_BUFFER					.equ	0x8000	; circular buffer for map data
MAP_BUFFER_SIZE				.equ	0x07D0	; size of buffer (2000d)
MAP_BLOCK_WORD_SIZE			.equ	50		; number of words sent to host in map block

; bits for flags1 variable -- ONLY set by host

PROCESSING_ENABLED			.equ	0x0001	; sample processing enabled
GATES_ENABLED				.equ	0x0002	; gates enabled flag
DAC_ENABLED					.equ	0x0004	; DAC enabled flag
ASCAN_FAST_ENABLED			.equ	0x0008	; AScan fast version enabled flag
ASCAN_SLOW_ENABLED			.equ	0x0010	; AScan slow version enabled flag
ASCAN_FREE_RUN				.equ	0x0020	; AScan runs free, not triggered by a gate
DSP_FLAW_WALL_MODE			.equ	0x0040	; DSP is a basic flaw/wall peak processor
DSP_WALL_MAP_MODE			.equ	0x0080	; DSP is a wall mapping processor

;bit masks for processingFlags1 -- ONLY set by DSP

IFACE_FOUND					.equ	0x0001
WALL_START_FOUND			.equ	0x0002
WALL_END_FOUND				.equ	0x0004
TRANSMITTER_ACTIVE			.equ	0x0008	; transmitter active flag
CREATE_ASCAN				.equ	0x0010	; signals that a new AScan dataset should be created

POSITIVE_HALF				.equ	0x0000
NEGATIVE_HALF				.equ	0x0001
FULL_WAVE					.equ	0x0002
RF_WAVE						.equ	0x0003

;bits for gate and DAC flags
GATE_ACTIVE						.equ	0x0001
GATE_REPORT_NOT_EXCEED			.equ	0x0002
GATE_MAX_MIN					.equ	0x0004
GATE_WALL_START					.equ	0x0008
GATE_WALL_END					.equ	0x0010
GATE_FIND_CROSSING				.equ	0x0020
GATE_USES_TRACKING				.equ	0x0040
GATE_FIND_PEAK					.equ	0x0080
GATE_FOR_INTERFACE				.equ	0x0100
GATE_INTEGRATE_ABOVE_GATE		.equ	0x0200
GATE_QUENCH_ON_OVERLIMIT		.equ	0x0400
GATE_TRIGGER_ASCAN_SAVE			.equ	0x0800
SUBSEQUENT_SHOT_DIFFERENTIAL	.equ	0x1000

;bit masks for gate results data flag

HIT_COUNT_MET			.equ	0x0001
MISS_COUNT_MET			.equ	0x0002
GATE_MAX_MIN			.equ	0x0004
GATE_EXCEEDED			.equ	0x0008

;size of buffer entries

;WARNING: Adjust these values any time you add more bytes to the buffers.

GATE_PARAMS_SIZE		.equ	14
GATE_RESULTS_SIZE		.equ	13
DAC_PARAMS_SIZE			.equ	9


MAX_NUM_COEFFS			.equ	31		; max number of coefficients for which space is reserved
NUM_COEFFS_IN_PKT		.equ	4		; number of coefficients (unpacked words) in each packet
MAX_COEFF_BLOCK_NUM		.equ	8		; max number for coefficients packet Descriptor Code

; end of Miscellaneous Defines
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; Message / Command IDs
; Should match settings in host computer.
;

DSP_NULL_MSG_CMD				.equ	0
DSP_GET_STATUS_CMD 				.equ	1
DSP_SET_GAIN_CMD 				.equ	2
DSP_GET_ASCAN_BLOCK_CMD			.equ	3
DSP_GET_ASCAN_NEXT_BLOCK_CMD	.equ	4
DSP_SET_AD_SAMPLE_SIZE_CMD		.equ	5
DSP_SET_DELAYS					.equ	6
DSP_SET_ASCAN_RANGE				.equ	7
DSP_SET_GATE					.equ	8
DSP_SET_GATE_FLAGS				.equ	9
DSP_SET_DAC						.equ	10
DSP_SET_DAC_FLAGS				.equ	11
DSP_SET_HIT_MISS_COUNTS			.equ	12
DSP_GET_PEAK_DATA				.equ	13
DSP_SET_RECTIFICATION			.equ	14
DSP_SET_FLAGS1					.equ	15
DSP_UNUSED1						.equ	16
DSP_SET_GATE_SIG_PROC_THRESHOLD	.equ	17
DSP_GET_MAP_BLOCK_CMD			.equ	18
DSP_GET_MAP_COUNT_CMD			.equ	19
DSP_RESET_MAPPING_CMD			.equ	20
DSP_SET_FILTER_CMD				.equ	21

DSP_ACKNOWLEDGE					.equ	127

; end of Message / Command IDs
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; Vectors
;
; For the TMS320VC5441, each dsp core begins execution at the reset vector
; at 0xff80.
;
; NOTE: The vector table can be relocated by changing the IPTR in the PMST
; register.  The 9 bit IPTR pointer selects the 128 word program page where
; the vectors start.  At reset, it is set to 0x1ff which puts the vector table
; at 0xff80 on page 0 as that page is the default at reset.  Since the reset
; vector is always at offset 0 in this table, it will always be at 0xff80.
;
; If the program memory page is changed via the XPC register, a copy of the
; vector table must exist on the page being switched to if interrrupts are
; active during that time.  Alternatively, the vector table can be relocated
; at run time to a section which is constant regardless of which page is
; active.  For instance, on the TMS320VC5441 for core A, MPDA is always present
; in the lower half of program memory when OVLY=0 and MPAB3 is always present
; when OVLY=1.  The vectors can be copied to one of these pages (which depends
; on the setting of OVLY) and will always be active regardless of the currently
; selected page.  For MPD*, words 0h - 60h are reserved so the table should not
; be relocated to those addresses.
;
; Similarly, any code branched to by the interrupt vector must also be available
; when the interrupt occurs.
;
; Table 3-26 of the TMS320VC5441 Data Manual shows the offsets for each vector
; in the vector table.  These are not the actual addresses - add these values
; to the first word of the page being pointed to by IPTR.  If IPTR is 0x1ff,
; the first vector will be at 0x1ff * 128 = 0xff80.  The reset vector is listed
; as being at 0x00 so it can be found at 0xff80 + 0x00 = 0xff80.
;

	.sect	"vectors"			; link this at 0xff80

	b		main

; end of Vectors
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; Variables - uninitialized

	.bss	Variables1,1			; used to mark the first page of variables

	.bss	breakPointControl,1		; enables or disables specific breakpoints

	.bss	heartBeat,1				; incremented constantly to show that program
									; is running

	.bss	flags1,1				; bit 0 : sample processing enabled
									; bit 1 : Gates Enabled
									; bit 2 : DAC Enabled
									; bit 3 : Fast AScan Enabled
									; bit 4 : Slow AScan Enabled
									; bit 5 : AScan free run, not triggered by a gate
									; bit 6 : DSP is a basic flaw/wall peak processor
									; bit 7 : DSP is a wall mapping processor

	.bss	softwareGain,1			; gain multiplier for the signal
	.bss	adSampleSize,1			; size of the unpacked data set from the FPGA
	.bss	adSamplePackedSize,1	; size of the data set from the FPGA
	.bss	fpgaADSampleBufEnd,1	; end of the buffer where FPGA stores A/D samples
	.bss	coreID,1				; ID number of the DSP core (1-4)
	.bss	numCoeffs,1				; number of coefficients for FIR filter
	.bss	numFIRLoops,1			; one less than numCoeffs to work with repeat opcode
	.bss	firBufferEnd,1			; last position of FIR buffer (based on number of coefficients)
	.bss	filterScale,1			; scaling for FIR filter output (number of bits to right shift)
	.bss	getAScanBlockPtr,1		; points to next data to send to host
	.bss	getAScanBlockSize,1		; number of AScan words to transfer per packet
	.bss	hardwareDelay1,1		; high word of FPGA hardware delay
	.bss	hardwareDelay0,1		; low word of FPGA hardware delay
	.bss	aScanDelay,1			; delay for start of AScan
	.bss	aScanScale,1			; compression scale for AScan
	.bss	aScanChunk,1			; number of input points to scan for each output point
	.bss	aScanSlowBatchSize,1	; number of output data words to process in each batch
	.bss	aScanMin,1				; stores min values during compression
	.bss	aScanMinLoc,1			; location of min peak
	.bss	aScanMax,1				; stores max values during compression
	.bss	aScanMaxLoc,1			; location of max peak
	.bss	trackCount,1			; location tracking value
	.bss	freeTimeCnt1,1			; high word of free time counter
	.bss	freeTimeCnt0,1			; low word of free time counter
	.bss	freeTime1,1				; high word of free time value
	.bss	freeTime0,1				; low word of free time value

	.bss	mapBufferInsertIndex,1	; tracks insertion point of circular map buffer
	.bss	mapBufferExtractIndex,1	; tracks extraction point of circular map buffer
	.bss	mapBufferCount,1		; tracks number of words available in the map buffer
	.bss	previousMapTrack,1		; storage of the track variable for detecting change
	.bss	mapPacketCount,1		; counts number of packets sent to host -- rolls over at 255

; the next block is used by the function processAScanSlow for variable storage

	.bss	inBufferPASS,1			; pointer to data in input buffer
	.bss	outBufferPASS,1			; pointer to data in output buffer
	.bss	totalCountPASS,1		; counts total number of output data points

; end of PASS variables

	.bss	serialPortInBufPtr,1	; points to next position of in buffer
	.bss	reSyncCount,1			; tracks number of times reSync required

	.bss	hitCountThreshold,1		; gate violations required to flag
	.bss	missCountThreshold,1	; gate misses required to flag

	.bss	dma3Source,1			; used to write to program memory via DMA

	.bss	frameCount1,1			; MSB of A/D data sets count
	.bss	frameCount0,1			; LSB of A/D data sets count
	.bss	frameSkipErrors,1		; missing data set error count
	.bss	frameCountFlag,1		; stores previous count flag from FPGA

	.bss	interfaceGateIndex,1	; index number of the interface gate if in use
	.bss	processingFlags1,1		; flags used by signal processing functions

	.bss	wallStartGateIndex,1	; index number of the wall start gate if used
	.bss	wallStartGateInfo,1		; pointer to wall start gate info
	.bss	wallStartGateResults,1	; pointer to wall start gate results
	.bss	wallStartGateLevel,1	; level of the wall start gate stored for quick access

	.bss	wallEndGateIndex,1		; index number of the wall end gate if used
	.bss	wallEndGateInfo,1		; pointer to wall end gate info
	.bss	wallEndGateResults,1	; pointer to wall end gate results
	.bss	wallEndGateLevel,1		; level of the wall end gate stored for quick access

	.bss	scratch1,1				; scratch variable for any temporary use
	.bss	scratch2,1				; scratch variable for any temporary use
	.bss	scratch3,1				; scratch variable for any temporary use
	.bss	scratch4,1				; scratch variable for any temporary use
	.bss	scratch5,1				; scratch variable for any temporary use

	;---------------------------------------------------------------------------------
	; Wall Peak Buffer Notes
	;
	; This buffer holds data for the crossing points of the two gates used
	; to calculate the wall thickness.  The data for the positions
	; representing the thinnest and the thickest wall are stored.
	;
	; With 66 MHz sampling, the period between samples is 15 ns, or
	; 0.015 us.  Assuming the speed of sound in steel is 0.233 inches/us,
	; 15 ns gives a resolution of 0.003495 inches.  Since the measurement
	; is divided by two to account for the round trip sound path, the
	; resolution is twice as good.
	;
	; To improve the resolution, a previous code version extrapolated
	; a more exact gate crossing position.  This was more complicated
	; than useful and was removed.  In Git, see the commit tagged
	; VersionWithFractionalMathForThickness for that version.
	;
	; The min and max peak distances between the gate crossings are stored
	; and passed back when the host requests.
	;
	; Each new measurement is compared with the min and max peaks. If
	; the distance for the new value is not equal to the old stored
	; peak, a new min or max peak is stored as appropriate.
	;
	; word  0:	current value - whole number distance between crossovers
	; word  1:	current value - numerator first crossover
	; word  2:	current value - denominator first crossover
	; word  3:	current value - numerator second crossover
	; word  4:	current value - denominator second crossover
	;
	; word  5:	max peak - whole number distance between crossovers
	; word  6:	max peak - numerator first crossover
	; word  7:	max peak - denominator first crossover
	; word  8:	max peak - numerator second crossover
	; word  9:	max peak - denominator second crossover
	; word 10:	max peak - tracking location
	;
	; word 11:	min peak - whole number distance between crossovers
	; word 12:	min peak - numerator first crossover
	; word 13:	min peak - denominator first crossover
	; word 14:	min peak - numerator second crossover
	; word 15:	min peak - denominator second crossover
	; word 16:	min peak - tracking location
	;
	; word 17:	current value - normalized numerator first crossover
	; word 18:	current value - normalized denominator first crossover
	; word 19:	current value - normalized numerator second crossover
	; word 20:	current value - normalized denominator second crossover
	;
	; word 21:	max peak - normalized numerator first crossover
	; word 22:	max peak - normalized denominator first crossover
	; word 23:	max peak - normalized numerator second crossover
	; word 24:	max peak - normalized denominator second crossover
	;
	; word 25:	min peak - normalized numerator first crossover
	; word 26:	min peak - normalized denominator first crossover
	; word 27:	min peak - normalized numerator second crossover
	; word 28:	min peak - normalized denominator second crossover
	;

	.bss	wallPeakBuffer, 29

	;---------------------------------------------------------------------------------

	;---------------------------------------------------------------------------------
	; Gate Info Buffer Notes
	;
	; The gatesBuffer section is for storing 10 gates.
	; Each gate is defined by the data words below:
	;
	; word  0: first gate ID number
	;           (upper two bits used to store pointer to next averaging buffer)
	; word  1: gate function flags (see below)
	; word  2: gate start location MSW
	; word  3: gate start location LSW
	; word  4: gate adjusted start location
	; word  5: gate width / 3
	; word  6: gate level
	; word  7: gate hit count threshold (number of consecutive violations before flag)
	; word  8: gate miss count threshold (number of consecutive non-violations before flag)
	; word  9: Threshold 1
	; word 10: unused
	; word 11: unused
	; word 12: unused
	; word 13: unused
	; word 0: second gate ID number
	; word 1: ...
	;	...remainder of the gates...
	;
	; WARNING: if you add more entries to this buffer, you must adjust
	;           GATE_PARAMS_SIZE constant.
	;
	; All values are defined in sample counts - i.e a width of 3 is a width
	; of 3 A/D sample counts.
	;
	; If interface tracking is off, the start position is based from the
	; initial pulse.  Since the FPGA delays the start of sample collection
	; based upon the "hardware delay" set by the host, this delay must
	; be accounted for by subtracting it from each gate start so they
	; are correct in relation the beginning of the data set.  The adjusted
	; values are updated with each pulsing of the transducers to account
	; for any changes which may have been made to the variable hardwareDelay
	; by the host.  Note that the hardwareDelay value should match the
	; value set in the FPGA.
	;
	; If interface tracking is on, the start position is based from the
	; first point where the signal rises above the interface gate.  After
	; each transducer pulse, the interface crossing is detected and added
	; to each gate's location and stored in each gate's "adjusted" variable.
	;
	; Bit assignments for the Gate Function flags:
	;
	; bit 0 :	0 = gate is inactive
	; 			1 = gate is active
	; bit 1 :	0 = no report on does NOT exceed
	;			1 = report if signal does NOT exceed gate
	;			(useful for loss of interface or backwall detection)
	; bit 2 :	0 = flag if signal greater than gate (max gate)
	;			1 = flag if signal less than gate (min gate)
	;			(see Caution 1 below)
	; bit 3:	0 = not a wall measurement gate
	;			1 = used as first gate for wall measurement
	; bit 4:	0 = not a wall measurement gate
	;			1 = used as second gate for wall measurement
	; bit 5:	0 = do not search for signal crossing
	;			1 = search for signal crossing
	; bit 6:	0 = gate does not use interface tracking
	;			1 = gate uses interface tracking
	;			(ignored for interface gate; it never tracks)
	; bit 7:	0 = do not search for a peak
	;			1 = search for a peak
	; bit 8:	0 = this is not the interface gate
	;			1 = this is the interface gate
	; bit 9:	0 = do not integrate above gate level
	;			1 = integrate signal above gate level
	; bit 10:	0 = do not quench signal on signal over limit
	;			1 = quench signal on signal over limit
	; bit 11: 	0 = this is not an AScan trigger gate
	;			1 = AScan sent if this gate exceeded (must have peak search enabled)
	; bit 12:	0 = subsequent differential noise cancellation inactive
	;			1 = subsequent differential noise cancellation active
	; bit 13:	unused
	; bit 14:	lsb - gate data averaging buffer size
	; bit 15:	msb - gate data averaging buffer size
	;
	; Caution 1: the GATE_MAX_MIN bit in the gate flag above matches the
    ;            GATE_MAX_MIN flag position in the gate results buffer
	;            flags below so that the bit can easily be copied from the
    ;            former to the latter before sending peak data to the host
	;			 DO NOT MOVE without adjusting all code as necessary.
	;

	.bss	gateBuffer, GATE_PARAMS_SIZE * 10;

	;---------------------------------------------------------------------------------

	;---------------------------------------------------------------------------------
	; Gate Results Buffer Notes
	;
	; The gateResultsBuffer section is for storing the data collected
	; for 10 gates.
	; Each gate is defined by the data words below:
	;
	; word 0: first gate ID number
	; word 1: gate result flags (see below)
	; word 2: not used
	; word 3: level exceeded count
	; word 4: level not exceeded count
	; word 5: signal before exceeding
	; word 6: signal before exceeding buffer address
	; word 7: signal after exceeding
	; word 8: signal after exceeding buffer address
	; word 9: peak in the gate (max for a max gate, min for a min)
	; word 10: peak buffer address
	; word 11: peak tracking location
	; word 12: gate peak value from previous data set
	; word 0: second gate ID number
	; word 1: ...
	;	...remainder of the gates...
	;
	; WARNING: if you add more entries to this buffer, you must adjust the
	;           GATE_RESULTS_SIZE constant.
	;
	; Bit assignments for the Gate Result flags:
	;
	; bit 0 :	0 = no signal exceeded gate more than hitCount threshold times consecutively
	;			1 = signal exceeded gate more than hitCount threshold times consecutively
	; bit 1 :	0 = signal did not miss gate more than allowed limit
	;			1 = signal failed to exceed gate more than missCount times consecutively
	; bit 2:	0 = max gate, higher values are worst case
	;			1 = min gate, lower values are worst case
	;			(see Caution 1 above)
	; bit 3:	0 = signal did not exceed the gate level per max/min setting
	;			1 = signal did exceed the gate level per max/min setting
	;
	; Notes:
	;
	; Bit 0 is to flag if the signal exceeded the gate a certain number of times.  It is only set if
	; the violation occurred more than hitCount times in a row.  This flag
	; typically catches flaw indications.
	;
	; Bit 1 is to flag if the signal has not exceeded the gate a certain number of times. It is only set
	; if failure to exceed occurred more than missCount times in a row.  This
	; is typically used to detect loss of interface or loss of backwall.
	;
	; Every time the signal does not exceed the gate, hitCount is reset.
	; Every time the signal does exceed the gate, missCount is reset
	;
	; NOTE NOTE NOTE
	;
	; Each core processes every other transducer pulse, so a hitCount of
	; two requires only that violations occur on shots 1 and 3 with the
	; second and forth shot being handled by another DSP.
	;

	.bss	gateResultsBuffer, GATE_RESULTS_SIZE * 10

	;---------------------------------------------------------------------------------

	;---------------------------------------------------------------------------------
	; DAC Buffer Notes
	;
	; The dacBuffer section is for storing 10 DAC sections (also called
    ; gates). Each section is defined by 9 words each:
	;
	; The DAC sections define the gain multiplier to be applied to each
	; section of the sample data set.  The start positions are handled the
	; same as for the gates.  The sections allow the signal amplitude to
	; be set to different values along the timeline.
	;
	; word 0: first section ID number
	; word 1: section function flags
	; word 2: section start location MSB
	; word 3: section start location LSB
	; word 4: section adjusted start location
	; word 5: section width
	; word 6: section gain
	; word 7: unused
	; word 8: unused
	; word 0: second section ID number
	; word 1: ...
	;	...remainder of the gates...
	;
	; WARNING: if you add more entries to this buffer, you must adjust the
	;           DAC_PARAMS_SIZE constant.
	;
	; All values are defined in sample counts - i.e a width of 3 is a width
	; of 3 A/D sample counts.
	;
	; This section's operation with Interface Tracking is identical to that
	; of the gates - see "Gate Buffer Notes" above for details.
	;
	; Bit assignments for the Section Function flags:
	;
	; bit 0 :	0 = section is inactive
	; 			1 = section is active
	;

	.bss	dacBuffer, DAC_PARAMS_SIZE * 10

	;---------------------------------------------------------------------------------

	;---------------------------------------------------------------------------------
	; FIR Filter Buffer
	;
	; Convolution buffer for the FIR filter. Add 1 to account for the value shifted
	; out the bottom of the buffer during each convolution.
	;
	
	.bss	firBuffer, MAX_NUM_COEFFS + 1

	;---------------------------------------------------------------------------------

	;---------------------------------------------------------------------------------
	; Processor Stack
	;

	.bss	stack, 99			; the stack is set up here
	.bss	endOfStack,	1       ; code sets SP here on startup
								; NOTE: you can have plenty of stack!
								;   The PIC micro-controller has the limited
								;   stack space, not the C50!

	;---------------------------------------------------------------------------------

	;---------------------------------------------------------------------------------
	; Debugger Variables
	;
	; Variables used for debugging, especially with the on-board debugger code.
	;
	; Register contents are stored in the block beginning at debuggerVariables in
	; the following order:
	;
	; debugStatusFlags
	; AG_Register
	; AH_Register
	; AL_Register
	; BG_Register
	; BH_Register
	; BL_Register
	;
	; ST0_Register
	; ST1_Register
	;
	; PMST_Register
	;
	; AR0_Register
	; AR1_Register
	; AR2_Register
	; AR3_Register
	; AR4_Register
	; AR5_Register
	; AR6_Register
	; AR7_Register
	;

	.bss	debuggerVariables, DEBUGGER_VARIABLES_BUFFER_SIZE

	; end of Debugger Variables
	;---------------------------------------------------------------------------------

; NOTE: Various buffers are defined at 3000h and up (see above) - be careful about
;       assigning variables past that point.

; end of Variables
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
;  Variables on Page ? - uninitialized
;
; Variables on page other than 0. Uses .usect to create a new section that
; can overlay addresses already used by .bss. These are on a different memory
; page, so the data locations don't overlap.
;
; The .usect directive is used as it is functionally equivalent to .bss but
; creates a separate address space.
;

example .usect "varpage2", 2

; end of Variables on Page ?
;-----------------------------------------------------------------------------

	.data

;-----------------------------------------------------------------------------
; Data - initialized

Data	.word	55aah			; used to mark the first page of data

; coeffs1 is the list of coefficients for the signal FIR filter
; 32 words are reserved to allow 8 packets of 4 words each to be stored
; these values are replaced by the program with values sent from the host
; the values are overwritten using a DMA channel, the only way to write to
; program memory

coeffs1	.word	55h,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0aah

; end of Variables
;-----------------------------------------------------------------------------

	.text

;-----------------------------------------------------------------------------
; setupDMA
;
; Sets up DMA channels.
;
; See manual "TMS320C54x Volume 5 Enhanced Peripherals spru302b" for details.
;
; CAUTION: Using multiple DMA channels can cause issues. See note at the
; top of the file title "Multiple DMA Channels Issue" for details.
;

setupDMA:

	; setup channel 1 to store data from McBSP1 to a buffer

	call	setupDMA1

	; setup channel 2 to send data from a buffer to McBSP1

	call	setupDMA2

	; setup channel 3 to write data to the program memory

	call	setupDMA3


	; setup registers common to all channels

	stm #0100011000000010b, DMPREC

	;0~~~~~~~~~~~~~~~ (FREE) DMA stops on emulation stop
	;~1~~~~~~~~~~~~~~ (IAUTO) set for '5441 to use separate reload registers
	;~~0~~~~~~~~~~~~~ (DPRC[5]) Channel 5 low priority
	;~~~0~~~~~~~~~~~~ (DPRC[4]) Channel 4 low priority
	;~~~~0~~~~~~~~~~~ (DPRC[3]) Channel 3 low priority
	;~~~~~1~~~~~~~~~~ (DPRC[2]) Channel 2 high priority
	;~~~~~~1~~~~~~~~~ (DPRC[1]) Channel 1 high priority
	;~~~~~~~0~~~~~~~~ (DPRC[0]) Channel 0 low priority
	;~~~~~~~~00~~~~~~ (INTOSEL) N/A here as interrupts are disabled
	;~~~~~~~~~~0~~~~~ (DE[5]) Channel 5 disabled
	;~~~~~~~~~~~0~~~~ (DE[4]) Channel 4 disabled
	;~~~~~~~~~~~~0~~~ (DE[3]) Channel 3 disabled (enabled when time to send)
	;~~~~~~~~~~~~~0~~ (DE[2]) Channel 2 disabled (enabled when time to send)
	;~~~~~~~~~~~~~~1~ (DE[1]) Channel 1 enabled
	;~~~~~~~~~~~~~~~0 (DE[0]) Channel 0 disabled

	; Note - The basic *54x used a common set of reload registers for all
	; channels. The TMS320VC5441 has separate reload registers for each channel.
	; To enable the use of the separate registers set bit 14 (IAUTO) of DMPREC.

	ret

; end of setupDMA
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setupDMA1 (DMA Channel 1 transfer from McBSP1)
;
; This function prepares DMA Channel 1 to transfer data received on the
; McBSP1 serial port to a circular buffer.
;
; See manual "TMS320C54x Volume 5 Enhanced Peripherals spru302b" for details.
;
; Transfer mode: ABU non-decrement
; Source Address: McBSP1 receive register (DRR11)
; Destination buffer: SERIAL_PORT_RCV_BUFFER (in data space)
; Sync event: McBSP1 receive event
; Channel: DMA channel #1
;
; CAUTION: Using multiple DMA channels can cause issues. See note at the
; top of the file title "Multiple DMA Channels Issue" for details.
;

setupDMA1:

	stm		DMSRC1, DMSA			;set source address to DRR11
	stm		DRR11, DMSDN

	stm		DMDST1, DMSA			;set destination address to buffer
	stm		#SERIAL_PORT_RCV_BUFFER, DMSDN

	stm		DMCTR1, DMSA			;set buffer size
	stm		#SERIAL_PORT_RCV_BUFSIZE, DMSDN

	stm		DMSFC1, DMSA
	stm		#0101000000000000b, DMSDN

	;0101~~~~~~~~~~~~ (DSYN) McBSP1 receive sync event
	;~~~~0~~~~~~~~~~~ (DBLW) Single-word mode
	;~~~~~000~~~~~~~~ Reserved
	;~~~~~~~~00000000 (Frame Count) Frame count is not relevant in ABU mode

	stm		DMMCR1, DMSA
	stm		#0001000001001101b, DMSDN

	;0~~~~~~~~~~~~~~~ (AUTOINIT) Autoinitialization disabled
	;~0~~~~~~~~~~~~~~ (DINM) DMA Interrupts disabled
	;~~0~~~~~~~~~~~~~ (IMOD) Interrupt at full buffer
	;~~~1~~~~~~~~~~~~ (CTMOD) ABU (circular buffer) mode
	;~~~~0~~~~~~~~~~~ Reserved
	;~~~~~000~~~~~~~~ (SIND) No modify on source address (DRR11)
	;~~~~~~~~01~~~~~~ (DMS) Source in data space
	;~~~~~~~~~~0~~~~~ Reserved
	;~~~~~~~~~~~011~~ (DIND) Post increment destination address with DMIDX0 *note
	;~~~~~~~~~~~~~~01 (DMD) Destination in data space

	; *note - the basic *54x used DMIXD0 to specify the increment for ALL channels
	; the TMS320VC5441 has a separate increment register for each channel - to
	; enable the use of the separate increments set bit 14 (IAUTO) of DMPREC

	stm		DMIDX0, DMSA			;set element address index to +1
	stm		#0001h, DMSDN

	.newblock						; allow re-use of $ variables

; setupDMA1 (DMA Channel 1 transfer from McBSP1)
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setupDMA2 (DMA Channel 2 transfer to McBSP1)
;
; This function prepares DMA Channel 2 to transfer data from a buffer to the
; McBSP1 serial port.
;
; See manual "TMS320C54x Volume 5 Enhanced Peripherals spru302b" for details.
;
; Transfer mode: Multiframe mode
; Source Address: SERIAL_PORT_XMT_BUFFER (data space)
; Destination buffer: McBSP1 transmit register (DXR11)
; Sync event: free running
; Channel: DMA channel #2
;
; CAUTION: Using multiple DMA channels can cause issues. See note at the
; top of the file title "Multiple DMA Channels Issue" for details.
;

setupDMA2:

	stm		DMSRC2, DMSA			;set source address to buffer
	stm		#SERIAL_PORT_XMT_BUFFER, DMSDN

	stm		DMDST2, DMSA			;set destination address to DXR11
	stm		DXR11, DMSDN

	stm		DMCTR2, DMSA			;set element transfer count (this gets
	stm		#0h, DMSDN				; adjusted for each type of packet)

	stm		DMSFC2, DMSA
	stm		#0110000000000000b, DMSDN

	;0110~~~~~~~~~~~~ (DSYN) McBSP1 transmit sync event
	;~~~~0~~~~~~~~~~~ (DBLW) Single-word mode
	;~~~~~000~~~~~~~~ Reserved
	;~~~~~~~~00000000 (Frame Count) 1 frame (desired count - 1)

	stm		DMMCR2, DMSA
	stm		#0000000101000001b, DMSDN

	;0~~~~~~~~~~~~~~~ (AUTOINIT) Autoinitialization disabled - *see note below
	;~0~~~~~~~~~~~~~~ (DINM) DMA Interrupts disabled
	;~~0~~~~~~~~~~~~~ (IMOD) Interrupt at full buffer
	;~~~0~~~~~~~~~~~~ (CTMOD) Multiframe mode
	;~~~~0~~~~~~~~~~~ Reserved
	;~~~~~001~~~~~~~~ (SIND) post increment source address after each transfer
	;~~~~~~~~01~~~~~~ (DMS) Source in data space
	;~~~~~~~~~~0~~~~~ Reserved
	;~~~~~~~~~~~000~~ (DIND)  No modify on destination address (DXR11)
	;~~~~~~~~~~~~~~01 (DMD) Destination in data space


	; Note regarding Autoinitialization
	;  AutoInit cannot be used to just reload the registers as it also restarts
	;  another transfer.  The TI manual only says that it reloads registers.
	;  The DE bit will transition briefly at the end of the block, but this
	;  can be hard to catch.  When AutoInit is off, the DMA sets the DE (disable)
	;  bit off at the end of the block transfer and ceases operation.

	.newblock                       ; allow re-use of $ variables

; setupDMA2 (DMA Channel 2 transfer to McBSP1)
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setupDMA3 (DMA Channel 3 write to Program Memory)
;
; This function prepares DMA Channel 3 to write to the program memory.
; While the '54x has several instructions for writing to program memory,
; they cannot be used to write to shared program memory on the '5441.
; Only the DMA can write to shared memory.
;
; See manual "TMS320C54x Volume 5 Enhanced Peripherals spru302b" for details.
;
; Transfer mode: Multiframe mode
; Source Address: dma3Source variable
; Destination buffer: various program memory address
; Sync event: free running
; Channel: DMA channel #3
;
; IMPORTANT NOTE:
;
; Only Core A and Core C can write to the program memory in MPAB0 and MPCD0
; due to the design of the DMA addressing.
;
; See "DMA Addressing" section in the notes at the top of this file for
; more details.
;
; CAUTION: Using multiple DMA channels can cause issues. See note at the
; top of the file title "Multiple DMA Channels Issue" for details.
;

setupDMA3:

	stm		DMSRC3, DMSA            ;set source address to dma3Source
	stm		#dma3Source, DMSDN

	stm		DMDST3, DMSA            ;set destination address to 0x7fff
	stm		#0x7fff, DMSDN          ; (code should set this as desired
									;  before initiating a transfer)

	stm		DMCTR3, DMSA            ;set element transfer count (this
	stm		#0h, DMSDN              ; can be adjusted for each transfer,
									; starts with 0 which is 1 element)

	stm		DMSFC3, DMSA
	stm		#0000000000000000b, DMSDN

	;0000~~~~~~~~~~~~ (DSYN) No sync event
	;~~~~0~~~~~~~~~~~ (DBLW) Single-word mode
	;~~~~~000~~~~~~~~ Reserved
	;~~~~~~~~00000000 (Frame Count) 1 frame (desired count - 1)

	stm		DMMCR3, DMSA
	stm		#0000000001000100b, DMSDN

	;0~~~~~~~~~~~~~~~ (AUTOINIT) Autoinitialization disabled - *see note below
	;~0~~~~~~~~~~~~~~ (DINM) DMA Interrupts disabled
	;~~0~~~~~~~~~~~~~ (IMOD) Interrupt at full buffer
	;~~~0~~~~~~~~~~~~ (CTMOD) Multiframe mode
	;~~~~0~~~~~~~~~~~ Reserved
	;~~~~~000~~~~~~~~ (SIND) No modify on source address
	;~~~~~~~~01~~~~~~ (DMS) Source in data space
	;~~~~~~~~~~0~~~~~ Reserved
	;~~~~~~~~~~~001~~ (DIND) Post increment destination address (see note 1 below)
	;~~~~~~~~~~~~~~00 (DMD) Destination in program space

; Note 1
; Post increment does not seem to work when transferring one word at at time.
; Seems to be used to increment between words when multiple words sent in one block.


	; set all source and destination data and memory page pointers
	; to zero in case transfers are made in both directions

	stm		DMSRCP, DMSA    ; DMA source program memory page 0
	stm		#0, DMSDN       ; (common to all channels)

	stm		DMDSTP, DMSA    ; DMA destination program memory page 0
	stm		#0, DMSDN       ; (common to all channels)

	stm		DMSRCDP3, DMSA  ; DMA source data memory page 0
	stm		#0, DMSDN       ; (applies only to this channel)

	stm		DMDSTDP3, DMSA  ; DMA destination data memory page 0
	stm		#0, DMSDN       ; (applies only to this channel)


	; Note regarding Autoinitialization
	;  AutoInit cannot be used to just reload the registers as it also restarts
	;  another transfer.  The TI manual only says that it reloads registers.
	;  The DE bit will transition briefly at the end of the block, but this
	;  can be hard to catch.  When AutoInit is off, the DMA sets the DE (disable)
	;  bit off at the end of the block transfer and ceases operation.

	.newblock                       ; allow re-use of $ variables

; setupDMA3 (DMA Channel 3 write to Program Memory)
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setupSerialPort (McBSP1)
;
; This function prepares the McBSP1 serial port for use.
;

setupSerialPort:

; set up serial port using the following registers:
;
; Serial Port Control Register 1 (SPCR1)
; Serial Port Control Register 2 (SPCR2)
; Pin Control Register (PCR)
;


; The McBSP registers are not directly accessible.  They are reached
; using sub-addressing - the sub-address of the desired register is
; first stored in SPSA[0-2] and the register is read or written via
; SPSD[0-2] where [0-2] specifies McBSP0, McBSP1, or McBSP2


; Serial Port Control Register 1 (SPCR1)
;
; bit 	15	  = 0 		: RW - Digital loop back mode disabled
; bits	14-13 = 00		: RW - Right justify and zero-fill MSBs in DRR[1,2]
; bits	12-11 = 00		: RW - Clock stop mode is disabled
; bits  10-8  = 000		: R  - reserved
; bit	7	  = 0		: RW - DX enabler is off (delays hi-z to on time for 1st bit)
; bit	6	  = 0		: RW - A-bis mode is disabled
; bit	5-4	  = 00		: RW - RINT interrupt driven by RRDY (end of word)
; bit	3	  = ?		: RW - Rcv sync error flag - write a 0 to clear it
; bit	2	  = ?		: R  - Overrun error flag, possible data loss
; bit	1	  = ?		: R  - Data ready to be read from DDR flag = 1
; bit 	0	  = 0		: RW - Port receiver in reset = 0
;

	stm		#SPCR1, SPSA1			; point subaddressing register
	stm		#00h, SPSD1				; store value in the desired register

; Serial Port Control Register 2 (SPCR2)
;
; bits 	15-10 = 000000	: R  - Reserved
; bit 	9	  = 0		: RW - Free run disabled (used by emulator tester)
; bit 	8	  = 0		: RW - SOFT mode disabled (used by emulator tester)
; bit	7	  = 0		: RW - Frame sync not generated internally so disable
; bit	6	  = 0		: RW - Sample rate generator not used so disable
; bits	5-4	  = 00		: RW - XINT interrupt driven by XRDY (end of word)
; bit	3	  = ?		: RW - Xmt sync error flag - write a 0 to clear it
; bit	2	  = ?		: R  - Transmit shift register is empty (underrun)
; bit	1	  = ?		: R  - Transmitter is ready for new data = 1
; bit	0	  = 0		: WR - Port transmitter in reset = 0
;
; Xmt and Rcv clocks and Frame signals are generated externally so FRST (bit 7)
; and GRST (bit 6) are set 0 to keep them in reset and disabled.  On page 2-24
; of the data manual, a GRST flag is described as being in SRGR2 - there is
; no such flag in that register and apparently the GRST flag in the SPCR2 register
; is what was intended.  The statement "If you want to reset the sample rate
; generator when neither the transmitter nor the receiver is fed by..." is
; misleading - it means that you can disable it by putting it in reset.  Otherwise,
; why would you need to reset it if it is not being used?
;

	stm		#SPCR2, SPSA1			; point subaddressing register
	stm		#00h, SPSD1				; store value in the desired register

; Pin Control Register (PCR)
;
; bits 	15-14 = 00		: R  - Reserved
; bit 	13	  = 0		: RW - DX, FSX, CLKX used for serial port and not I/O
; bit	12	  = 0		: RW - DR, FSR, CLKR, CLKS used for serial port and not I/O
; bit	11	  = 0		: RW - Xmt Frame Sync driven by external source
; bit	10	  = 0		: RW - Rcv Frame Sync driven by external source
; bit	9	  = 0		: RW - Xmt Clock driven by external source
; bit	8	  = 0		: RW - Rcv Clock driven by external source
; bit	7	  = 0		: R  - Reserved
; bit	6	  = ?		: R  - CLKS pin status when used as an input
; bit	5	  = ?		: R  - DX pin status when used as an input
; bit	4	  = ?		: R  - DR pin status when used as an input
; bit	3	  = 0		: RW - Xmt Frame Sync pulse is active high
; bit	2	  = 0		: RW - Rcv Frame Sync pulse is active high
; bit	1	  = 0		: RW - Xmt data output on rising edge of CLKX
; bit	0	  = 0		: RW - Rcv data sampled on falling edge of CLKR
;

	stm		#PCR, SPSA1				; point subaddressing register
	stm		#00h, SPSD1				; store value in the desired register


; set up receiver using the following registers:
;
; Receive Control Register 1 (RCR1)
; Receive Control Register 2 (RCR2)

; Receive Control Register 1 (RCR1)
;
; bit	15	  = 0		: R  - Reserved
; bits 	14-8  = 0000000	: RW - Rcv frame 1 length = 1 word
; bits	7-5	  = 000		: RW - Rcv word length = 8 bits
; bits	4-0	  = 00000	: R  - Reserved
;

	stm		#RCR1, SPSA1			; point subaddressing register
	stm		#00h, SPSD1				; store value in the desired register

; Receive Control Register 2 (RCR2)
;
; bit	15	  = 0		: RW - Single phase rcv frame
; bits	14-8  = 0000000	: RW - Rcv frame 2 length = 1 word (not used for single phase)
; bits	7-5	  = 000		: RW - Rcv word length 2 = 8 bits (not used for single phase)
; bits	4-3	  = 00		: RW - No companding, data tranfers MSB first
; bit	2	  = 0		: RW - Rcv frame sync pulses after the first restart transfer
; bits	1-0	  = 00		: RW - First bit transmitted zero clocks after frame sync

	stm     #RCR2, SPSA1		; point subaddressing register
	stm     #00h, SPSD1			; store value in the desired register


; set up transmitter using the following registers:
;
; Transmit Control Register 1 (XCR1)
; Transmit Control Register 2 (XCR2)

; Transmit Control Register 1 (XCR1)
;
; bit	15      = 0             : R  - Reserved
; bits 	14-8    = 0000000       : RW - Xmt frame 1 length = 1 word
; bits	7-5     = 000           : RW - Xmt word length = 8 bits
; bits	4-0     = 00000         : R  - Reserved
;

	stm		#XCR1, SPSA1    ; point subaddressing register
	stm		#00h, SPSD1     ; store value in the desired register

; Transmit Control Register 2 (XCR2)
;
; bit	15      = 0         : RW - Single phase xmt frame
; bits	14-8    = 0000000   : RW - Xmt frame 2 length = 1 word (not used for single phase)
; bits	7-5     = 000       : RW - Xmt word length 2 = 8 bits (not used for single phase)
; bits	4-3     = 00        : RW - No companding, data received MSB first
; bit	2       = 0         : RW - Xmt frame sync pulses after the first restart transfer
; bits	1-0     = 01        : RW - First bit transmitted one clock after frame sync
;
; The first bit is transmitted one cycle after frame sync because the sync is
; generated externally and it arrives too late to place the first bit without
; waiting for the next cycle.
;

	stm     #XCR2, SPSA1            ; point subaddressing register
	stm     #01h, SPSD1             ; store value in the desired register


	stm     #15, AR1		; wait 15 internal cpu clock cycles (10 ns each)
	banz    $, *AR1-		; to delay at least two serial port clock cycles
							; (60 ns each)


; enable receiver by setting SPCR1 bit 0 = 1

	stm     #SPCR1, SPSA1           ; point subaddressing register
	stm     #01h, SPSD1             ; store value in the desired register


; do NOT enable transmitter until a packet is received addressing to this
; particular DSP core


; prepare serial port reception by setting pointer to beginning of buffer
; and setting flags and counters

	ld      #Variables1, DP
	st      #SERIAL_PORT_RCV_BUFFER, serialPortInBufPtr

	ret

	.newblock                       ; allow re-use of $ variables

; end of setupSerialPort (McBSP1)
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; checkSerialInReady
;
; Checks to see if the number of bytes or more specified in the A register are
; available in the serial port receive circular buffer.
;
; If the specified number of bytes or more is available, B register will contain
; a value greater than or equal to zero on exit.  Otherwise B will contain a
; value less than zero:
;
; B >= 0 : number of bytes or more specified are available in buffer
; B < 0  ; number of bytes specified is not available
;

checkSerialInReady:

	ld      #Variables1, DP         ; point to Variables1 page

	stm     DMDST1, DMSA            ; get current buffer pointer
	ldm     DMSDN, B                ; (sign is not extended with ldm)

	subs    serialPortInBufPtr, B   ; subtract the last buffer position
									; processed from the current position
									; to determine the number of bytes
									; read

	bc      $1, BGEQ		; if current pointer > last processed,
							; jump to check against specified qty

	; current pointer < last processed so it has wrapped past end of the
	; circular buffer, more math to calculate number of words

	ldm     DMSDN, B		; reload current buffer pointer
							; (sign is not extended with ldm)

        ; add the buffer size to the current pointer to account for the
        ; fact that it has wrapped around

	add     #SERIAL_PORT_RCV_BUFSIZE, B

	subs    serialPortInBufPtr, B	; subtract the last buffer position
									; processed from the current position
									; to determine the number of bytes
									; read

$1:	; compare number of bytes in buffer with the specified amount in A

	sub		A, 0, B         ; ( B - A << SHIFT ) -> B
							;  (the TI manual is obfuscated on this one)

	ret

	.newblock                       ; allow re-use of $ variables

; end of checkSerialInReady
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; readSerialPort
;
; This function processes packets in the serial port receive circular buffer
; The buffer contains data transferred from the McBSP1 serial port by the
; DMA.
;
; All packets are expected to be the same length for the sake of simplicity
; and execution speed.
;
; Not all packets will be addressed to the DSP core - the serial port is
; shared amongst all 4 cores and all cores receive all packets.  Each
; packet has a core identifier to specify the target core.
;
; This function will discard any packets addressed to other cores until
; a packet is reached which is addressed to the proper core.  The function
; will then process this packet and exit. Thus only one packet addressed
; to the core will be processed while all preceding packets addressed to
; other cores will be discarded.
;
; On program start, serialPortInBufPtr should be set to the start of the buffer.
;
; Since all packets are the same length, data packet size is always the same.
;
; There is no need for processing functions to ensure that they skip past any
; unused words to the next packet -- this function always makes sure that
; pointer SerialPortInBufPtr points to the next packet.
;
; The packet to DSP format is:
;
; byte0 	= 0xaa
; byte1 	= 0x55
; byte2 	= 0xbb
; byte3 	= 0x66
; byte4 	= DSP Core identifier (1-4 for cores A-B)
; byte5 	= message identifier
; byte6 	= data packet size (does not include bytes 0-5 or checksum byte12)
; byte7 	= data byte 0
; byte8 	= data byte 1
; byte9 	= data byte 2
; byte10 	= data byte 3
; byte11	= data byte 4
; byte12	= data byte 5
; byte13	= data byte 6
; byte14	= data byte 7
; byte15	= data byte 8
; byte16 	= checksum for bytes 4-15
;

readSerialPort:

	ld      #17, A
	call    checkSerialInReady
	rc      BLT                     ; B < 0 - bytes not ready so exit

; a packet is ready, so process it

; DP already pointed to Variables1 page by checkSerialInReady function

	ld      serialPortInBufPtr, A   ; get the buffer pointer
	stlm    A, AR3
	nop								; can't use stm to BK right after stlm AR3
									; and must skip two words before using AR3
									; due to pipeline conflicts

	stm     #SERIAL_PORT_RCV_BUFSIZE, BK ; set the size of the circular buffer
	nop                             ; next word cannot use circular
									; addressing due to pipeline conflicts

; check for valid 0xaa, 0x55, 0xbb, 0x66 header byte sequence

	ldu     *AR3+%, A               ; load first byte of packet header
	sub     #0xaa, A                ; compare with 0xaa
	bc      reSync, ANEQ            ; error - reSync and bail out

	ldu     *AR3+%, A               ; load first byte of packet header
	sub     #0x55, A                ; compare with 0x55
	bc      reSync, ANEQ            ; error - reSync and bail out

	ldu     *AR3+%, A               ; load first byte of packet header
	sub     #0xbb, A                ; compare with 0xbb
	bc      reSync, ANEQ            ; error - reSync and bail out

	ldu     *AR3+%, A               ; load first byte of packet header
	sub     #0x66, A                ; compare with 0x66
	bc      reSync, ANEQ            ; error - reSync and bail out

; check if packet addressed to this core

	ldu     *+AR3(0)%, A            ; load core ID from packet
									; [ *+AR3(0)% is only way to not modify AR3 for circular buffer]
	sub     coreID, A               ; compare the address with this core's ID
	bc      $1, AEQ                 ; process the packet if ID's match

	mar     *+AR3(13)%             	; packet ID does not match DSP core ID, skip
									; to the next packet and ignore this one
	ldm     AR3, A                  ; save the buffer pointer which now points
	stl     A, serialPortInBufPtr   ; to next packet
	ret

; verify checksum

$1:	ldu     *AR3+%, A               ; reload core ID from packet
									; (this is first byte included in checksum)
	rpt     #11                     ; repeat k+1 times
	add     *AR3+%, A               ; add in all bytes which are part of the
									; checksum, including the checksum byte

	and     #0xff, A                ; mask off upper bits
	bc      reSync, ANEQ            ; checksum result not zero, toss and reSync

	ldm     AR3, A                  ; save the buffer pointer which now points
	stl     A, serialPortInBufPtr   ; to next packet


; process the packet

	;enable the serial port transmitter
	;need to do other tasks for at least 15 internal cpu clock cycles
	;(10 ns each) to delay at least two serial port clock cycles (60 ns each)

	stm     #SPCR2, SPSA1           ; point subaddressing register
	stm     #01h, SPSD1             ; store value in the desired register
									; this enables the transmitter

	orm     #TRANSMITTER_ACTIVE, processingFlags1	; set transmitter active flag

	mar	*+AR3(-12)%					; point back to packet ID

	; NOTE: the various functions are invoked with a branch rather
	; 	than a call so that they do not return to this function
	;	but instead to that which called this function.  This
	;	reduces code because the message ID in the A register is
	;	destroyed by the function being called and extra loading
	;	or branching would be required if execution returned here.

	ld      *AR3+%, A                   ; load the message ID

	sub     #DSP_GET_STATUS_CMD, 0, A, B	; B = A - (command)
	bc		getStatus, BEQ					; do command if B = 0

	sub     #DSP_SET_FLAGS1, 0, A, B    ; same comment as above for
	bc      setFlags1, BEQ              ; this entire section

	sub     #DSP_SET_GATE_SIG_PROC_THRESHOLD, 0, A, B
	bc      setGateSignalProcessingThreshold, BEQ

	sub     #DSP_SET_GAIN_CMD, 0, A, B
	bc      setSoftwareGain, BEQ

	sub     #DSP_GET_ASCAN_BLOCK_CMD, 0, A, B
	bc      getAScanBlock, BEQ

	sub     #DSP_GET_ASCAN_NEXT_BLOCK_CMD, 0, A, B
	bc      getAScanNextBlock, BEQ

	sub     #DSP_SET_AD_SAMPLE_SIZE_CMD, 0, A, B
	bc      setADSampleSize, BEQ

	sub     #DSP_SET_DELAYS, 0, A, B
	bc      setDelays, BEQ

	sub     #DSP_SET_ASCAN_RANGE, 0, A, B
	bc      setAScanScale, BEQ

	sub     #DSP_SET_GATE, 0, A, B
	bc      setGate, BEQ

	sub     #DSP_SET_GATE_FLAGS, 0, A, B
	bc      setGateFlags, BEQ

	sub     #DSP_SET_DAC, 0, A, B
	bc      setDAC, BEQ

	sub     #DSP_SET_DAC_FLAGS, 0, A, B
	bc      setDACFlags, BEQ

	sub     #DSP_SET_HIT_MISS_COUNTS, 0, A, B
	bc      setHitMissCounts, BEQ

	sub     #DSP_GET_PEAK_DATA, 0, A, B
	bc      getPeakData, BEQ

	sub     #DSP_SET_RECTIFICATION, 0, A, B
	bc      setRectification, BEQ

	sub     #DSP_GET_MAP_BLOCK_CMD, 0, A, B
	bc      getMapBlock, BEQ

	sub     #DSP_GET_MAP_COUNT_CMD, 0, A, B
	bc      getMapBufferWordsAvailableCount, BEQ

	sub     #DSP_RESET_MAPPING_CMD, 0, A, B
	bc      handleResetMappingCommand, BEQ

	sub     #DSP_SET_FILTER_CMD, 0, A, B
	bc      handleSetFilterCommand, BEQ

	ret

	.newblock                       ; allow re-use of $ variables

; end of readSerialPort
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; reSync
;
; Clears bytes from the socket buffer until 0xaa byte reached which signals
; the *possible* start of a new valid packet header or until the buffer is
; empty.
;
; Calling reSync will increment the reSyncCount variable which tracks
; number of reSyncs required.  If a reSync is not due to an error, call
; reSyncNoCount instead.
;
; On Entry:
;
; AR3 should already be loaded with the current serial in buffer pointer
; BK register should already be loaded with SERIAL_PORT_RCV_BUFSIZE
; DMSA should alread be loaded with DMDST1
;
; On Exit:
;
; If a 0xaa byte was found, serialPortInBufPtr will point to it.
; If byte not found, serialPortInBufPtr will be equal to the DMA
;  channel buffer pointer.
;

reSync:

; count number of times a reSync is required

	ld      reSyncCount, A
	add     #1, A
	stl     A, reSyncCount

reSyncNoCount:


$1:

; check if buffer processing pointer is less than DMA pointer
; stop trying to reSync when pointers match which means all available data
; has been scanned

	ldm     DMSDN, B                ; get the serial in DMA buffer pointer
									; (sign is not extended with ldm)

	ldm     AR3, A                  ; get current buffer pointer

	sub     A, 0, B                 ; ( B - A << SHIFT ) -> B
									;  (the TI manual is obfuscated on this one)

	bc      $2, BEQ                 ; pointers are same, nothing to sync

; data is available - scan for 0xaa

	ldu     *AR3+%, A               ; load next byte
	sub     #0xaa, A                ; compare with 0xaa
	bc      $1, ANEQ                ; if not 0xaa, keep scanning

	mar     *AR3-%                  ; move back to point to the 0xaa byte

$2:

	ldm     AR3, A                  ; save the buffer pointer
	stl     A, serialPortInBufPtr

	ret

	.newblock                       ; allow re-use of $ variables

; end of reSync
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; sendPacket
;
; Sends a packet via the serial port. The serial port should already have
; been enabled and the data placed in the buffer. This function sets up the
; DMA channel to start sending the data.  The serial port is then disabled
; elsewhere upon completion so that other DSP cores can use it.
;
; IMPORTANT: See responseDelay header notes for info regarding timing delays
;	required to avoid collision between the DSP cores sharing the port.
;
; On entry, data to be sent should be stored in SERIAL_PORT_XMT_BUFFER
; starting at array position 6.  The length of the data should be stored
; in the  A register, the message ID should be in the B register.
;
; The length of the data is not sent back in the packet as the message ID
; will indicate this value.
;
; This function will add header information, using packet format of:
;
; byte 0 : 00h
; byte 1 : 99h
; byte 2 : 0aah
; byte 3 : 055h
; byte 4 : DSP Core ID (1-4 for cores A-D)
; byte 5 : Message ID (matches the request message ID from the host)
; byte 6 : First byte of data
; ...
; ...
;

sendPacket:

	ld      #Variables1, DP

	stm     #SERIAL_PORT_XMT_BUFFER, AR3    ; point to start of out buffer

	stm     DMSRC2, DMSA            ;set source address to buffer
	stm     #SERIAL_PORT_XMT_BUFFER, DMSDN

	add     #5, A                   ; A contains the size of the data in the buffer
	stm     DMCTR2, DMSA            ;  adjust for the header bytes in the total
	stlm    A, DMSDN                ;  byte count and store the new value
									; in DMA channel 2 element counter
									; (the value stored is one less than the
									;  actual number of bytes to be sent as
									;  required by the DMA)

; a ffh value has already been sent to trigger the DMA transfer
; this must be followed by 00h, 99h to force the FPGA to begin storing the data

	st      #00h, *AR3+             ; trigger to FPGA to start storing
	st      #099h, *AR3+            ; trigger to FPGA to start storing
	st      #0aah, *AR3+            ; all packets start with 0xaa, 0x55
	st      #055h, *AR3+

	ld      coreID, A               ; all packets include DSP core
	stl     A, *AR3+

	stl     B, *AR3+                ; B contains the message ID

; The serial port will have been enabled for some time and preloaded with
; data value of zero - it may send this value a few times as the frame
; sync is generated by the FPGA.  The FPGA ignores all data received until
; the first 0x99 value is encountered.

; NOTE NOTE NOTE NOTE
;
; According to "TMS320VC5441 Digital Signal Processor Silicon Errata"
; manual SPRZ190B, a problem can occur when enabling a channel which
; can cause another active channel to also be enabled.  If the other
; active channel finishes and clears its DE bit at the same time as
; an ORM instruction is used to enable different channel, the ORM
; can overwrite the cleared bit for the other channel.
; Currently, this code does not have a problem because the only other
; active channel is the serial port read DMA which is always active
; anyway since it is in ABU mode.
; If another channel is used in the future, see the above listed manual
; for ways to avoid the issue.

	ld      #00, DP			; point to Memory Mapped Registers
	orm     #04, DMPREC		; use orm to set only the desired bit
	ld      #Variables1, DP

; since the DMA was disabled when the serial port was enabled, the DMA misses
; the trigger to load data - force feed a first transmit byte to get things
; started

; the FPGA looks for a 0xff, 0x00, 0x99 sequence as a signal to begin storing
; packets - the leading 0xff is transmitted here while the remaining two bytes
; of the header are included at the beginning of the packet - sending the 0xff
; here is necessary to start the DMA tranfer
; The 0xff, 0x00, 0x99 header bytes will not be stored by the FPGA.

	ld      #0ffh, A
	stlm    A, DXR11

	ret

	.newblock                       ; allow re-use of $ variables

; end of sendPacket
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; getMapBlock
;
; Returns the next 50 words (100 bytes) of the map data buffer.  The words are
; sent as bytes on the serial port, MSB first. The map buffer is circular --
; if 50 new data words are not available, the extraction pointer will pass the
; insertion pointer (and possibly wrap around to the top of the buffer) and
; old data will be returned. Calling getMapBufferWordsAvailableCount first to
; determine if there are adequate bytes available will prevent this problem.
;
; The number of words should be one less than the amount to be transferred:
;   i.e. a value of 49 returns 50 words which is 100 bytes.
;
; Outgoing packet structure:
;
; byte 0 : packet counter
; bytes 1 - 100 : map data
;

getMapBlock:

	ld      #Variables1, DP

	stm     #SERIAL_PORT_XMT_BUFFER+6, AR3  ; point to first data word after header

	ld      mapPacketCount, A               ; increment the packet counter
	add     #1, A
	stl     A, mapPacketCount

	stl     A, *AR3+                        ; store packet counter in first byte

	stm     #MAP_BLOCK_WORD_SIZE-1, AR1    	; get number of words to transfer

	ld      mapBufferExtractIndex, A ; get the buffer extract index pointer
	stlm    A, AR2
	nop								; can't use stm to BK right after stlm AR*
									; and must skip two words before using AR*
									; due to pipeline conflicts

	stm     #MAP_BUFFER_SIZE, BK 	; set the size of the circular buffer
	nop                             ; next word cannot use circular
									; addressing due to pipeline conflicts

	ld      #00, DP					; point to Memory Mapped Registers
	orm     #0001h, DMMR			; switch to MD*1 page to access the map buffer
	nop								; must skip three words before using page
	nop								; use three nops to be safe
	nop

$1:	ld		*AR2+%, A               ; load word from buffer

	stl     A, -8, *AR3+            ; store high byte in serial transmit buffer
	stl     A, *AR3+                ; low byte

	banz    $1, *AR1-               ; loop until all samples transferred

	andm    #0fffeh, DMMR			; switch back to MD*0 data page
	nop								; must skip three words before using page
	nop								; use three nops to be safe
	nop
	ld      #Variables1, DP         ; point to Variables1 page

	ldm     AR2, A                  ; save the buffer insert index pointer
	stl     A, mapBufferExtractIndex

	ld      mapBufferCount, A       ; decrement the counter to track number of
	sub     #MAP_BLOCK_WORD_SIZE, A ; words in the buffer
	stl     A, mapBufferCount

	ld      #MAP_BLOCK_WORD_SIZE, 1, A	; load block word size, shift to multiply by two
										; to calculate number of bytes
										; since this function uses MAP_BLOCK_WORD_SIZE-1
										; in the loop, MAP_BLOCK_WORD_SIZE is the actual
										; number of bytes transferred
	add     #1, A						; add one to account for packet count byte

	ld      #DSP_GET_MAP_BLOCK_CMD, B ; load message ID into B before calling

	b       sendPacket              ; send the data in a packet via serial

	.newblock                       ; allow re-use of $ variables

; end of getMapBlock
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; getAScanBlock
;
; Returns the first block of words of the AScan data buffer.  The words are
; sent as bytes on the serial port, MSB first.  The number of words to be
; transferred is specified in the requesting packet as the block size.
;
; The number of words should be one less than the amount to be transferred:
;   i.e. a value of 49 returns 50 words which is 100 bytes.
;
; Outgoing packet structure:
;
; byte 0 : current aScanScale (the scale of the compressed data)
; byte 1 : MSB of position where interface exceeds the interface gate
; byte 2 : LSB of above
; bytes 3 - 102 : AScan data
;
; The position is in A/D sample count units and is relative to the
; start of the A/D sample buffer - host must take the hardwareDelay
; value into account.
;
; On exit the current pointer is stored so the subsequent blocks can be
; retrieved using the getAScanNextBlock function.
;
; The block size is also saved so it can be used by getAScanNextBlock.
;

getAScanBlock:

	ld      #Variables1, DP

	bitf    flags1, #ASCAN_FREE_RUN	; only trigger another AScan dataset creation if in free run mode
	bc      $2, NTC

	orm     #CREATE_ASCAN, processingFlags1

$2:
	mar     *AR3+%                  ; skip past the packet size byte
	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte
	stl     A, getAScanBlockSize    ; number of data words to return with
									; each packet

;wip mks
; remove this after Rabbit code changed to send block size -- code above
; already in place to retrieve this from the request packet
	ld      #49, A
	stl     A, getAScanBlockSize
;end wip mks

	stm     #SERIAL_PORT_XMT_BUFFER+6, AR3  ; point to first data word after header

	ld      aScanScale, A                   ; store the current AScan scaling ratio
	stl     A, *AR3+                        ; in first byte of packet

	stm     #gateResultsBuffer+8, AR2		; point to the entry of gate 0 (the
											; interface gate if it is in use) which holds
											; the buffer address of the point which first
											; exceeded the interface gate
											; if the interface gate is not in use, then
											; this value should be ignored by the host

	ld      #PROCESSED_SAMPLE_BUFFER, B     ; start of buffer
	and     #0ffffh, B                      ; remove sign - pointer is unsigned

	ldu     *AR2+, A                ; load the interface crossing position
									; position is relative to the start of the
									;  buffer, so remove this offset
	sub     B, 0, A                 ; ( A - B << SHIFT ) -> A
									;  (the TI manual is obfuscated on this one)
	stl     A, -8, *AR3+            ; high byte -- store interface crossing position
	stl     A, *AR3+                ; low byte	--   in the packet for host

	stm     #ASCAN_BUFFER, AR2      ; point to processed data buffer

	ld      getAScanBlockSize, A    ; get number of words to transfer
	stlm    A, AR1

$1:
	ld      *AR2+, A                ; get next sample

	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	banz    $1, *AR1-               ; loop until all samples transferred

	ldm     AR2, A                  ; save the buffer pointer so it can be used
	stl     A, getAScanBlockPtr     ; in subsequent calls to getAScanNextBlock

	ld      getAScanBlockSize, 1, A ; load block word size, shift to multiply by two
									; to calculate number of bytes
	add     #5, A                   ; one more word (two more bytes) actually
									; transferred by the loop so add 2, three more bytes
									; are added to the packet as well so add 3 more

	ld      #DSP_GET_ASCAN_BLOCK_CMD, B ; load message ID into B before calling

	b       sendPacket              ; send the data in a packet via serial


	.newblock                       ; allow re-use of $ variables

; end of getAScanBlock
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; getAScanNextBlock
;
; Returns the next block of words of the AScan data buffer.  The words are
; sent as bytes on the serial port, MSB first.
;
; NOTE: getAScanBlock should be called prior to this function.
;
; See notes for getAScanBlock for details on the packet structure.
;
; On exit the current pointer is stored so the subsequent blocks can be
; retrieved by calling this function repeatedly.
;

getAScanNextBlock:

	ld      #Variables1, DP

	stm     #SERIAL_PORT_XMT_BUFFER+6, AR3  ; point to first data word after header

	ld      aScanScale, A                   ; store the current AScan scaling ratio
	stl     A, *AR3+                        ; in first byte of packet

	stm     #gateResultsBuffer+8, AR2		; point to the entry of gate 0 (the
											; interface gate if it is in use) which holds
											; the buffer address of the point which first
											; exceeded the interface gate
											; if the interface gate is not in use, then
											; this value should be ignored by the host

	ld      #PROCESSED_SAMPLE_BUFFER, B     ; start of buffer
	and     #0ffffh, B                      ; remove sign - pointer is unsigned

	ldu     *AR2+, A                        ; load the interface crossing position

											; position is relative to the start of the
											;  buffer, so remove this offset
	sub     B, 0, A                         ; ( A - B << SHIFT ) -> A
											;  (the TI manual is obfuscated on this one)
	stl     A, -8, *AR3+                    ; high byte -- store interface crossing position
	stl     A, *AR3+                        ; low byte	--   in the packet for host

	ld      getAScanBlockPtr, A             ; get the packet data pointer
	stlm    A, AR2

	ld      getAScanBlockSize, A            ; get number of words to transfer
	stlm    A, AR1

$1:
	ld      *AR2+, A                        ; get next sample

	stl     A, -8, *AR3+                    ; high byte
	stl     A, *AR3+                        ; low byte

	banz	$1, *AR1-                       ; loop until all samples transferred

	ldm     AR2, A                          ; save the buffer pointer so it can be used
	stl     A, getAScanBlockPtr             ; in subsequent calls to getAScanNextBlock

	ld      getAScanBlockSize, 1, A         ; load block word size, shift to multiply by two
											; to calculate number of bytes
	add		#5, A                           ; one more word (two more bytes) actually
											; transferred by the loop so add 2, three more bytes
											; are added to the packet as well so add 3 more

	ld      #DSP_GET_ASCAN_NEXT_BLOCK_CMD, B    ; load message ID into B before calling

	b       sendPacket                      ; send the data in a packet via serial

	.newblock                               ; allow re-use of $ variables

; end of getAScanNextBlock
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; sendACK
;
; Sends an acknowledgement packet back to the host.  Part of the packet
; is the low byte of the resync error count so the host can easily track
; the number of reSync errors that have occurred.
;
; IMPORTANT: See responseDelay header notes for info regarding timing delays
;	required to avoid collision between the DSP cores sharing the port.
;

sendACK:

	call    responseDelay                   ; see notes in responseDelay for info

	ld      #Variables1, DP

	stm     #SERIAL_PORT_XMT_BUFFER+6, AR3  ; point to first data word after header

	ld      reSyncCount, A

	and     #0ffh, 0, A, B                  ; store low byte
	stl     B, *AR3+

	ld      #1, A                           ; size of data in buffer

	ld      #DSP_ACKNOWLEDGE, B             ; load message ID into B before calling

	b       sendPacket                      ; send the data in a packet via serial

	.newblock                               ; allow re-use of $ variables

; end of sendACK
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; getStatus
;
; Returns the processingFlags1 word via the serial port.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

getStatus:

	ld      #Variables1, DP

	stm     #SERIAL_PORT_XMT_BUFFER+6, AR3  ; point to first data word after header

	ld      processingFlags1, A

	stl     A, -8, *AR3+                    ; high byte
	stl     A, *AR3+                        ; low byte

	ld      #2, A                           ; size of data in buffer

	ld      #DSP_GET_STATUS_CMD, B          ; load message ID into B before calling

	call    responseDelay                   ; see notes in responseDelay for info

	b       sendPacket                      ; send the data in a packet via serial

	.newblock                               ; allow re-use of $ variables

; end of getStatus
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; getMapBufferWordsAvailableCount
;
; Returns the number of words waiting extraction in the map buffer. Note that
; this will result in twice as many bytes in the FPGA buffer; that must be
; taken into account when specifying the number of bytes the FPGA is to wait
; for before signalling the Rabbit.
;
; The map buffer is circular; if the host doesn't extract data fast enough
; the buffer will wrap around and overwrite data before it can be retrieved.
; The count will continue to increase even if the buffer index wraps around.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

getMapBufferWordsAvailableCount:

	ld      #Variables1, DP

	stm     #SERIAL_PORT_XMT_BUFFER+6, AR3  ; point to first data word after header

	ld      mapBufferCount, A

	stl     A, -8, *AR3+                    ; high byte
	stl     A, *AR3+                        ; low byte

	ld      #2, A                           ; size of data in buffer

	ld      #DSP_GET_MAP_COUNT_CMD, B       ; load message ID into B before calling

	call    responseDelay                   ; see notes in responseDelay for info

	b       sendPacket                      ; send the data in a packet via serial

	.newblock                               ; allow re-use of $ variables

; end of getMapBufferWordsAvailableCount
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setFlags1
;
; Allows the host to set the flags1 variable.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

setFlags1:

	mar     *AR3+%                  ; skip past the packet size byte

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte

	ld      #Variables1, DP

	stl     A, flags1               ; store the new flags

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setFlags1
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setGateSignalProcessingThreshold
;
; Sets a value to be used by the current signal processing method for
; establishing thresholds, applying gain, choosing number of samples to
; average, etc..  Each processing method has its own use for the value.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

setGateSignalProcessingThreshold:

	; wip mks -- does nothing, needs to be completed

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setGateSignalProcessingThreshold
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setSoftwareGain
;
; Sets the gain value from data in a packet.  The signal is multiplied by
; this value and then right shifted 9 bytes to divide by 512, so:
;  Gain = softwareGain / 512.  Thus each count of the gain value multiplies
; the signal by 1/512.  To multiply the signal by 1, gain should be 512;
; to multiply by 3, gain should be 512 * 3 (1,536).  To divide the signal
; by 2, gain should be 512 / 2 (256).
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

setSoftwareGain:

	mar     *AR3+%                  ; skip past the packet size byte

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte

	ld      #Variables1, DP

	stl     A, softwareGain         ; gain multiplier

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setSoftwareGain
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setHitMissCounts
;
; Sets Hit Count and Miss Count thresholds.  The value Hit Count specifies how
; many consecutive times the signal must exceed the gate before it is flagged.
; The value Miss Count specifies how many consecutive times the signal must
; fail to exceed the gate before it is flagged.
;
; A value of zero or one means one hit or miss will cause a flag. Values
; above that are one to one - 3 = 3 hits, 4 = 4 hits, etc.
;
; Note: At first glance, it would seem that a hit count of zero would always
; trigger setting of the flag, but the code is never reached unless a peak
; exceeds the gate.  Thus, it functions basically the same as a value of 1.
; Thus, the host needs to catch the special case of zero and ignore the
; flag in that case.
;
; NOTE: Each DSP core processes every other shot of its associated
; channel. So a hit count of 1 will actually flag if shot 1 and shot 3
; are consecutive hits, with shots 2 and 4 being handled by another
; core in the same fashion.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

setHitMissCounts:

	ld      #Variables1, DP

	mar     *AR3+%                  ; skip past the packet size byte

	ld      *AR3+%, A               ; load the gate index number
	call    pointToGateInfo         ; point AR2 to info for gate in A

	mar     *+AR2(+6)               ; skip to the hit count entry

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte

	stl     A, *AR2+                ; Hit Count threshold

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte

	stl     A, *AR2+                ; Miss Count threshold

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setHitMissCounts
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setRectification
;
; Sets the signal rectification to one of the following for the value in
; the first data byte of the packet:
;
; 0 = Positive half and RF (host computer shifts by half screen for RF)
; 1 = Negative half
; 2 = Full
;
; The code is modified to change an instruction in the sample processing
; loop to perform the necessary rectification.  The code modification is
; used instead of a switch in the loop because the loop is very time
; critical.
;
; DMA channel 3 is used to write the opcodes to program memory.
; While the '54x has several instructions for writing to program memory,
; they cannot be used to write to shared program memory on the '5441.
; Only the DMA can write to shared memory.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;
; NOTE:
;
; Only Core A and Core C can write to the program memory in MPAB0 and MPCD0
; due to the design of the DMA addressing. Since A/B share a channel and
; C/D share a channel, they always have the same settings so it works fine
; to only have A/C modify the shared code for each pair.
;
; If the core is B or D (coreID variable = 2 or 4), this function exits
; without action to prevent writing to pages MPAB2 or MPCD2.
;
; See "DMA Addressing" section in the notes at the top of this file for
; more details.
;
; CAUTION: Using multiple DMA channels can cause issues. See note at the
; top of the file title "Multiple DMA Channels Issue" for details.
;

setRectification:

	ld      #Variables1, DP

	bitf	coreID, #01h			; check core, only A or C can modify, exit if B or D
	rc		NTC						; core id = 1/2/3/4, B&D will have bit 0 cleared

	mar     *AR3+%                  ; skip past the packet size byte

	ld      *AR3+%, A               ; get rectification selection

; choose the appropriate instruction code for the desired rectification

	st      #0f495h, dma3Source     ; opcode for NOP - for RF_WAVE/POS_HALF
									; this will be default used if rectification
									; code is invalid

	sub     #POSITIVE_HALF, 0, A, B	; B = A - (command)
	bc      $3, BNEQ                ; skip if B != 0
	st      #0f495h, dma3Source     ; opcode for NOP - for Pos Half Wave
	b       $6

$3:	sub     #NEGATIVE_HALF, 0, A, B	; B = A - (command)
	bc      $4, BNEQ                ; skip if B != 0
	st      #0f484h, dma3Source     ; opcode for NEG A - for Neg Half Wave
	b       $6

$4:	sub     #FULL_WAVE, 0, A, B     ; B = A - (command)
	bc      $5, BNEQ                ; skip if B != 0
	st      #0f485h, dma3Source     ; opcode for ABS A - for Full Wave
	b       $6

$5:	sub     #RF_WAVE, 0, A, B	; B = A - (command)
	bc      $6, BNEQ                ; skip if B != 0
	st      #0f495h, dma3Source     ; opcode for NOP - for RF_WAVE (same as POS_HALF)

$6:	stm     DMDST3, DMSA            ; set destination address to position of first
	stm     #rect1, DMSDN           ; instruction which needs to be changed
	call	runAndWaitOnDMA3		; in the sample processing loop

	stm     DMDST3, DMSA            ; set destination address to position of second
	stm     #rect2, DMSDN           ; instruction which needs to be changed
	call	runAndWaitOnDMA3		; in the sample processing loop

	stm     DMDST3, DMSA            ; set destination address to position of second
	stm     #rect3, DMSDN           ; instruction which needs to be changed
	call	runAndWaitOnDMA3		; in the sample processing loop

	stm     DMDST3, DMSA            ; set destination address to position of second
	stm     #rect4, DMSDN           ; instruction which needs to be changed
	call	runAndWaitOnDMA3		; in the sample processing loop

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setRectification
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; runAndWaitOnDMA3
;
; Starts DMA channel 3 and waits for it to complete the transfer.
;
; On exit, DP will be set to 0x00.
;

runAndWaitOnDMA3:

	ld      #00, DP

	orm     #08h, DMPREC            ; use orm to set only the desired bit
									; orm to memory mapped reg requires DP = 0

$1:	bitf    DMPREC, #08h            ; loop until DMA disabled
	bc      $1, TC                  ; AutoInit is disabled, so DMA clears this
									; enable bit at the end of the block transfer
	ret

	.newblock

; end of runAndWaitOnDMA3
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setADSampleSize
;
; Sets the size of the data set which will be transferred into RAM via the
; HPI bus by the FPGA.  The FPGA will collect this many samples but will
; actually transfer half as many words because it packs two byte samples
; into each word transferred.  After the DSP unpacks the incoming buffer
; into the working buffer, the working buffer will have adSampleSize number
; of words - the lower byte of each containing one sample.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

setADSampleSize:

	mar     *AR3+%                  ; skip past the packet size byte

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte

	ld      #Variables1, DP

	stl     A, adSampleSize         ; number of samples

	stl     A, -1, adSamplePackedSize   ; number of words transferred in by
										; the FPGA - two samples per word so
										; divide by two

	; add the size of the packed buffer stored by the FPGA to the start of
	; the buffer to calculate the end of the buffer

	ld      adSamplePackedSize, A

	add     #FPGA_AD_SAMPLE_BUFFER, A

	stl     A, fpgaADSampleBufEnd   ; end of the buffer where FPGA stores samples

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setADSampleSize
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; handleResetMappingCommand
;
; Processes request from host to reset the mapping variables.
;
; No data in the command packet is used in this function.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

handleResetMappingCommand:

	call	resetMapping

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of handleResetMappingCommand
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; handleSetFilterCommand
;
; Processes request from host to set the signal filter variables.
;
; The first byte after the command byte is the Descriptor Code which describes
; the values contained in the packet:
;
;  00: the following byte contains the number of filter coefficients
;      the byte after that contains the right bit shift amount for scaling
;  01: the following 8 bytes contain the first set of four coefficient words
;  02: the following 8 bytes contain the second set of four coefficient words
;  03: the following 8 bytes contain the third set of four coefficient words
;  04: the following 8 bytes contain the fourth set of four coefficient words
;  05: the following 8 bytes contain the fifth set of four coefficient words
;  06: the following 8 bytes contain the sixth set of four coefficient words
;  07: the following 8 bytes contain the seventh set of four coefficient words
;  08: the following 8 bytes contain the eighth set of four coefficient words
;
; The number of FIR coefficients is always odd, so one or more of the words
; in the last set sent will be ignored. The DSP uses the number of coefficients
; specified using the 00 descriptor. It is not necessary to send 8 sets if
; there are fewer coefficients.
;
; If not zero, the Descriptor Code is used to determine where in the coefficients
; list the values in the packet should be placed. If the Code is greater than
; MAX_COEFF_BLOCK_NUM, the values will be ignored and not placed in the list.
;
; After each FIR filter convolution performed in the DSP, the result is right
; shifted by the amount specified in the packet sent with 00 Descriptor Code.
;
; The number of coefficients should not be more than MAX_NUM_COEFFS.
;   If received value is greater, will be limited to the max.
; The number of bits to shift should not be more than allowed by DSP.
;	If received value is greater, an unpredictable shift will be applied.
;
; If the filter array is empty (a single element set to zero), the array size
; zero will be sent with a zero bit shift value. In such case, no coefficients
; will be sent -- the existing ones will be ignored.
;
; The coefficients are stored in program memory as the MACD opcode expects them
; there for fastest operation. A DMA channel is used to store the values as that
; is the only way to access program memory. There is space reserved for 32 words
; so 8 packets of four words each can be stored without overrun...in practice
; no more than 31 values will be used as FIR filters always use an odd number
; of coefficients.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;
; NOTE:
;
; Only Core A and Core C can write to the program memory in MPAB0 and MPCD0
; due to the design of the DMA addressing. Since A/B share a channel and
; C/D share a channel, they always have the same settings so it works fine
; to only have A/C modify the shared code for each pair.
;
; If the core is B or D (coreID variable = 2 or 4), this function exits
; without action to prevent writing to pages MPAB2 or MPCD2.
;
; See "DMA Addressing" section in the notes at the top of this file for
; more details.
;
; CAUTION: Using multiple DMA channels can cause issues. See note at the
; top of the file title "Multiple DMA Channels Issue" for details.
;

handleSetFilterCommand:

	ld      #Variables1, DP

	mar     *AR3+%                  ; skip past the packet size byte

	ld      *AR3+%, A               ; get packet Descriptor Code
	bc      $2, ANEQ                ; check for code 0, skip if not


	; handle Descriptor Code 0 by storing number of coefficients and
	; the right shift scale value
	
	ld      *AR3+%, A               ; get number of coefficients
	
	sub     #MAX_NUM_COEFFS, 0, A, B    ; check if A > MAX (B=A-MAX_NUM_COEFFS)
	bc      $1, BLEQ            		; A<=0 if A was not over max
	ld      #MAX_NUM_COEFFS, A			; limit to max

$1:	stl     A, numCoeffs			; store value
	sub		#1, A					; subtract one for use as FIR repeat counter
	stl		A, numFIRLoops

	;calculate the ending address of the FIR filter buffer based on the number
	;of coefficients -- 0 coeffs no problem as filter won't be run in that case

	ld		numCoeffs, A
	add     #firBuffer, A
	sub     #1, A
	stl		A, firBufferEnd

	ld      *AR3+%, 8, A            ; get filter output scaling value
	stl     A, filterScale			; this upshift/downshift used to set sign
	ld		filterScale, A			;   properly from byte to word
	stl		A, -8, filterScale

	; no need to skip AR3 past end of packet as readSerialPort uses its own pointer

	b       sendACK                 ; send back an ACK packet

$2:

	bitf	coreID, #01h			; check core, only A or C can modify coefficient table
	bc		sendACK, NTC			; core id = 1/2/3/4, B&D will have bit 0 cleared so exit

	; handle all other Descriptor Codes by storing the coefficients in the packet
	; into the list in program memory

	sub     #MAX_COEFF_BLOCK_NUM, 0, A, B    ; check if A > MAX (B=A-MAX_COEFF_BLOCK_NUM)
	bc      $3, BLEQ            			 ; A<=0 if A was not over max

	; ignore packet due to invalid Descriptor Code
	; no need to skip AR3 past end of packet as readSerialPort uses its own pointer

	b       sendACK                 ; send back an ACK packet

$3:

	; store the values in the packet in the coefficients list

	; calculate offset into list based on Descriptor Code
	;  (code 1-> first set in list, code 2-> second set, etc.)

	stm     #NUM_COEFFS_IN_PKT, T	; number of coefficients in each packet
	sub     #1, A					; packet #1 is zeroeth offset
	stl     A, scratch1             ; save to multiply by T register
	mpyu    scratch1, A             ; A = num coeffs in group x group number (in T)
	ld		#coeffs1, B		
	stl		B, scratch2				; save reload as unsigned to avoid sign extension
	ldu		scratch2, B				;  (reset/set SXM bit requires nop for latency so actually more opcodes)
	add		A, 0, B					; compute offset into coeffs1 table

	ld		#4, A					; packet has 4 words (8 bytes) to transfer
									; B contains the destination
									; AR3 points to the buffer

	call	copyByteBufferToProgramMemory

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of handleSetFilterCommand
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; copyByteBufferToProgramMemory
;
; This function transfers a series of words to program memory after assembling
; each word from a byte pair stored in BigEndian format.
;
; The source byte buffer is expected to be a circular buffer.
;
; On entry:
;
; A register = number of words to be transferred.
; B register = destination address
; AR3 = address of high order byte of first word in circular buffer
; 
; DMA3 already set up to transfer from variable dma3Source
; DMA3 already set up to auto post increment the destination address
;
; Although the DMA3 is set up to post-increment the destination address, this
; does not seem to work when transferring one word at at time. It seems to be
; used to increment between words when multiple words sent in one block.
;

copyByteBufferToProgramMemory:

	sub     #1, A                   ; subtract 1 to account for loop behavior.
	stlm    A, BRC					; store transfer count in loop counter
	nop								; latency fixer for store to BRC

	rptb    $8

	stm     DMDST3, DMSA            ; set destination address
	stlm    B, DMSDN
	add		#1, B					; increment to next address

	ld      *AR3+%, 8, A            ; combine bytes into a word...get high byte
	adds    *AR3+%, A               ; add in low byte
	ld      #Variables1, DP
	stl     A, dma3Source           ; store in variable used for DMA3 transfers

	ld		#00h, DP
	orm     #08h, DMPREC            ; use orm to set only the desired bit
									; orm to memory mapped reg requires DP = 0

$1:	bitf    DMPREC, #08h            ; loop until DMA disabled
	bc      $1, TC                  ; AutoInit is disabled, so DMA clears this
									; enable bit at the end of the block transfer

$8:	nop								; end of repeat block

	ret	

; end of copyByteBufferToProgramMemory
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; responseDelay
;
; Uses a string of nop codes to create a delay.  The nops are used because
; they require no register modifications.
;
; Shared Serial Port Timing Notes:
;
; The four DSP cores share the muxed serial port used to transmit data to
; the FPGA.  After the DMA begins transmitting, other functions begin
; monitoring the DMA and serial port transmit buffer status -- when the
; transmission is complete, the port is released so another DSP core can use
; it.  The release time varies depending on what the core is doing. It appears
; that responding functions with very short execution time can return a packet
; too quickly for the controlling core to release the port after its own
; transmission.
;
; Oddly enough, increasing the AScan time to maximum actually reduces the
; collisions as the AScan processing seems to ensure the serial port release
; check code gets called more often.
;
; It was considered to have the host wait for an ack packet after each
; transmission to increase the timing, but some calls such as for AScan
; packets don't wait for an ack in order to speed up the display.  Also, this
; would have drastically increased the overhead for all calls.
;
; The current best solution is for all of the response functions which have
; a very quick response time to insert a delay such as the one provided
; by this function before beginning transmission of the return packet.  This
; delay is no worse than that probably encountered by getPeakData which the
; code must accommodate anyway.
;

responseDelay:

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
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

	ret

; end of responseDelay
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setDelays
;
; Sets the software delay and the hardware delay for the A/D sample set and
; the AScan dataset.
;
; The software delay (aScanDelay) is the number of samples to skip in
; the collected data set before the start of an AScan dataset.  The data
; collection may start earlier than the AScan, so this delay value is
; is necessary to position the AScan. See notes at the top of processAScanFast
; function for more explanation of this delay value.
;
; The hardware delay should match the value set in the FPGA which specifies
; the number of samples to be skipped before recording starts.  This value
; is used in various places in the DSP code to adjust gate locations and
; such so that they reference the start of data collection.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

setDelays:

	ld      #Variables1, DP

	mar     *AR3+%                  ; skip past the packet size byte

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte

	stl     A, aScanDelay           ; number of samples to skip for AScan

	; this delay value can only be positive as ldu does not sign extend
	; the gate positions can be negative, so this delay value must
	; not be greater than positive max integer value

	ldu     *AR3+%, A               ; get byte 3
	sftl    A, 8
	adds    *AR3+%, A               ; add in byte 2
	sftl    A, 8
	adds    *AR3+%, A               ; add in byte 1
	sftl    A, 8
	adds    *AR3+%, A               ; add in byte 0

	sth     A, hardwareDelay1       ; number of samples skipped by FPGA
	stl     A, hardwareDelay0       ; after initial pulse before recording

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setDelays
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setAScanScale
;
; Sets the compression scale for the AScan data set.  This number is actually
; a compression ratio that determines the number of samples to be compressed
; into the AScan data set.  For example, a scale of 3 means three samples
; are to be compressed into every data point in the AScan set.
;
; The value aScanSlowBatchSize is also set -- this value sets the number of
; output data points to be processed in each batch by the slow version of
; the aScan processing function.  This number should be small enough so that
; each batch can be processed while handling data from a UT shot without
; overrunning into the following shot.  As this value is the number of output
; (compressed) data points processed, the number of input data points =
; aScanSlowBatchSize * aScanScale
;
; This function also calls processAScanSlowInit, initializing variables so
; that processAScanSlow can be called.  It is okay to do this even if the
; slow function is currently filling the AScan buffer, in which case the
; process will be restarted using the new batch size.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;
; See notes at the top of processAScanFast function for more explanation of this
; scaling value.
;

setAScanScale:

	mar     *AR3+%                  ; skip past the packet size byte

	ld      #Variables1, DP

	ld      *AR3+%, 8, A            ; get high byte of scale
	adds    *AR3+%, A               ; add in low byte

	stl     A, aScanScale           ; number of samples to compress for
									; each AScan data point

	ld      aScanScale, 1, A        ; load the compression scale * 2 (see header note 1)
	bc      $1, AEQ                 ; if ratio is zero, don't adjust

	sub     #1, A                   ; loop counting always one less

$1:	stl     A, aScanChunk           ; used to count input data points

	ld      *AR3+%, 8, A            ; get high byte of batch size
	adds    *AR3+%, A               ; add in low byte

	stl     A, aScanSlowBatchSize   ; number of output samples to process in
									; each batch for the slow processing

	call    processAScanSlowInit	; init variables for slow AScan processing

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setAScanScale
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setGate / setDAC
;
; Sets the start location, width, and height of a gate or DAC section.  The
; first byte in the packet specifies the gate/section to be modified (0-9),
; the next two bytes specify the start location (MSB first), the next two
; bytes specify the width (MSB first), and the last two bytes specify the
; gate height/section gain (MSB first).
;
; This function will return an ACK packet.
;
; Interface tracking can be turned on or off for each gate by setting the
; appropriate bit in the gate's function flags - see setGateFlags.
;
; If interface tracking is off, the start location is in relation to the
; initial pulse.
;
; If interface tracking is on, the interface gate still uses absolute
; positioning while the start location of the other gates is in relation
; to the point where the interface signal exceeds the interface gate
; (this is calculated with each pulse).  If an interface gate is being
; used, it must always be the first gate (gate 0).
;
; See "Gate Buffer Notes" and "DAC Buffer Notes" in this source code file
; for more details.
;
; The gate height is in relation to the max signal height - it is an
; absolute value not a percentage.
;
; To set gate or DAC function flags, see setGateFlags / setDACFlags.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

setGate:        ; call here to set Gate info

	mar     *AR3+%                  ; skip past the packet size byte
	ld      *AR3+%, A               ; load the gate index number
	call    pointToGateInfo         ; point AR2 to info for gate in A

	b       $1

setDAC:         ; call here to set DAC info

	mar     *AR3+%                  ; skip past the packet size byte
	ld      *AR3+%, A               ; load the gate index number
	call    pointToDACInfo          ; point AR2 to info for DAC in A

$1:

	mar     *AR2+                   ; skip the function flags

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte
	stl     A, *AR2+                ; store the start location MSB

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte
	stl     A, *AR2+                ; store the start location LSB

	mar     *AR2+                   ; skip the adjusted start location

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte
	stl     A, *AR2+                ; store the width

	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3+%, A               ; add in low byte
	stl     A, *AR2+                ; store the height/gain

	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setGate / setDAC
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setGateFlags / setDACFlags
;
; Sets the function flags for a gate or DAC section.  The first byte in the
; packet specifies the gate/section to be modified (0-9), the next two bytes
; specify the function flags (MSB first).
;
; NOTE: setGate/setDAC should be called first as this function may use
; values stored by those functions.
;
; If the gate is flagged as an interface, wall start, or wall end, the index
; will be saved in a variable appropriate for each type.  If more than one
; gate is flagged as one of the above, then the last gate flagged will
; be stored.
;
; If the gate is flagged as wall start or wall end, the gate level, gate
; info pointer, and gate results pointer will be stored in variables for
; quick access during processing.
;

setGateFlags:		; call here to set Gate function flags

	mar     *AR3+%                  ; skip past the packet size byte
	ld      *AR3+%, A               ; load the gate index number
	call    pointToGateInfo         ; point AR2 to info for gate in A

	b       $1

setDACFlags:            ; call here to set DAC function flags

	mar     *AR3+%                  ; skip past the packet size byte
	ld      *AR3+%, A               ; load the gate index number
	call    pointToDACInfo          ; point AR2 to info for DAC in A

$1:	ld      *AR3+%, 8, A            ; get high byte
	adds    *AR3-%, A               ; add in low byte
	stl     A, *AR2                 ; store the gate flags

	mar     *AR3-%                  ; move back to index number
	ld      *AR3, A                 ; reload the gate index number
									; don't use % (circular buffer) token here as
									; it is not needed if not inc/decrementing

        ;NOTE:  the following is being done for Gate flags and DAC gate flags.
        ;       it only makes sense for Gate flags. Since most DAC flags are
        ;       currently zeroed (right?), the following should be ignored for DAC.
        ;       If these DAC flags are ever to be used, the function needs to be
        ;       separated for Gate and DAC Gate flag setting else the following
        ;       will cause problems.

	bitf	*AR2, #GATE_FOR_INTERFACE   ; check if this is the interface gate
	bc      $2, NTC

	stl     A, interfaceGateIndex   ; store this index to designate the iface gate

	b       $4

$2:	bitf    *AR2, #GATE_WALL_START  ; check if this is the wall start gate
	bc      $3, NTC

	stl     A, wallStartGateIndex   ; store this index to designate wall start gate

	call    pointToGateInfo         ; point AR2 to the info for gate index in A
									;  also stores index in A in scratch1 for a
									;  call to pointToGateResults

	ldm     AR2, A                  ; store pointer to gate info in variable
	stl     A, wallStartGateInfo

	mar     *+AR2(+5)               ; skip to the gate level
	ld      *AR2, A                 ; copy for easy use by processing
	stl     A, wallStartGateLevel

	call    pointToGateResults      ; point AR2 to gate results (index in scratch1)

	ldm     AR2, A                  ; store pointer to gate results in variable
	stl     A, wallStartGateResults ; for easy use by processing

	b       $4

$3:	bitf    *AR2, #GATE_WALL_END    ; check if this is the wall end gate
	bc      $4, NTC

	stl     A, wallEndGateIndex     ; store this index to designate wall end gate

	call    pointToGateInfo         ; point AR2 to the info for gate index in A
									;  also stores index in A in scratch1 for a
									;  call to pointToGateResults

	ldm     AR2, A                  ; store pointer to gate info in variable
	stl     A, wallEndGateInfo

	mar     *+AR2(+5)               ; skip to the gate level
	ld      *AR2, A                 ; copy for easy use by processing
	stl     A, wallEndGateLevel

	call	pointToGateResults      ; point AR2 to gate results (index in scratch1)

	ldm     AR2, A                  ; store pointer to gate results in variable
	stl     A, wallEndGateResults   ; for easy use by processing

	b       $4

$4:	b       sendACK                 ; send back an ACK packet

	.newblock                       ; allow re-use of $ variables

; end of setGateFlags / setDACFlags
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processAScan
;
; Creates and stores an AScan dataset.  This is a compressed sample set of the
; input buffer which is sent to the host upon request.  It is meant for
; display in an oscilloscope type display.
;
; A dataset is only created if the CREATE_ASCAN bit in processingflags1 is set.
; This is set by the getAScanBlock function when the host requests the first
; AScan block and by findGatePeak when the signal exceeds a trigger gate.
;
; wip mks -- Since the CREATE_ASCAN bit is set by the call for the first
; block of the AScan, the AScan will generally be overwritten with a new
; dataset before it is completely read as it takes a bit of time to read the
; entire dataset in multiple blocks. The resulting glitches has not seemed
; to be obvious in the display, but it would be better for the host to pass
; a flag on the last block request to initiate the next AScan creation.
;
; The DSP's have multiple AScan modes -- Free Run and Triggered.
;
; Free Run Mode:
;
; Upon receiving a request for an AScan, the DSP immediately returns the
; AScan data set created after the last request.  The DSP then creates a new
; data set from whatever data is in the sample buffer to be ready for the next
; AScan request.  Thus the display always reflects the data stored after the
; previous request, but this is not obvious to the user.
;
; When viewing brief signal indications, the signal will not be very clear as
; the indications will only occasionally flash into view when they happen to
; coincide with the time of request.
;
; Triggered:
;
; The DSP will only create and store an AScan packet when any gate flagged as
; a trigger gate is exceeded by the signal.  An AScan request is answered with
; the latest packet created.  This allows the user to adjust the gate such that
; only the signal of interest triggers a save, thus making sure that that
; signal is clearly captured and displayed.
;
; The parameter pHardwareDelay is stored for use by the function which
; processes the returned packet.
;
; See processAScanFast, processAScanSlow, and kBlock functions for more
; details.
;
; On entry:
;
; DP should point to Variables1 page.
;

processAScan:

	bitf    processingFlags1, #CREATE_ASCAN   ; do nothing if flag not set
	rc      NTC

	andm    #~CREATE_ASCAN, processingFlags1  ; clear the flag

	bitf    flags1, #ASCAN_FAST_ENABLED ; process AScan fast if enabled
	cc      processAScanFast, TC        ; (this will cause framesets to be skipped
										;  due to the extensive processing required)
										; ONLY use fast or slow version

	bitf    flags1, #ASCAN_SLOW_ENABLED ; process AScan slow if enabled
	cc      processAScanSlow, TC        ; (this is safe to use during inspection)
										; ONLY use fast or slow version

; end of processAScan
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processAScanFast
;
; (see also processAScanSlow)
;
; Prepares an AScan data set in the ASCAN_BUFFER which can then be transmitted
; to the host.
;
; There are two versions of this function - fast and slow.  The desired mode is
; set by a message call. (wip mks -- the ability to switch is not yet
; implemented).
; (wip mks -- slow scan tested very little, seems a little too slow)
;
; The fast version processes the entire buffer at one time and returns the data
; set in large chunks as requested by the host.  This will usually cause
; degradation in performance of the rest of the code such as peak detection
; because the ASCan processing may not finish before the next transducer
; pulse/acquisition cycle. This mode may be used during setup when speed
; of the AScan display is important but the peak detection is less
; important.
;
; The slow version processes a small part of the buffer with each firing and
; data collection from the pulsers.  A small part of the buffer is then
; returned each time the host asks for peak data. This mode does not interfere
; with timing and the peak detection code will be accurate.  This mode is used
; during inspection to provide periodic updates to an AScan display for
; monitoring purposes.  If necessary, the host can use the peak data to add
; data to the AScan buffer to show peaks on the AScan which would normally
; have been missed because the AScan data is collected only periodically
; over time.  Because the buffer is created from different data sets as only
; a portion is processed with each shot, the result is not a perfect copy
; of a single shot, but the end result is a good representation of the data.
;
; There are two delays involved in providing an AScan - the delay set in
; the FPGA to delay the collection of samples and the aScanDelay which
; provides further delay for the beginning of the AScan data set.  The
; system must capture data from the beginning of the earliest gate, so the
; FPGA sample delay cannot be later than that.  The user may wish to view
; an AScan from a later point, so an added delay is specified by a call to
; setAScanDelay.  The true delay for the AScan is the sum of the FPGA
; sample delay and the aScanDelay.
;
; To fit larger sample ranges into the buffer, the data is compressed by
; the scale factor in aScanScale.  If aScanScale = 0 or 1, no compression is
; performed.  If aScanScale = 3, then the data is compressed by 3.  The
; min and max are collected from aScanScale * 2 samples, then the peaks
; are stored in the AScan buffer in the order in which they were found
; in the raw data.  By storing the peaks in the order they occur, the host
; can redraw the data set more accurately.
;
; Note 1:
;
;  The compressed AScan buffer stores both a minimum and maximum peak for each
;  section of compressed data from the raw buffer.  If only one peak was being
;  kept, the aScanScale value could be used as is to scan that number of raw
;  data values to catch the peak and the compression would be proper.  Since
;  two buffer spaces are being used instead, twice as much data must be scanned
;  for those two spaces to get the same compression, thus the aScanScale value
;  is multiplied by two to obtain the proper count value.
;  Recap using scale of 2 as an example:
;   if one peak is stored, that peak represents represents 2 raw data points
;   if two peaks are stored (as used here), those represent 4 raw data points
;
; On entry:
;
; DP should point to Variables1 page.
;

processAScanFast:

	ld      aScanScale, 1, A        ; load the compression scale * 2 (see header note 1)
	stlm    A, AR0                  ; use to reset the raw buffer index in AR1
									; by using:	mar     *AR1-0

	ld      #PROCESSED_SAMPLE_BUFFER, A ; init input buffer pointer
	adds    aScanDelay, A               ; skip samples to account for delay
	stlm    A, AR1

	stm     #ASCAN_BUFFER, AR2      ;(stm has no pipeline latency problem)

	stm     #399, AR3               ; number of samples for transfer - 1

scanSlowEntry:                          ; function processAScanSlow uses this entry
                                        ; point to process a batch of data points
$1:

	ld      aScanChunk, A           ; counts input data points per data output point
	stlm    A, AR4                  ; use as a counter to catch max peaks
	stlm    A, AR5                  ; use as a counter to catch min peaks

; scan through the data to be compressed for max peak

$8:	ld      #8000h, A               ; prepare to catch max peak

$2:
	ld      *AR1+, B                ; get next sample
	max     A                       ; max of A & B -> A, c=0 if A>B
	bc      $3, NC                  ; jump if A > B, no new peak

	ldm     AR1, B                  ; store location + 1 of new peak
	stl     B, aScanMaxLoc

$3:	banz    $2, *AR4-               ; count thru number samples to compress

	stl     A, aScanMax             ; store the max peak
	mar     *AR1-0                  ; jump back to redo samples for min peak

; scan again through the data to be compressed, this time for min peak

	ld      #7fffh, A               ; prepare to catch min peak

$4:
	ld      *AR1+, B                ; get next sample
	min     A                       ; min of A & B -> A, c=0 if A<B
	bc      $5, NC                  ; jump if A < B, no new peak

	ldm     AR1, B                  ; store location + 1 of new peak
	stl     B, aScanMinLoc

$5:	banz    $4, *AR5-               ; count thru number samples to compress

	stl     A, aScanMin             ; store the min peak

; determine which peak was found first

	ld      aScanMaxLoc, A
	ld      aScanMinLoc, B

	min     A                       ; min location = first peak
	bc      $6, C                   ; jump if B < A

	ld      aScanMax, A             ; store max peak first
	ld      aScanMin, B
	b       $7

$6:

	ld      aScanMin, A             ; store min peak first
	ld      aScanMax, B

$7:

	stl     A, *AR2+                ; store peaks in AScan buffer
	stl     B, *AR2+


	banz    $1, *AR3-               ; loop until batch is complete

	ret

	.newblock                       ; allow re-use of $ variables

; end of processAScanFast
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processAScanSlow
;
; (see also processAScanFast)
; (see also processAScanSlowInit)
;
; Prepares an AScan data set in the ASCAN_BUFFER which can then be transmitted
; to the host.
;
; This function performs the same operation as processAScanFast, but breaks
; the processing into small chunks so small portions can be done with each
; pulse fire/data collection routine.  This allows the AScan buffer to be
; populated without missing a data set -- processAScanFast causes data sets
; to be lost because it takes so much time.
;
; See header notes for processAScanFast for details.  This slower function
; uses variables to store the states of the different pointers and counters
; between processing each batch.  The function processAScanSlowInit should
; be called first to set the pointers and counters up the first time.
; Thereafter, this function will call the init to restart each time the
; data buffer has been entirely processed.
;
; Warning: data may be stored a bit beyond the end of the AScan buffer
; as the total number of points processed is checked after each batch.  The
; number of points processed in each batch may not be an exact multiple.
;
; On entry:
;
; Before the first call, processAScanSlowInit should have been called.
; DP should point to Variables1 page.
;

processAScanSlow:

; load all the variables

	ld      aScanScale, 1, A        ; load the compression scale * 2 (see header note 1)
	stlm    A, AR0                  ; use to reset the raw buffer index in AR1
									; by using:		mar		*AR1-0

	ld      inBufferPASS, A         ; load input buffer pointer
	stlm    A, AR1

	ld      outBufferPASS, A        ; load output buffer pointer
	stlm    A, AR2

	ld      totalCountPASS, A       ; load total output data counter
	stlm    A, AR6

	ld      aScanSlowBatchSize, A   ; load number of output points to process in one batch
	stlm    A, AR3

	call    scanSlowEntry           ; call the processAScanFast function to use
									; it to process one batch of data points

	banz    $1, *AR6-               ; stop when entire output buffer filled
									; Warning: may go a bit past the buffer end
									; because the batches process multiple points
									; between each time the total count is checked.


	b       processAScanSlowInit    ; call init again to start over


; save the new state of the variables
; aScanSlowBatchSize in AR3 is not saved as it never changes
; the compression scale is saved even though it does not change
; since it is manipulated (multiplied by 2) by the init

$1:

	ldm     AR1, A                  ; save input buffer pointer
	stl     A, inBufferPASS

	ldm     AR2, A                  ; save output buffer pointer
	stl     A, outBufferPASS

	ldm     AR6, A                  ; load total output data counter
	stl     A, totalCountPASS

	ret

	.newblock                       ; allow re-use of $ variables

; end of processAScanSlow
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processAScanSlowInit
;
; (see also processAScanFast)
; (see also processAScanSlowInit)
;
; Initializes variables for processAScanSlow.  Must be called before
; processAScanSlow is called for the first time.  Thereafter, processAScanSlow
; will call this function itself to restart each time the data buffer is
; completely processed.
;
; The variables used all have the anacronym PASS appended to their names.
;
; On entry:
;
; DP should point to Variables1 page.
;

processAScanSlowInit:

	ld      #PROCESSED_SAMPLE_BUFFER, A ; init input buffer pointer
	adds    aScanDelay, A               ; skip samples to account for delay
	stl     A, inBufferPASS

	ld      #ASCAN_BUFFER, A            ; init output buffer pointer
	stl     A, outBufferPASS

	ld      #399, A                     ; init total output data counter
	stl     A, totalCountPASS

	ret

	.newblock                           ; allow re-use of $ variables

; end of processAScanSlowInit
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; calculateGateIntegral
;
; Finds the integral of the data bracketed by the gate which has a level
; above the gate.  Anything below the gate level is ignored.
;
; NOTE: This should work for all modes -- +Half, -Half, Full, and RF since
; only data above the gate is processed.  For most purposes, the gate should
; be a "max" gate.
;
; On entry, AR2 should point to the flags entry for the gate.  Variable
; scratch1 should contain the gate's index.
;
; The integral is stored in the gate's peak results entry in gateResultBuffer.
;
; NOTE: If the signal equals the gate level, it is considered to exceed it.
;
; If the gate is a "max" gate, the signal must go higher than the gate's
; height.  If it is a "min" gate, the signal must go lower.
;
; If the peak is higher than the gate level, the gate's hit counter value
; in the results buffer is incremented.  If the hit count value reaches
; the Hit Count threshold setting, the appropriate bit is set in the gate's
; results flags.
;
; NOTE: The "adjusted start location" for the gate should be calculated
; before calling this function.
;

calculateGateIntegral:

; if you include the next line, also include the branch to copyToAveragingBuffer at the end of this function
;	call	averageGate             ; average the sample set with the previous
									; set(s) -- up to four sets can be averaged

									; AR2 already point to the gate's paramaters
	mar     *AR2+                   ; skip the flags
	mar     *AR2+                   ; skip the MSB raw start location
	mar     *AR2+                   ; skip the LSB

	ldu     *AR2+, A                ; set AR3 to adjusted start location of the gate
	stlm    A, AR3
	stlm    A, AR4                  ; AR4 is passed to storeGatePeakResult as the
									; buffer location of the peak -- not useful for
									; the integral so set to the start of the gate

	ld      *AR2, A                 ; Set block repeat counter to the gate width.
	add     *AR2, A                 ; Value in param list is 1/3 the true width.
	add     *AR2+, A                ; Add three times to get true width.
									; There may be slight round off error here,
									; but shouldn't have significant effect.

	rc      AEQ                     ; if the gate width is zero, don't attempt
									; to calculate integral

	sub     #1, A                   ; Subtract 1 to account for loop behavior.
	stlm    A, BRC

	ld      *AR2+, A                ; load the gate level
	stl     A, scratch4             ; store for quick use

	mar     *+AR2(-6)               ; point back to gate function flags

	ld      #0h, A                  ; zero A in preparation for summing

; same integration code used for any signal mode, +half, -half, Full, RF
; the result will vary depending on the mode

	rptb    $3


; load each data point and subtract the gate level to shift it down,
; values which then fall below zero will be ignored -- this acts as a
; threshold at the gate level

	ld      *AR3+, B                ; load each data point
	sub     scratch4, B             ; subtract an offset (use the gate level)

	nop                             ; pipeline protection for xc
	nop

	xc      1, BGT
	add     B, A                    ; sum each data point only if
									; it is greater than zero

$3:	nop

	sfta    A, -2                   ; scale down the result

	call    storeGatePeakResult     ; store the result

	ret

;	b       copyToAveragingBuffer   ; copy new data to oldest buffer

	.newblock                       ; allow re-use of $ variables

; end of calculateGateIntegral
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; averageGate
;
; Averages the samples in the gate with the previous sets of data (up to 4
; sets).
;
; The number of sets to average (buffer size) is transferred from the host
; in the upper most two bits of the gate's flags.
;
; The counter tracking which buffer was filled last time is stored in the upper
; most two bits of the gate's ID number.
;
; On entry, AR2 should point to the flags entry for the gate.  Variable
; scratch1 should contain the gate's index.
;
; NOTE: The "adjusted start location" for the gate should be calculated
; before calling this function.
;
; This function does nothing if the averaging buffer size is 0.
;

averageGate:

	ldu     *AR2, A			; get the buffer size from flags -- shift to bit 0
	sfta    A, -14
	rc      AEQ				; do nothing if averaging buffer size is zero
							; zero from host means no averaging

							; AR2 already point to the gate's paramaters
	mar     *AR2+			; skip the flags
	mar     *AR2+			; skip the MSB raw start location
	mar     *AR2+			; skip the LSB

	ldu     *AR2+, A		; set AR3 to adjusted start location of the gate
	stlm    A, AR3
	stl     A, scratch5		; store for later use by copyToAveragingBuffer

	ld      *AR2, A			; Set block repeat counter to the gate width.
	add     *AR2, A			; Value in param list is 1/3 the true width.
	add     *AR2+, A		; Add three times to get true width.
							; There may be slight round off error here,
							; but shouldn't have significant effect.
	sub     #1, A			; Subtract 1 to account for loop behavior.
	stlm    A, BRC


; increment the buffer counter -- if it is equal to the number of
; averaging buffers to be used (specified by host), then reset to
; 1 -- the first time through the counter will be zero so that
; buffer 1 will be used first

	mar     *+AR2(-5)               ; move back to the gate's flags
	ldu     *AR2-, B                ; load the flags and shift buffer size
									; to average down to bit 0 (this number from host)
	sfta    B, -14

	ldu     *AR2, A                 ; load gate ID and shift buffer counter to bit 0
	sfta    A, -14

	min     A                       ; is limit or counter bigger?

	bc      $1, C                   ; if the counter is equal to the max buffer to
                                        ; average, reset counter to 1

	; increment counter

	ldu     *AR2, A                 ; get the ID & buffer counter
	add     #04000h, A              ; increment counter at bit 14

	stl     A, *AR2                 ; save the ID with new counter

	b       $2

$1:	; reset counter to 1

	andm    #03fffh, *AR2           ; clear the old counter in ID
	orm     #04000h, *AR2           ; set counter bits to 01, point AR2 at flags

$2:

; set up the pointers to each buffer -- they are 2000h apart so they could
; hold the entire 8K data sample set if the gate(s) were that big

	ldm     AR3, A                  ; get adjusted gate start location
	add     #2000h, A               ; buffer 1
	stlm    A, AR4
	add     #2000h, A               ; buffer 2
	stlm    A, AR5
	add     #2000h, A               ; buffer 3
	stlm    A, AR6

; the summed data gets stored over the data in the oldest buffer, pointed at by
; AR7 -- the gate's adjusted start entry gets set to this value so the following
; processing functions will operate on that summed data
; after processing, the new data in the 8000h buffer is copied to this oldest
; buffer, overwriting the summed data which will not be needed any more

	ld      #2000h, A               ; load spacing between buffers
	stlm    A, T                    ; preload T for mpya

	ldu     *AR2, A                 ; load gate ID
	sfta    A, 2                    ; shift buffer counter up to upper of A for mpya

	mpya    A                       ; multiply A(bits 32-16) x T -> B

	ldm     AR3, B                  ; get adjusted gate start location

	add     B, A                    ; add buffer offset to location in the 8000h buffer
									; where the gate's adjusted start location points at
									; this will now point to the gate's mirror location in
									; the current averaging history buffer

	stlm    A, AR7                  ; use AR7 to track result buffer
	mar     *+AR2(+4)               ; move to adjusted gate start
	stl     A, *AR2                 ; following processing functions will
									; now work on data at this location

	mar     *+AR2(-3)               ; move back to gate flags

	rptb    $4

; add the values from all the buffers together
; if a buffer isn't being used, it will have zeroes and won't affect the
; sum -- this is the simplest way to do it at the time
; all buffers need to be zeroed on program start

	ld      *AR3+, A                ; sum each data point from all 4 buffers
	add     *AR4+, A
	add     *AR5+, A
	add     *AR6+, A
$4:	stl     A, *AR7+

;	sfta    A, -2                   ; scale down the result

	ret

	.newblock

; end of averageGate
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; storeWordInMapBuffer
;
; Stores the value in the A register in the circular map buffer in data
; page MD*1.
;
; Increments the mapBufferCount variable to track the number of words inserted.
;
; Helpful note:
; 	*+AR3(0)% is only way to not modify AR3 for circular buffer
; 	all other operations increment, decrement, or add a value to AR3
;

storeWordInMapBuffer:

	ld      #Variables1, DP         ; point to Variables1 page

	pshm	AL						; save the value to be buffered

	ld      mapBufferInsertIndex, A ; get the buffer insert index pointer
	stlm    A, AR3
	nop								; can't use stm to BK right after stlm AR3
									; and must skip two words before using AR3
									; due to pipeline conflicts

	stm     #MAP_BUFFER_SIZE, BK 	; set the size of the circular buffer
	nop                             ; next word cannot use circular
									; addressing due to pipeline conflicts

	ld      #00, DP					; point to Memory Mapped Registers
	orm     #0001h, DMMR			; switch to MD*1 page to access the map buffer
	nop								; must skip three words before using page
	nop								; use three nops to be safe
	nop

	popm	AL						; retrieve the value to be buffered

	stl     A, *AR3+%               ; store word in buffer

	andm    #0fffeh, DMMR			; switch back to MD*0 data page
	nop								; must skip three words before using page
	nop								; use three nops to be safe
	nop
	ld      #Variables1, DP         ; point to Variables1 page

	ldm     AR3, A                  ; save the buffer inset index pointer
	stl     A, mapBufferInsertIndex

	ld      mapBufferCount, A       ; increment the counter to track number of
	add     #1, A                   ; words in the buffer
	stl     A, mapBufferCount

	ret

	.newblock                       ; allow re-use of $ variables

; end of storeWordInMapBuffer
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; copyToAveragingBuffer
;
; This function copies data for the gate from the buffer at 8000h to the
; history buffer with specified by the value in the gate's adjusted start
; location parameter. This is done so that the averageGate function can use
; the history buffers to average the signal over time.
;
; On entry, variable scratch1 should contain the gate's index.
;
; Variable scratch5 should contain the gate's adjusted location in the
; 8000h buffer while the gate's adjusted location parameter should contain
; the destination buffer (this is set by the averageGate function).
;
; This data copy is necessary because the 4 buffers are not truly rotated.
; Incoming data is always inserted into the 8000h buffer and then rotated
; to one of the other three.  If the program is instead changed to dump
; incoming data directly into the oldest data buffer then this copy will
; no longer be necessary.
;
; This function does nothing if the averaging buffer size is 0.
;

copyToAveragingBuffer:

	ld      scratch1, A             ; get the gate index
	call    pointToGateInfo         ; point AR2 to the gate's parameter list

	ldu     *AR2, A                 ; get the buffer size from flags -- shift to bit 0
	sfta    A, -14
	rc      AEQ                     ; do nothing if averaging buffer size is zero
									; zero from host means no averaging


	ldu     scratch5, A             ; set AR3 to adjusted start location of the gate
	stlm    A, AR3                  ;  this is the new data in the 8000h buffer
									;  this pointer stored by function averageGate

	mar     *+AR2(+3)               ; move to adjusted start location in the gate's
									; parameters -- averageGate function sets this
									; to the buffer to be used next

	ldu     *AR2+, A                ; set AR3 to adjusted start location of the gate
	stlm    A, AR4

	ld      *AR2, A                 ; Set block repeat counter to the gate width.
	add     *AR2, A                 ; Value in param list is 1/3 the true width.
	add     *AR2+, A                ; Add three times to get true width.
									; There may be slight round off error here,
									; but shouldn't have significant effect.
	sub     #1, A                   ; Subtract 1 to account for loop behavior.
	stlm    A, BRC

	mar     *+AR2(-5)               ; move back to gate flags

	rptb    $1                      ; copy newest data to the oldest buffer
$1:	mvdd    *AR3+, *AR4+

	ret

	.newblock

; end of copyToAveragingBuffer
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; findGatePeak
;
; Finds the peak value and its location for the gate entry pointed to by AR2.
; On entry, AR2 should point to the flags entry for the gate.  Variable
; scratch1 should contain the gate's index.
;
; Preliminary search looks at every 3rd sample to save time. Secondary search
; then finds exact peak. Gate should be greater than 3 samples wide.  Signals
; on the edge may be missed, gate should be slightly wider than necessary to
; avoid problems.
;
; The peak and its buffer location are stored in the gate's results entry
; in gateResultBuffer.
;
; NOTE: If the signal equals the gate level, it is considered to exceed it.
;
; If the gate is a "max" gate, the signal must go higher than the gate's
; height to flag.  If it is a "min" gate, the signal must go lower than the
; gate to flag.
;
; If the peak exceeds the gate level, the gate's hit counter value
; in the results buffer is incremented.  If the hit count value reaches
; the Hit Count threshold setting, the appropriate bit is set in the gate's
; results flags.
;
; NOTE: The "adjusted start location" for the gate should be calculated
; before calling this function.
;
; If the gate is flagged as an AScan trigger gate, the CREATE_ASCAN flag
; will be set in processingFlags1 so that an AScan data set will be created
; from the current data set so the signal can be displayed by the host.
;
; On entry, DP should point to Variables1 page.
;

findGatePeak:

	stm     #3, AR0                 ; look at every third sample
									; (AR0 is used to increment sample pointer)

									; AR2 already point to the gate's parameters
	mar     *AR2+                   ; skip the flags
	mar     *AR2+                   ; skip the MSB raw start location
	mar     *AR2+                   ; skip the LSB

	ldu     *AR2+, A                ; set AR3 to adjusted start location of the gate
	stlm    A, AR3

	ld      *AR2+, A                ; set block repeat counter to the
	sub     #1, A                   ; gate width / 3, subtract 1 to account
	stlm    A, BRC                  ; for loop behavior

	mar     *+AR3(2)                ; start with third sample

	ld      *AR3+0, A               ; Get first sample - preload so
									; reload occurs at end of repeat
									; block - rptb crashes if it points
									; to a bc instruction or similar.
									; This is now the max or min until replaced.
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation

	mvmm    AR3, AR4                ; store the buffer address of the
									; first sample in AR4
									; NOTE: AR4 will actually be loaded
									; with the address + 3 - this must
									; be adjusted back when finished to
									; get the location of the found peak

	mar     *+AR2(-5)               ; point back to gate function flags

	bitf    *AR2, #GATE_MAX_MIN     ; function flags - check gate type
	bc      $2, TC                  ; look for max if 0 or min if 1

; max gate - look for maximum signal in the gate

	ld      #0x8000, 16, B          ; preload B with min value to force
									; save of first value preloaded in A

	rptb    $3

	max     A                       ; compare sample with previous max
									; the new max will replace old max in A

	nop                             ; avoid pipeline conflict with xc
	nop                             ; two words between test instr and xc

	xc      1, C                    ; if sample in B >= prev peak in A
	mvmm    AR3, AR4                ; store the buffer address of the new
									; max
									; NOTE: AR4 will actually be loaded
									; with the address + 3 - this must
									; be adjusted back before use

$3:	ld      *AR3+0, B               ; get next sample
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation


        ; look at two skipped samples before and two after peak to find the
        ; exact peak - the two after may be slightly past the gate, but
        ; so close as not to matter

	mar     *+AR4(-2)               ; AR4 points 3 points ahead of the peak
									; adjust to point to one after as this
									; is expected on exit
	mvmm    AR4, AR3                ; get buffer address of peak
	mar     *+AR3(-3)               ; move back to first of skipped samples
									; just before the found peak

	ld      *AR3+, B                ; get sample
	max     A                       ; compare with peak in A
	nop                             ; avoid pipeline conflict with xc
	nop                             ; two words between test instr and xc
	xc      1, C                    ; if sample in B >= old peak in A, then
	mvmm    AR3, AR4                ; store the buffer address of the new peak

	ld      *AR3+, B                ; repeat for next sample
	max     A
	nop
	nop
	xc      1, C
	mvmm    AR3, AR4

	mar     *AR3+                   ; skip past the peak already found,
									; now do two samples after peak

	ld      *AR3+, B                ; repeat for next sample
	max     A
	nop
	nop
	xc      1, C
	mvmm    AR3, AR4

	ld      *AR3+, B                ; repeat for next sample
	max     A
	nop
	nop
	xc      1, C
	mvmm    AR3, AR4

	mar     *AR4-                   ; adjust to point back to peak

	b       storeGatePeakResult

$2:

; min gate - look for minimum signal in the gate

	ld      #0x7fff, 16, B          ; preload B with very large value to force
									; save of new value on first min test
									; value loaded is 0x7fff0000
	rptb    $4

	min     A                       ; compare sample with previous min
									; the new min will replace old min in A

	nop                             ; avoid pipeline conflict with xc
	nop                             ; two words between test instr and xc

	xc      1, C                    ; if sample in B <= prev peak in A, then
	mvmm    AR3, AR4				; store the buffer address of the new
									; min
									; NOTE: AR4 will actually be loaded
									; with the address + 3 - this must
									; be adjusted back before use

$4:	ld      *AR3+0, B               ; get next sample
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation

        ; look at two skipped samples before and two after peak to find the
        ; exact peak - the two after may be slightly passed the gate, but
        ; so close as not to matter

	mar     *+AR4(-2)               ; AR4 points 3 points ahead of the peak
									; adjust to point to one after as this
									; is expected on exit
	mvmm    AR4, AR3                ; buffer address of peak -> AR3
	mar     *+AR3(-3)               ; move back to first of skipped samples
									; just before the found peak

	ld      *AR3+, B                ; get sample
	min     A                       ; compare with peak in A
	nop                             ; avoid pipeline conflict with xc
	nop                             ; two words between test instr and xc
	xc      1, C                    ; if sample in B <= old peak in A, then
	mvmm    AR3, AR4                ; store the buffer address of the new peak

	ld      *AR3+, B				; repeat for next sample
	min     A
	nop
	nop
	xc      1, C
	mvmm    AR3, AR4

	mar     *AR3+                   ; skip past the peak already found,
									; now do two samples after peak

	ld      *AR3+, B				; repeat for next sample
	min     A
	nop
	nop
	xc      1, C
	mvmm    AR3, AR4

	ld      *AR3+, B				; repeat for next sample
	min     A
	nop
	nop
	xc      1, C
	mvmm    AR3, AR4

	mar     *AR4-                   ; adjust to point back to peak

	b       storeGatePeakResult

	.newblock

	; store the peak in temporary variables and apply differential shot math

storeGatePeakResult:

	stl     A, scratch2             ; save the peak
	ld      *AR2, A                 ; save copy of gate flags for quick access
	stl     A, scratch3
	ld      *+AR2(+5), A            ; save copy of gate level for quick access
	stl     A, scratch4
	ld      *+AR2(+1), A            ; save copy of hit count threshold for quick access
	stl     A, hitCountThreshold
	ld      *+AR2(+1), A            ; save copy of miss count threshold for quick access
	stl     A, missCountThreshold

	; if subsequent differential noise cancellation mode is active,
	; subtract the peak from the peak of the previous shot (will actually
	; be two shots ago as each DSP core handles every other shot).

	bitf	scratch3, #SUBSEQUENT_SHOT_DIFFERENTIAL     ; gate function flags
	bc      checkForNewPeak, NTC    ; check for subsequent differential mode

	call    pointToGateResults      ; point AR2 to the entry for gate in scratch1

	mar     *+AR2(11)               ; move to gate peak value from previous data set
	ld      scratch2, A             ; load the current peak for storing
	ld      scratch2, B             ; load the current peak for subtracting

	sub     *AR2, B                 ; subtract the previous peak from the current peak
	stl     B, scratch2             ; save the modified current peak
	stl     A, *AR2                 ; save the unmodified current peak for use on next shot

	; check for new peak
	; checks to see if new peak is larger than stored peak and
	; replaces latter with former if so

checkForNewPeak:

; if the new peak is greater/lesser than the stored peak, replace the
; latter with the former

	call    pointToGateResults      ; point to the entry for gate in scratch1

	mar     *+AR2(8)                ; move to stored peak value
	ld      *AR2, A                 ; load the stored peak
	ld      scratch2, B             ; load the new peak

	bitf    scratch3, #GATE_MAX_MIN ; function flags - check gate type
	bc      $5, TC                  ; look for max if 0 or min if 1

; max gate - check if peak greater than stored peak

	max     A                       ; peak in B >= current peak in A?
	bc      $6, C                   ; yes if C set, jump to store
	b		checkForPeakCrossing

$5:

; min gate - check if peak less than stored peak

	min     A                       ; peak in B <= current peak in A?
	bc      $6, C                   ; yes if C set, jump to store
	b		checkForPeakCrossing

$6:

	stl     A, *AR2+                ; store the new peak in results
	ldm     AR4, A                  ; get the new peak's buffer address
	stl     A, *AR2+                ; store address in results
	ld      trackCount, A           ; get the tracking value for new peak
	stl     A, *AR2+                ; store tracking value in results

	b		checkForPeakCrossing

	; check to see if peak exceeds the gate
	; checks first to see if the peak is above the gate level - if so
	; increments the hit counter and sets the hit flag if the hitCount
	; threshold reached

checkForPeakCrossing:

	ld      scratch2, B             ; load the peak
	ld      scratch4, A             ; load the gate level

	bitf    scratch3, #GATE_MAX_MIN ; function flags - check gate type
	bc      $3, TC                  ; look for max if 0 or min if 1

; max gate - check if peak greater than gate level

	max     A                       ; peak in B >= gate level in A?
	bc      handlePeakCrossing, C   ; yes if C set, jump to inc hitCount
	b       handleNoPeakCrossing

$3:

; min gate - check if peak less than gate level

	min     A                       ; peak in B <= gate level in A?
	bc      handlePeakCrossing, C   ; yes if C set, jump to inc hitCount
	b       handleNoPeakCrossing

handlePeakCrossing:

; since the peak signal exceeded the gate, clear the "not exceeded" count
; and increment the "exceeded" count

	call    pointToGateResults      ; point to the entry for gate in scratch1

	stl     A, *+AR2(4)				; store the peak in "signal before exceeding"
	ldm     AR4, A					; store peak address (time) in "signal before exceeding buffer 
	stl     A, *+AR2(1)				; address" where processWall expects it             

	mar     *+AR2(-2)				; move to and clear the "not exceeded" count
	st      #0,*AR2-

	ld      *AR2, A                 ; increment the "exceeded" count
	add     #1, A
	stl     A, *AR2

	sub     hitCountThreshold, A	; compare count with threshold
	bc      $7, ALT                 ; skip if not count < threshold

	st      #0,*AR2-                ; clear the "exceeded" count

	mar     *AR2-                   ; skip to the gate results flags

	orm     #HIT_COUNT_MET, *AR2    ; set flag - signal exceeded gate
									; hitCount number of times

	;if the gate is an AScan trigger gate, set the flag to initiate the
	; saving of an AScan dataset from the current samples

$7:	bitf    scratch3, #GATE_TRIGGER_ASCAN_SAVE  ; function flags - check if trigger gate
	bc      $1, NTC                             ; don't trigger an AScan if not a trigger gate

	orm     #CREATE_ASCAN, processingFlags1		; set flag -- create a new AScan dataset

$1:	ld      #0, A                   ; return 0 - peak exceeds gate

	ret

; peak signal did not exceed gate, so clear "exceeded count" and
; increment the "not exceeded" count

handleNoPeakCrossing:

	call    pointToGateResults      ; point to the entry for gate in scratch1

	mar     *+AR2(2)                ; move to "exceeded" count

	; since the signal did not exceed the gate, clear the "exceeded" count
	; and increment the "not exceeded" count

	st      #0,*AR2+                ; clear the "exceeded" count

	ld      *AR2, A                 ; increment the "not exceeded" count
	add     #1, A
	stl     A, *AR2

	sub     missCountThreshold, A	; compare count with threshold
	bc      $2, ALT					; skip if not count < thhreshold

	st      #0,*AR2-                ; clear the "not exceeded" count

	mar     *AR2-                   ; skip to the gate results flags
	mar     *AR2-

	orm     #MISS_COUNT_MET, *AR2   ; set bit 1 - signal missed the gate
									; missCount number of times

$2:	ld      #-1, A                   ; return -1 - peak does not exceed gate

	ret

	.newblock                       ; allow re-use of $ variables

; end of findGatePeak
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; findGateCrossing
;
; Finds the location where the signal crosses the level for the gate entry
; pointed to by AR2.   AR2 should point to the flags entry for the gate.
;
; Preliminary search looks at every 3rd sample to save time. Secondary search
; then finds exact location.  Signal must therefore exceed the gate with at
; least three points.  Gate should be greater than 3 samples wide.  Signals
; on the edge may be missed, gate should be slightly wider than necessary to
; avoid problems.
;
; The crossing point and its buffer location and the previous point and
; its buffer location are stored in the gate's results entry in
; gateResultBuffer.  If A is returned not zero, the data in the results
; entry is undefined and should not be used.
;
; NOTE: If the signal equals the gate level, it is considered to exceed it.
;
; If the gate is a "max" gate, the signal must go higher than the gate's
; height.  If it is a "min" gate, the signal must go lower.
;
; On exit:
; If a crossing is detected, A register returns 0 and the results are
; stored in the gates results entry in the gateResultsBuffer.
; Register A returns -1 if the signal never exceeded the gate.
;
; NOTE: The "adjusted start location" for the gate should be calculated
; before calling this function.
;
; NOTE: This function is similar to findGateCrossingAfterGain.  This
; function does not apply gain to the samples.  The use of the A & B
; registers during the loop are opposite in the two functions because
; the gain version must use A to multiply the gain.  It would be better
; to change this version to use A & B in the same manner.  The gain
; version does jump to part of the code in this version.
;

findGateCrossing:

	stm     #3, AR0                 ; look at every third sample

	mar     *AR2+                   ; skip the flags
	mar     *AR2+                   ; skip the MSB raw start location
	mar     *AR2+                   ; skip the LSB

	ldu     *AR2+, A                ; set AR3 to adjusted start location
	stlm    A, AR3

	ld      *AR2+, A                ; set block repeat counter to the
	sub     #1, A                   ; gate width / 3, subtract 1 to account
	stlm    A, BRC                  ; for loop behavior

	mar     *+AR3(2)                ; start with third sample

	ld      *AR3+0, B               ; get first sample - preload so
									; reload occurs at end of repeat
									; block - rptb crashes if it points
									; to a bc instruction or similar
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation

	ld      *AR2+, A                ; get the gate height

	mar     *+AR2(-6)               ; point back to gate function flags

	bitf    *AR2, #GATE_MAX_MIN     ; function flags - check gate type
									; for wall, both the start and the
									; end gate should be MAX gates

	bc      $2, TC                  ; look for max if 0 or min if 1

	; max gate - look for signal crossing above the gate

	rptb    $3
	max     B                       ; compare sample with gate height in A
	bc      $4, C                   ; if sample in B > height in A, exit loop
$3:	ld      *AR3+0, B               ; get sample
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation

	b       handleNoCrossing        ; handle "signal did not exceed gate"

$4:	; look at skipped samples for earliest to exceed threshold

	mar     *+AR3(-5)               ; jump back to first of skipped samples

	ld      *AR3+, B                ; get sample
	max     B                       ; compare with gate height in A
	bc      $5, C

	ld      *AR3+, B                ; get sample
	max     B                       ; compare with gate height in A
	bc      $5, C

	;if the skipped samples did not exceed the gate, then AR3 will now
	;point to the sample which did exceed

	b       storeGateCrossingResult

$5:	mar     *AR3-                   ; move back to point at sample which first
									; exceeded the gate
	b       storeGateCrossingResult

$2:	; min gate - look for signal crossing below the gate

	rptb    $9
	min     B                       ; compare sample with gate height in A
	bc      $6, C                   ; if sample in B < height in A, exit loop
$9:	ld      *AR3+0, B               ; get sample
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation


	b       handleNoCrossing        ; handle "signal did not exceed gate"

$6:	; look at skipped samples for earliest to exceed threshold

	mar     *+AR3(-5)               ; jump back to first of skipped samples

	ld      *AR3+, B                ; get sample
	min     B                       ; compare with gate height in A
	bc      $7, C

	ld      *AR3+, B                ; get sample
	min     B                       ; compare with gate height in A
	bc      $7, C

	;if the skipped samples did not exceed the gate, then AR3 will now
	;point to the sample which did exceed

	b       storeGateCrossingResult

$7:
	mar     *AR3-                   ; move back to point at sample which first
									; exceeded the gate
	b       storeGateCrossingResult

	.newblock

; store the crossing point (first point which equals or exceeds the gate)
; and its buffer location and the previous point and its buffer location


storeGateCrossingResult:

	call    pointToGateResults      ; point to the entry for gate in scratch1

	mar     *+AR2(7)                ; move to entry for after exceeding address

	ldm     AR3, A                  ; get location of point which exceeded gate
	stl     A, *AR2-                ; store location

	ld      *AR3-, A                ; get point which exceeded gate
	stl     A, *AR2-                ; store exceeding point value

	ldm     AR3, A                  ; get location of previous point
	stl     A, *AR2-                ; store location

	ld      *AR3-, A                ; get previous point
	stl     A, *AR2-                ; store previous point value


	; since the signal exceeded the gate, clear the "not exceeded" count
	; and increment the "exceeded count"

	st      #0,*AR2-                ; clear the "not exceeded" count

	ld      *AR2, A                 ; increment the "exceeded count"
	add     #1, A
	stl     A, *AR2

	sub     hitCountThreshold, A    ; see if number of consecutive hits
	bc      $1, ALT                 ; >= preset limit - skip if not

	st      #0,*AR2-                ; clear the "exceeded" count

	mar     *AR2-                   ; skip to the gate results flags

	orm     #HIT_COUNT_MET, *AR2    ; set bit 0 - signal exceeded gate
                                        ; hitCount number of times

$1:	ld      #0, A                   ; return 0 - crossing point found

	orm     #GATE_EXCEEDED, *AR2    ; set flag - signal exceeded the gate level

	ret

; signal never exceeded gate, so clear "exceeded count" and increment
; the "not exceeded" count

handleNoCrossing:

	call    pointToGateResults      ; point to the entry for gate in scratch1

	mar     *+AR2(2)                ; move to "exceeded" count

	; since the signal exceeded the gate, clear the "not exceeded" count
	; and increment the "exceeded count"

	st      #0,*AR2+                ; clear the "exceeded" count

	ld      *AR2, A                 ; increment the "not exceeded count"
	add     #1, A
	stl     A, *AR2

	sub     missCountThreshold, A	; see if number of consecutive hits
	bc      $2, ALT                 ; >= preset limit - skip if not

	st      #0,*AR2-                ; clear the "not exceeded" count

	mar     *AR2-                   ; skip to the gate results flags
	mar     *AR2-

	orm     #MISS_COUNT_MET, *AR2   ; set bit 1 - signal did not exceed gate
									; missCount number of times

$2:	ld      #-1, A                  ; return -1 as no crossing found

	andm    #~GATE_EXCEEDED, *AR2   ; clear flag - signal did not exceed the gate level

	ret

	.newblock                       ; allow re-use of $ variables

; end of findGateCrossing
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; findGateCrossingAfterGain
;
; Finds the location where the signal crosses the level for the gate entry
; pointed to by AR2.   AR2 should point to the flags entry for the gate.
;
; DP should point to Variables1 page.
;
; This function applies softwareGain to each sample before comparing it
; with the gate level.  The sample set is not modified.  This is useful for
; finding the crossing point within the interface gate as the DAC will not
; have been applied when that function must be executed.  The DAC tracks
; the interface crossing, so the crossing point must be found first.
;
; Preliminary search looks at every 3rd sample to save time. Secondary search
; then finds exact location.  Signal must therefore exceed the gate with at
; least three points.  Gate should be greater than 3 samples wide.  Signals
; on the edge may be missed, gate should be slightly wider than necessary to
; avoid problems.
;
; The crossing point and its buffer location and the previous point and
; its buffer location are stored in the gate's results entry in
; gateResultBuffer.  If A is returned not zero, the data in the results
; entry is undefined and should not be used.
;
; NOTE: If the signal equals the gate level, it is considered to exceed it.
;
; If the gate is a "max" gate, the signal must go higher than the gate's
; height.  If it is a "min" gate, the signal must go lower.
;
; If a crossing is detected, A register returns 0 and the results are
; stored in the gates results entry in the gateResultsBuffer.
; Register A returns -1 if the signal never exceeded the gate.
;
; NOTE: The "adjusted start location" for the gate should be calculated
; before calling this function.
;
; NOTE: This function is similar to findGateCrossing.  That
; function does not apply gain to the samples.  The use of the A & B
; registers during the loop are opposite in the two functions because
; the gain version must use A to multiply the gain.  This function
; jumps to end code in findGateCrossing.
;

findGateCrossingAfterGain:

	stm     #3, AR0                 ; look at every third sample

	mar     *AR2+                   ; skip the flags
	mar     *AR2+                   ; skip the MSB raw start location
	mar     *AR2+                   ; skip the LSB

	ldu     *AR2+, A                ; set AR3 to adjusted start location
	stlm    A, AR3

	ld      *AR2+, A                ; set block repeat counter to the
	sub     #1, A                   ; gate width / 3, subtract 1 to account
	stlm    A, BRC                  ; for loop behavior

	ld      softwareGain, A         ; get the global gain value
	stlm    A, T                    ; preload T with the gain multiplier

	mar     *+AR3(2)                ; start with third sample

	ld      *AR3+0,16,A             ; Get first sample - shift to A Hi
									; for multiply instruction.
									; Preload so reload occurs at end of
									; repeat block - rptb crashes if it points
									; to a bc instruction or similar.
									; Indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation.

	; see notes in header of setSoftwareGain function for details on -9 shift
	mpya    A                       ; multiply by gain and store in A
	sfta    A,-9                    ; attenuate

	ld      *AR2+, B                ; get the gate height

	mar     *+AR2(-6)               ; point back to gate function flags

	bitf    *AR2, #GATE_MAX_MIN     ; function flags - check gate type
	bc      $2, TC                  ; look for max if 0 or min if 1

	; max gate - look for signal crossing above the gate

	rptb    $3
	max     A                       ; compare sample with gate height in B
	bc      $4, NC                  ; if sample in A > height in B, exit loop
	ld      *AR3+0,16,A             ; get next sample
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation

	; see notes in header of setSoftwareGain function for details on -9 shift
	mpya    A                       ; multiply by gain and store in A
$3:	sfta    A,-9                    ; attenuate

	b       handleNoCrossing        ; handle "signal did not exceed gate"

$4:	; look at skipped samples for earliest to exceed threshold

	mar     *+AR3(-5)               ; jump back to first of skipped samples

	ld      *AR3+,16,A              ; get sample
	mpya    A                       ; multiply by gain and store in A
	sfta    A,-9                    ; attenuate
	max     A                       ; compare with gate height in A
	bc      $5, NC

	ld      *AR3+,16,A              ; get sample
	mpya    A                       ; multiply by gain and store in A
	sfta    A,-9                    ; attenuate
	max     A                       ; compare with gate height in A
	bc      $5, NC

	;if the skipped samples did not exceed the gate, then AR3 will now
	;point to the sample which did exceed

	b       storeGateCrossingResult

$5:	mar     *AR3-                   ; move back to point at sample which first
									; exceeded the gate
	b       storeGateCrossingResult

$2:	; min gate - look for signal crossing below the gate

	rptb    $9
	min     A                       ; compare sample with gate height in A
	bc      $6, NC                  ; if sample in A < height in B, exit loop
	ld      *AR3+0,16,A             ; get next sample
									; indirect addressing *ARx+0 increments
									; ARx by AR0 after the operation
	; see notes in header of setSoftwareGain function for details on -9 shift
	mpya    A                       ; multiply by gain and store in A
$9:	sfta    A,-9                    ; attenuate

	b       handleNoCrossing        ; handle "signal did not exceed gate"

$6:	; look at skipped samples for earliest to exceed threshold

	mar     *+AR3(-5)               ; jump back to first of skipped samples

	ld      *AR3+,16,A              ; get sample
	mpya    A                       ; multiply by gain and store in A
	sfta    A,-9                    ; attenuate
	min     A                       ; compare with gate height in B
	bc      $7, NC

	ld      *AR3+,16,A              ; get sample
	mpya    A                       ; multiply by gain and store in A
	sfta    A,-9                    ; attenuate
	min     A                       ; compare with gate height in B
	bc      $7, NC

	;if the skipped samples did not exceed the gate, then AR3 will now
	;point to the sample which did exceed

	b       storeGateCrossingResult

$7:
	mar     *AR3-                   ; move back to point at sample which first
									; exceeded the gate
	b       storeGateCrossingResult

	.newblock

; this code jumps to points storeGateCrossingResult and handleNoCrossing
; in the function findGateCrossing

; end of findGateCrossingAfterGain
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; pointToGateInfo / pointToDACInfo
;
; Uses the gate index stored in register A to point AR2 to the specified
; gate info entry in the gateBuffer or DAC info entry in dacBuffer.
;
; AR2 will point to the flags entry for the gate or DAC.
;

pointToGateInfo:

	ld      #gateBuffer, B          ; start of gate info buffer
	stm     #GATE_PARAMS_SIZE, T    ; number of words per gate info entry
	b       $1

pointToDACInfo:

	ld      #dacBuffer, B           ; start of DAC info buffer
	stm     #DAC_PARAMS_SIZE, T     ; number of words per DAC gate info entry

$1:	stl     A, scratch1             ; save the gate index number
	mpyu    scratch1, A             ; multiply gate number by words per
									; gate to point to gate's info area

	add     B, 0, A                 ; offset from base of buffer
	stlm    A, AR2                  ; point AR2 to specified entry

	nop                             ; pipeline protection
	nop

	mar     *AR2+                   ; skip past gate ID to point to flags

	ret

	.newblock                       ; allow re-use of $ variables

; end of pointToGateInfo / pointToDACInfo
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; pointToGateResults
;
; Uses the gate index stored in scratch1 to point AR2 to the specified
; gate results entry in the gateResultsBuffer.
;
; AR2 will point to the flags entry for the gate.
;

pointToGateResults:

	ld      #gateResultsBuffer, B   ; start of gate results buffer

									; gate index number already in scratch1
	stm     #GATE_RESULTS_SIZE, T   ; number of words per gate results entry
	mpyu    scratch1, A             ; multiply gate number by words per
									; gate to point to gate's results area

	add     B, 0, A                 ; offset from base of buffer
	stlm    A, AR2                  ; point AR2 to specified entry

	nop                             ; pipeline protection
	nop

	mar     *AR2+                   ; skip past gate ID to point to flags

	ret

; end of pointToGateResults
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; findInterfaceGateCrossing
;
; Calculates the adjusted gate start location and then calls
; findGateCrossingAfterGain to find the location where the signal exceeds the
; gate's level.
;
; On return:
;  crossing found: A = 0 and IFACE_FOUND flag set in processingFlags1
;  no crossing found: A = -1 and IFACE_FOUND flag cleared in processingFlags1
;
; DP should point to Variables1 page.
;
; NOTE: This function will clear bit 6 for the interface gate, the
; "interface tracking" function as the interface gate itself cannot track
; the interface.
;
; The other flags are not modified, so the host can still disable the gate.
;
; The findGateCrossingAfterGain function is used since it applies the
; softwareGain to the samples.  The interface gate always uses this gain
; as the DAC may be in tracking mode.  For the DAC to track, the interface
; crossing must be found first, so it always uses softwareGain and ignores
; any DAC gain.
;

findInterfaceGateCrossing:

	; set the adjusted start gate value for the interface gate
	; this gate is always absolutely relative to the initial pulse and thereby
	; will be relative to the start of the sample buffer after the adjustment
	; is made

	ld      interfaceGateIndex, A   ; load interface gate index
	call    pointToGateInfo         ; point AR2 to the info for gate in A

	andm    #0ffbfh, *AR2           ; disable "interface tracking" for gate
									; see notes above

	pshm    AR2                     ; save gate info pointer
	call    setGateAdjustedStart
	popm    AR2                     ; restore gate info pointer

	call    findGateCrossingAfterGain   ; find where signal crosses above gate

	andm    #~IFACE_FOUND, processingFlags1 ; clear the found flag

	xc      2, AEQ                  ; if A returned 0 from function call,
									; set the found flag

	orm     #IFACE_FOUND, processingFlags1

	ret

	.newblock                       ; allow re-use of $ variables

; end of findInterfaceGateCrossing
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setGateAdjustedStart
;
; Calculates the adjusted gate start location for the gate entry pointed
; to by AR2. AR2 should point to the flags entry for the gate.
;
; DP should point to Variables1 page.
;
; If interface tracking is off for the gate, this function will
; adjust the start point so that it is relative to the beginning of the
; sample buffer by subtracting hardwareDelay which represents how many
; data samples are skipped before the FPGA begins recording.
;
; If interface tracking is on for the gate, this function will adjust
; the start point so that it is relative to the point where the signal
; first crosses the interface gate.
;
; The crossing function should always be enabled for the interface gate.
;
; Interface tracking can be turned on or off for each gate by setting the
; appropriate bit in the gate's function flags.
;

setGateAdjustedStart:

	bitf    *AR2+, #GATE_USES_TRACKING  ; check interface tracking flag
										; moves AR2 to gate start entry
	bc      $1, TC                      ; if TC set, tracking is on

	; interface tracking is off
	; load the hardwareDelay value as the adjustment amount
	; this will set the start relative to the start of the sample buffer

	ld      hardwareDelay1,16,B         ; load MSB of hardware delay
	adds    hardwareDelay0,B            ; load LSB

	neg     B                           ; set neg so will be subtracted from start


	; add in the start address of the processed sample buffer so that the
	; start location will be relative to that point

	ld      #PROCESSED_SAMPLE_BUFFER, A ;start of buffer
	and     #0ffffh, A                  ;remove sign - pointer is unsigned

	add     A, 0, B			; ( B + A << SHIFT ) -> B
							;  (the TI manual is obfuscated on this one)

	b       $2

$1: ; interface tracking is on

	; store the interface gate crossing point as the adjustment amount
	; this will set the start relative to the interface

	pshd    scratch1                ; store index of gate being adjusted
	pshm    AR2                     ; store address of gate being adjusted

	ld      interfaceGateIndex, A   ; load interface gate index
	stl     A, scratch1             ; pointToGateResults uses index in scratch1
	call    pointToGateResults      ; point AR2 to the results for gate in scratch1

	mar     *+AR2(7)                ; point to the entry of gate 0 (the
									; interface gate if in use) which holds the
									; buffer address of the point which first
									; exceeded the interface gate

	ldu     *AR2, B                 ; get interface crossing buffer location


	popm    AR2                     ; restore address of gate being adjusted
	popd    scratch1                ; restore index and pipeline protect popm AR2

$2:

	ld      *AR2+,16, A             ; load MSB of gate start position
	adds	*AR2+, A                ; load LSB

									; add appropriate offset from above
	add		B, 0, A					; ( A + B << SHIFT ) -> A
									;  (the TI manual is obfuscated on this one)
	stl		A, *AR2					; store the adjusted gate location

	ret

	.newblock                       ; allow re-use of $ variables

; end of setGateAdjustedStart
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processWall
;
; Calculate the wall thickness and record the value if it is a new max or min
; peak.
;
; If DSP_WALL_MAP_MODE bit is set, the value is also stored in the map buffer.
;
; For a sample rate of 66.666 mHz and using a sound speed of 0.233 inches/uS,
; the time between each sample represents
;
; 66.666 mHz = 15 nS period = 0.000000015 sec
; 0.233 inches/uS = 233,000 inches / sec
; 233,000 inches * 0.000000015 sec = .003495 inches
;
; We really need at least .003495 inches of resolution.
;
; BUT -- since we measure twice the distance of the thickness because we
;  are measuring there and back, we then divide by two which also increases
;  our accuracy by two to give 0.0017475 inches per sample of resolution.
;
; I like that.  I like that a lot.
;
; For a version which used fractional math to improve the resolution even
; more, see the commit in Git tagged VersionWithFractionalMathForThickness.
;

processWall:

	stm     #wallPeakBuffer, AR1	; point AR1 to wall peak buffer

	; calculate the whole number time distance between the before crossing points
	; in the start and end gates

	ld      wallStartGateResults, A ; point AR3 to wall start gate results
	stlm    A, AR3

	ld      wallEndGateResults, A   ; point AR4 to wall end gate results
	stlm    A, AR4

	nop                         ; pipeline protection

	mar     *+AR3(5)            ; point to buffer location (time position) of
								; crossover point for start gate

	mar     *+AR4(5)            ; load buffer location (time position) of point
	ld      *AR4+, A            ;  after crossing of end gate (unsigned)
	sub     *AR3+, A            ; subtract start gate crossing from end gate crossing

	stl     A, *AR1             ; save the whole number time distance as new value

	; check for new max peak

	ld      *+AR1(+5), B        ; load the old max peak
	mvmm    AR1, AR2            ; point AR2 at the max peak variables
	ld      *+AR1(-5), A        ; load new value

	max     B                   ; is new bigger than old?
	bc      $1, C               ; no if C set, skip save

	; call to store the new peak

	pshm    AR1
	call    storeNewPeak
	popm    AR1
	nop                             ; pipeline protection

$1:

	; check for new min peak

	ld      *+AR1(+11), B           ; load the old min peak
	mvmm    AR1, AR2                ; point AR2 at the min peak variables
	ld      *+AR1(-11), A           ; load new value

	min     B                       ; is new bigger than old?
	rc      C                       ; no if C set, skip save and return

	; call to store the new peak whole number and fractional parts

storeNewPeak:

	; store the new peak
    ; AR1 should point at the new value
    ; AR2 should point at the peak variables to be updated

	ld      *AR1, A                 ; whole number
	stl     A, *AR2

	ld      trackCount, A           ; get the tracking value for new peak
	stl     A, *+AR2(+5)            ; store tracking value in results

	ret

	.newblock                       ; allow re-use of $ variables

; end of processWall
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; storeWallValueInMapBuffer
;
; Stores the value in the A register in the circular map buffer in data
; page MD*1.
;
; Increments the mapBufferCount variable to track the number of words inserted.
;
; If the tracking byte has changed, the new value is stored with the data
; point in the buffer as a control code.
;

storeWallValueInMapBuffer:

	ldu     wallPeakBuffer, A       ; load the latest wall value
									; first element in buffer is raw wall

	call	storeWordInMapBuffer

	; if the tracking value has changed from non-zero to zero indicating a Track reset,
	; save the previous non-zero value inline with the wall data as a control code

	ldu		trackCount, A			; get the current tracking value as unsigned int
	bc		$1,ANEQ					; bail out if it is not zero; reset has not occurred

	ldu		previousMapTrack, A		; check if previous value was zero
	bc		$1,AEQ					; if was zero, still in reset condition

	or		#0x8000, A				; set the top bit to designate as a control code

	call	storeWordInMapBuffer	; store the control code in the map buffer

$1:	ldu		trackCount, A			; save current tracking value for future comparison
	stl		A, previousMapTrack

	ret

	.newblock                       ; allow re-use of $ variables

; end of storeWallValueInMapBuffer
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; applyGainToEntireSampleSet
;
; Applies value in variable softwareGain (set by host) to the entire sample
; set.  This is for use when the DAC is disabled so that the global gain
; gets applied to the data.  When the DAC is enabled, the DAC gates are
; processed to apply gain to each DAC section of the data.
;
; NOTE: Call this function after processing the interface gate.  That gate
; applies softwareGain as it is processing the data.
;

applyGainToEntireSampleSet:

	ld      #PROCESSED_SAMPLE_BUFFER, A ;start of buffer
	and     #0ffffh, A              	;remove sign - pointer is unsigned
	stlm    A, AR3                  	; set AR3 & AR4 to buffer start location
	stlm    A, AR4

	ld      adSampleSize, A         ; load size of processed data buffer
	sub     #1, A                   ; block repeat uses count-1
	stlm    A, BRC                  ; buffer has two samples per word

	; see notes in header of setSoftwareGain function for details on -9 shift

	ld      #7, ASM                 ; use shift of -9 for storing (shift=ASM-16)
	ld      softwareGain, A         ; get the global gain value
	stlm    A, T                    ; preload T with the gain multiplier

	ld      *AR3+,16,A              ; preload first sample, shifting to
                                        ; upper word of A where mpy expects it


	; loop ~ apply DAC section gain to each sample -------------------

	rptb    $3

	mpya    A                       ; multiply upper sample in A(32-16) by T
                                        ; and store in A

$3:	st      A, *AR4+                ; shift right by 9 (using ASM) and store,
	|| ld   *AR3+, A                ; load the next sample into upper A
									; where mpy expects it

	; loop end -------------------------------------------------------

	ret

	.newblock                       ; allow re-use of $ variables

; end of applyGainToEntireSampleSet
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processDAC
;
; Processes all DAC sections(gates), applying the gain specified for each
; section to the data buffer.
;

processDAC:

	; cannot use block repeat for this AR5 loop because the block
	; repeat is used in some functions called within this loop and there
	; is only one set of block repeat registers - most efficient use is
	; block repeat for the inner loops

	stm     #9, AR5                 ; loop counter to process all gates

$2:	ldm     AR5, A                  ; use loop count as gate index

	call    pointToDACInfo          ; point AR2 to the info for DAC index in A
									;  also stores index in A in scratch1
									;  for later calls to pointToDACResults

	bitf    *AR2, #GATE_ACTIVE      ; function flags - check if gate is active
	bc      $8, NTC                 ; bit not set, skip this gate

	; adjust each gate to be relative to the start of the sample buffer or the
	; interface crossing if the gate is flagged to track the interface

	pshm    AR2                     ; save gate info pointer
	call    setGateAdjustedStart
	popm    AR2                     ; restore gate info pointer
	nop                             ; pipeline protection

	; apply the gain associated with each DAC section (gate) to the samples

	mar     *AR2+                   ; skip the flags
	mar     *AR2+                   ; skip the MSB raw start location
	mar     *AR2+                   ; skip the LSB

	ldu     *AR2+, A                ; set AR3 & AR4 to adjusted start location
	stlm    A, AR3
	stlm    A, AR4

	ld      *AR2+, A                ; set block repeat counter to the
	sub     #1, A                   ; gate width / 3, subtract 1 to account
	stlm    A, BRC                  ; for loop behavior

	; see notes in header of setSoftwareGain function for details on -9 shift

	ld      #7, ASM                 ; use shift of -9 for storing (shift=ASM-16)
	ld      *AR2+, A                ; get the DAC gate gain
	stlm    A, T                    ; preload T with the gain multiplier

	ld      *AR3+,16,A              ; preload first sample, shifting to
									; upper word of A where mpy expects it


	; loop ~ apply DAC section gain to each sample -------------------

	rptb    $3

	mpya    A                       ; multiply upper sample in A(32-16) by T
									; and store in A

$3:	st      A, *AR4+                ; shift right by 9 (using ASM) and store,
	|| ld	*AR3+, A                ; load the next sample into upper A
									; where mpy expects it

	; loop end -------------------------------------------------------


$8:	banz    $2, *AR5-               ; decrement DAC gate index pointer

	ret

	.newblock                       ; allow re-use of $ variables

; end of processDAC
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processGates
;
; Processes all gates: finding the interface crossing, adjusting all start
; positions, finding signal crossings if enabled, max peaks if enabled.
;
; On entry, DP should point to Variables1 page.
;
; The interfaceGateIndex, wallStartGateIndex, wallEndGateIndex variables
; are set to ffffh if those gates are not set up.  If they are setup, the
; variables will point to those gates and thus their top bits will be
; zeroed. Checking the top bit can tell if the gate is setup and in use.
;
; The interface gate gets processed twice. It is first used to find the signal
; crossing point in that gate which is then used to adjust the position of all
; other gates for which gate interface tracking enabled. During that processing,
; the software gain is applied to the signal in the gate, even if no DAC gate
; covers that area. This is necessary because the signal crossing is searched
; for before the DAC or software gain is applied -- the signal only has the
; hardware gain applied. This is necessary since the DAC gates also track the
; interface crossing, so that must be found before the DAC can be applied.
;
; The interface gate is then processed again along with the other gates in the
; processing loop as a regular gate. The findInterfaceGateCrossing function used
; to find the crossing point (as mentioned above) forces off the tracking flag
; for the interface gate so it doesn't try to track itself when the gate is
; processed again in the loop. When processed in the loop, gain is not applied
; by default so if the DAC is enabled and the signal from the interface gate is
; to be used in some manner by the host with the DAC enabled, a DAC gate should
; be placed over the interface gate area so the signal will be valid. With DAC
; disabled, the software gain is applied over the entire signal anyway.
;
; NOTE 1: If the interface gate is present, no gates will be processed if a signal
; crossing is not found in the interface gate. This is because the gates'
; positions cannot be determined if the interface is not detected. Technically,
; each gate can be independently set for tracking or non-tracking, but the host
; software currently makes all gates the same mode.
;
; NOTE 2: If the interface gate is present but no interface is detected, the
; DAC gain will not be applied as it is complex to determine which gates are
; tracking/non-tracking and the gain cannot be applied to the gates without
; adjusting their position to the interface. Thus, when the DAC is enabled and
; an interface gate is present with no detectable interface, no DAC gain will
; be applied even if tracking is disabled. In such a case, no software gain at
; all will be applied to the sample set until a signal exceeds the interface
; gate. This can be confusing to the user as it will appear that the software
; gain is unresponsive.
;
; NOTE 2a: Standard procedure is to turn off the DAC, apply software gain
; and adjust the interface gate as required to obtain a good interface signal
; in the interface gate. The DAC and tracking (if desired) should then be
; enabled and the DAC gates adjusted as required while an interface signal is
; exceeding the interface gate. The interface gate always uses software gain
; without DAC gain in any case, so adjusting it with the DAC off has no effect.
;
; NOTE 3: A gate can still be designated non-tracking if the interface gate is
; active, but that gate will not be processed if the interface is not found
; even though that gate does not need it for positioning -- NO gates (tracking
; or non-tracking) are processed if no crossing found in an active interface
; gate.
;

processGates:

	; if bit 15 of interfaceGateIndex is zeroed, interface gate has been set so
	; process it to find the interface crossing point and adjust the
	; other gates if they are using interface tracking
	; (see notes at top of this function for more explanation)

	ld      #0, A			; preload A with interface found flag

	orm     #IFACE_FOUND, processingFlags1
                                        ; preset the interface found flag to true
                                        ; if iface gate is not active, then the
                                        ; flag will be left true so remaining
                                        ; gates will be processed

	bitf    interfaceGateIndex, #8000h
	cc      findInterfaceGateCrossing, NTC

	; apply gain to entire sample set if DAC not enabled -- see Note 2 in header

	bitf    flags1, #DAC_ENABLED    
	cc      applyGainToEntireSampleSet, NTC

    ;don't process remaining gates if interface not found -- see Notes 1,3 in header

	bitf    processingFlags1, #IFACE_FOUND
	rc      NTC

	; apply DAC gain to DAC gates if DAC enabled -- see Note 2 in header
	; (don't do this if interface gate is present but no interface found)

	bitf    flags1, #DAC_ENABLED    ; process DAC if it is enabled
	cc      processDAC, TC          ;  applies gain for each DAC gate to sample set

	; cannot use block repeat for this AR5 loop because the block
	; repeat is used in some functions called within this loop and there
	; is only one set of block repeat registers - most efficient use is
	; block repeat for the inner loops

	stm     #9, AR5                 ; loop counter to process all gates

$2:	ldm     AR5, A                  ; use loop count as gate index

	pshm    AR5                     ; save loop counter as some calls below destroy AR5

	call    pointToGateInfo         ; point AR2 to the info for gate index in A
									;  also stores index in A in scratch1

	bitf    *AR2, #GATE_ACTIVE      ; function flags - check if gate is active
	bc      $8, NTC                 ; bit not set, skip this gate

	; adjust each gate to be relative to the start of the sample buffer or the
	; interface crossing if the gate is flagged to track the interface

	pshm    AR2						; save gate info pointer
	call    setGateAdjustedStart
	popm    AR2                     ; restore gate info pointer
	nop                             ; pipeline protection

	pshm    AR2						; save gate info pointer
	call    processWallGates		; if this is a wall gate, handle accordingly
	popm    AR2                     ; restore gate info pointer
	nop                             ; pipeline protection

	bc      $8, AEQ					; skip to next gate if current gate was handled
									; as a wall gate by processWallGates

	bitf    *AR2, #GATE_FIND_PEAK   ; find peak if bit set
	bc      $5, NTC

	pshm    AR2                     ; save gate info pointer
	call    findGatePeak            ; records signal peak in the gate
	popm    AR2                     ; restore gate info pointer
	nop                             ; pipeline protection

$5:	bitf    *AR2, #GATE_INTEGRATE_ABOVE_GATE    ; find integral above gate level if bit set
	bc      $6, NTC

	pshm    AR2						; save gate info pointer
	call    calculateGateIntegral   ; records integral of signal above gate level
	popm    AR2                     ; restore gate info pointer
	nop                             ; pipeline protection

$6:	bitf    *AR2, #GATE_QUENCH_ON_OVERLIMIT	; skip all remaining gates if the integral
	bc      $8, NTC                 ; above the gate is greater than trigger level
									; WARNING: this section must be after the
									; GATE_INTEGRATE_ABOVE_GATE section as it
									; uses the result from that call

	pshm    AR2                     ; save gate info pointer

	; wip mks -- call function to check for over limit here
	; problem -- the gates are processed from gate 9 to gate 0 because the loop counter is used as the
	; 	gate index (see above). Thus, trying to quench gates after the interface on overlimit in the
	;	interface gate won't work! Need to reverse order of gate processing before this section is
	;	implemented.

	ld      #0, A	;wip mks - remove this after adding quench check

	popm    AR2                     ; restore gate info pointer
	nop                             ; pipeline protection

    ; cease processing remaining gates if over limit detected

	bc      $8, AEQ                 ; if A=0, continue processing remaining gates
	popm    AR5                     ; if A!=0, stop processing gates
	b       $9                      ;  all remaining gates are ignored

$8:	popm    AR5                     ; restore loop counter
	nop                             ; pipeline protection

	banz    $2, *AR5-               ; decrement gate index pointer

$9:	; Check if Wall readings need to be processed.

	; if either the wall start or end gates have not been set, then exit
	; the entries default to ffffh and the top bit will be set unless those
	; entries have been changed to the index of a wall gate


	bitf    wallStartGateIndex, #8000h
	rc      TC

	bitf    wallEndGateIndex, #8000h
	rc      TC

	; if in mapping mode, a wall reading is saved to the buffer for every shot even if one or
	; more gates were not triggered -- previous reading will be used if new one is not available

	; debug mks -- this only gets done if the interface gate is triggered because processGates
	;	bails out immediately if no interface detected; to change this, instead of returning, it
	; 	could jump to a section which duplicates the next two lines and then return

	bitf    flags1, #DSP_WALL_MAP_MODE	; if in wall map mode, save the value to the map buffer
	cc      storeWallValueInMapBuffer, TC

	; check to see if the interface was found, the first wall reflection was
	; found, and the second wall reflection was found
	; exit if any were missed - the signal will be ignored

	bitf    processingFlags1, #IFACE_FOUND          ; interface check
	rc      NTC

	bitf    processingFlags1, #WALL_START_FOUND     ; first reflection check
	rc      NTC

	bitf    processingFlags1, #WALL_END_FOUND       ; second reflection check
	rc      NTC

	b       processWall                     ; calculate the wall thickness

	.newblock                               ; allow re-use of $ variables

; end of processGates
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processWallGates
;
; If the gate is a Wall start or end gate, it is processed accordingly.
; If not a Wall gate, does nothing.
;
; The GATE_MAX_MIN flag for any gate used for wall measurement will be cleared
; here. The host generally sets the wall start gate to a MAX gate and the wall
; end gate to a MIN gate so it's peak catching code in the host can trap the
; max and min wall values in those gates. However, all gates need to be MAX
; gates for the DSP code to function properly for wall measurement. Hence, all
; wall gates are forced to be MAX gates in this function. The DSP's peak
; trapping code for wall ignores the gates' MIN/MAX flag.
;
; On exit:
; If the gate is a Wall start or end gate, the A register returns 0 to signal
; that the gate was handled in this function. Otherwise, A register returns -1.
;

processWallGates:

	bitf    *AR2, #GATE_WALL_START  ; find crossing if gate is used for wall start
	bc      $3, NTC

	andm    #~GATE_MAX_MIN, *AR2    	; force gate to be a MAX gate

	bitf    *AR2, #GATE_FIND_CROSSING   ; use signal crossing if true
	pshm	AR2
	cc      findGateCrossing, TC
	popm	AR2
	nop									; pipeline protection

	bitf    *AR2, #GATE_FIND_PEAK   	; use signal peak if true
	pshm	AR2
	cc      findGatePeak, TC
	popm	AR2
	nop									; pipeline protection

	andm    #~WALL_START_FOUND, processingFlags1 ; clear the found flag

	xc      2, AEQ                  ; if A returned 0 from function call,
									; set the found flag -- crossing found
									; or peak was above gate

	orm     #WALL_START_FOUND, processingFlags1

	ld      #0, A                   ; return 0 - gate was handled as a Wall gate

	ret

$3:	bitf	*AR2, #GATE_WALL_END    ; find crossing if gate is used for wall end
	bc      $4, NTC

	andm    #~GATE_MAX_MIN, *AR2    ; force gate to be a MAX gate

	bitf    *AR2, #GATE_FIND_CROSSING   ; use signal crossing if true
	pshm	AR2
	cc      findGateCrossing, TC
	popm	AR2
	nop									; pipeline protection

	bitf    *AR2, #GATE_FIND_PEAK   ; use signal peak if true
	pshm	AR2
	cc      findGatePeak, TC
	popm	AR2
	nop									; pipeline protection

	andm    #~WALL_END_FOUND, processingFlags1 ; clear the found flag

	xc      2, AEQ                  ; if A returned 0 from function call,
									; set the found flag -- crossing found
									; or peak was above gate

	orm     #WALL_END_FOUND, processingFlags1

	ld      #0, A                   ; return 0 - gate was handled as a Wall gate

	ret

$4:	

	ld      #-1, A                  ; return -1 as gate was not a Wall gate

	ret

	.newblock					; allow re-use of $ variables

; end of processWallGates
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; getPeakData
;
; Returns the data peaks collected since the last call to this function and
; resets the peaks in preparation for new ones.
;
; All gates will be checked, the data for any enabled gate will be added
; to the packet.  The packet size will vary depending on the number of enabled
; gates.  The data will be returned in order of the gates, 0 first - 9 last.
;
; On entry, AR3 should be pointing to word 2 (received packet data size) of
; the received packet.
;

getPeakData:

	ld      #Variables1, DP

	stm     #0, AR2                         ; tracks number of gate data bytes sent

	stm     #9, BRC                         ; check for peaks from 10 gates

	stm     #SERIAL_PORT_XMT_BUFFER+6, AR3	; point to first data word after header
	stm     #gateBuffer+1, AR4              ; point to gate info buffer (flags of first gate)
	stm     #gateResultsBuffer+1, AR5       ; point to gate results (flags of first gate)

; start of peak collection block

	rptb    $1

	bitf    *AR4, #GATE_ACTIVE              ; check if gate enabled
	bc      $2, TC                          ; bit 0 set, send gate's data

	mar     *+AR4(GATE_PARAMS_SIZE)         ; move to parameters for next gate
	mar     *+AR5(GATE_RESULTS_SIZE)        ; move to results for next gate
	b       $1

$2:

	mar     *+AR2(8)                ; count bytes sent (8 per gate for peak data)

	ldu     *AR4, A                 ; get the gate flags and mask for the max/min
	and     #GATE_MAX_MIN, A        ; flag so it can be transferred to the results
									; flag so the host will know gate type
									; it is transferred repeatedly because the results
									; flag is zeroed each time

	adds    *AR5, A                 ; add the gate type flag to the results flags
	st      #0, *AR5                ; zero the results flags

	stl     A, -8, *AR3+            ; store flag high byte in serial out buffer
	stl     A, *AR3+                ; low byte

	mar     *+AR5(8)                ; move to the peak value

	bitf    *AR4, #GATE_MAX_MIN     ; function flags - check gate type
									; need two instructions before xc (pipeline)

	ld      #0x8000, B              ; reset peak with min value to search for max

	ld      *AR5, A                 ; load the peak value

	xc      2, TC                   ; max or min gate decides reset value
	ld      #0x7fff, B              ; reset peak with max value to search for min
									; TC set from bitf above gate is a min

	stl     B, *AR5+                ; set peak to appropriate reset value

	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5, A                 ; load the peak's buffer address
	st      #0, *AR5+               ; zero the address

	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5, A                 ; load the peak's tracking value
	st      #0, *AR5+               ; zero the tracking location

	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	mar     *+AR4(GATE_PARAMS_SIZE)	; move to flags of next gate info

	mar     *+AR5(GATE_RESULTS_SIZE-11) ; move to results flags of next gate

$1: nop

; end of peak collection block

	; if both wall start and end gates have not been set, don't send wall data

	bitf    wallStartGateIndex, #8000h
	bc      $3, TC

	bitf    wallEndGateIndex, #8000h
	bc      $3, TC

	; transfer wall max peak data

	stm     #wallPeakBuffer+5, AR5  ; point to wall max peak data

	ld      *AR5, A                 ; load the max peak value
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      #0x8000, B              ; reset peak with min value to search for max
	stl     B, *AR5+                ; set peak to appropriate reset value

	; transfer the fractional time data - no need to reset to min or max

	ld      *AR5+, A                ; numerator start gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; denominator start gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; numerator end gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; denominator end gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; tracking value
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	; transfer wall min peak data

	ld      *AR5, A                 ; load the min peak value
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      #0x7fff, B              ; reset peak with max value to search for min
	stl     B, *AR5+                ; set peak to appropriate reset value

	; transfer the fractional time data - no need to reset to min or max

	ld      *AR5+, A                ; numerator start gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; denominator start gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; numerator end gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; denominator end gate
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	ld      *AR5+, A                ; tracking value
	stl     A, -8, *AR3+            ; high byte
	stl     A, *AR3+                ; low byte

	mar     *+AR2(24)               ; add in bytes for wall data

$3:

	ldm     AR2, A                  ; size of gate data in buffer

	ld      #DSP_GET_PEAK_DATA, B   ; load message ID into B before calling

	b       sendPacket              ; send the data in a packet via serial

	.newblock                       ; allow re-use of $ variables

; end of getPeakData
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processSamples
;
; Processes a new set of A/D samples placed in memory by the FPGA via the
; HPI bus.  The A/D samples are packed - two sample bytes in each word.
; This function unpacks the bytes as it transfers them.
;
; On entry:
;
; A should be zero.
;
; DP should point to Variables1 page.
;
; AR3 should point to the last position of the buffer which will have
; been set to non-zero by the FPGA after writing a sample set.
;
; On exit, the buffer ready flag will be set to 0000h.
;
; The FPGA stores a flag as the last word of the data set.  The most
; significant bit is always 1 while the 15 lower bits specify the frame
; count for the data set.  Since each DSP core processes every other
; data set as the FPGA alternates between two cores for each channel,
; the counter flag will appear to be incremented by two between each
; set.  This counter is compared with the counter from the previous set
; and if there are more than two counts between them it indicates that
; a data set was not properly stored and was missed.  In this case, the
; frameSkipErrors counter will be incremented.
;
; The frame counter will be incremented each time a data set is processed.
; This counter can be retrieved by the host and compared with the number
; of skipped frame errors to determine the error rate.
;
; NOTE: MACD vs FIRS
;
; Using the FIRS instruction can cut the convolution time in half, but
; FIRS requires the use of circular buffers to be efficient as it does
; not shift the data. As the buffer pointers (ARx registers) only have
; to be loaded once as the circular setup leaves them pointing at the
; position for the next data point after convolution means that the setup
; time is minimal.
;
; PROBABLY a good idea to switch this code to using FIRS, complicated
; though it may be.
;

processSamples:

	ld      freeTimeCnt1, 16, B     ; load 32 bit free time counter
	adds    freeTimeCnt0, B         ;  (used to calculate the amount of free
	sth     B, freeTime1            ; store free time value for retrieval by host
	stl     B, freeTime0

	st      #00h, freeTimeCnt1      ; zero the free time counter
	st      #00h, freeTimeCnt0

	; A register contains the data set count flag - mask the top bit
	; which is always set to 1 by the FPGA

	and     #7fffh, A
	ld      A, 0, B                 ; store the flag in the B register

	subs    frameCountFlag, A       ; compare new counter with previous one
	bc      $2, AEQ                 ; if the counters match, no error

	ld      frameSkipErrors, A      ; increment the error count
	add     #1, A
	stl     A, frameSkipErrors

$2:	add     #2, B                   ; increment the flag by 2 (each DSP gets every
									;  other frame),
	and     #7fffh, B               ; mask the top bit,
	stl     B, frameCountFlag       ; and store it so it will be ready for
									;  the next data set check

	ld      #0, A                   ; clear the ready flag at the end of the
	stl     A, *AR3                 ; sample buffer

	; increment the frame counter to track the number of data sets processed

	ld      frameCount1, 16, A      ; load 32 bit frame counter
	adds    frameCount0, A
	add     #1, A
	sth     A, frameCount1
	stl     A, frameCount0

	; prepare pointers to source and destination buffers

	stm     #FPGA_AD_SAMPLE_BUFFER, AR2     ; point to tracking word at start of buffers
	stm     #PROCESSED_SAMPLE_BUFFER, AR3   ;(stm has no pipeline latency problem)

	nop

	ld      *AR2+, A                ; load the tracking value for this sample set
									; this can be linear or rotational position tracking
									; depending on the system

	stl     A, trackCount           ; store it for tagging the peak data

	ld      adSamplePackedSize, A   ; load size of FPGA buffer
	sub     #1, A                   ; block repeat uses count-1
	stlm    A, BRC                  ; buffer has two samples per word

	; transfer the samples from the FPGA buffer to the processed buffer
	; split each word into one two-byte samples (the FPGA packs two samples
	; into each word)

	; process without filtering if filter as zero coefficients, filter otherwise

	ld		numCoeffs, A
	cc		processSamplesWithoutFilter, AEQ

	ld		numCoeffs, A
	cc		processSamplesWithFilter, ANEQ

	call    disableSerialTransmitter    ; call this often

	bitf    flags1, #GATES_ENABLED      ; process gates if they are enabled
	cc      processGates, TC            ; also processes the DAC

	call    disableSerialTransmitter    ; call this often

	call    processAScan                ; store an AScan dataset if enabled

	call    disableSerialTransmitter    ; call this often

	ret

	.newblock                           ; allow re-use of $ variables

; end of processSamples
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processSamplesWithoutFilter
;
; Extracts each dual-byte stuffed word into two samples and stores each in
; the processed signal buffer.
;
; On entry, DP should point at Variables1 page.
;

processSamplesWithoutFilter:

	ld      #-8, ASM                ; load constant into ASM register
									; for parallel LD||ST, this causes shift of
									; -24 for the save (shift=ASM-16)
									; this shifts the highest byte to the lowest

	ld      *AR2,16,A               ; preload the first sample pair - shift
									; to AHi to be compatible with code loop

; start of transfer block

	rptb    $1                      ; transfer all samples

rect1:
	nop                             ; this nop gets replaced with an instruction
									; which performs the desired rectification
									;  nop for positive half and RF, neg for
									; negative half, abs for full

	st      A, *AR3+                ; shift right by 24 (using ASM) and store
	|| ld   *AR2+, A                ; reload the same pair again to process
									; lower sample - this function shifts the
									; packed samples to A(32-16) as it loads

	stl     A, -8, scratch1         ; shift down and store the lower sample
									; this will chop off the upper sample and
									; fill the lower bits with zeroes (2)

	ld      scratch1, 16, A         ; reload the value into upper A, extending
									; the sign

rect2:
	nop                             ; this nop gets replaced with an instruction
									; which performs the desired rectification
									;  nop for positive half and RF, neg for
									; negative half, abs for full

$1:
	st      A, *AR3+                ; shift right by 24 (using ASM) and store
	|| ld   *AR2, A                 ; load the next pair without inc of AR2
									; this function shifts the packed samples
									; to A(32-16) as it loads

; end of transfer block

	ret

	.newblock

; end of processSamplesWithoutFilter
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; processSamplesWithFilter
;
; Extracts each dual-byte stuffed word into two samples and runs each sample
; through a FIR filter before storing in the processed signal buffer.
;
; On entry, DP should point at Variables1 page.
;

processSamplesWithFilter:

	ld		#firBuffer, A			; save in AR1 for quick access without modifying DP
	stlm	A, AR1

	ld      #Variables1, DP

	ld		filterScale, ASM		; get number of bits to right-shift filter output to fit into a word

; start of transfer block

	rptb    $1                      ; transfer all samples

	; process upper byte packed in the word

	ld		*AR2+, B				; load dual-byte with sign extension for high byte
	stl		B, -8, *AR1				; store upper byte at top of filter buffer for filtering

	ld		firBufferEnd, A			; convolution start point (from bottom of buffer)
	stlm	A, AR0
	ld      #00h, A					; clear for summing in MACD

	rpt		numFIRLoops				; FIR filter convolution
	macd	*AR0-, coeffs1, A

rect3:
	nop                             ; this nop gets replaced with an instruction
									; which performs the desired rectification
									;  nop for positive half and RF, neg for
									; negative half, abs for full

	stl		A, ASM, *AR3+			; store filter output in the processed buffer
									; result is shifted by ASM bits

	; process lower byte packed in the word (still in register B)

	; shift/save/load to isolate lower byte and achieve proper sign extension
	;  the top of the filter buffer is used as a scratch variable for this operation

	stl		B, 8, *AR1				; shift lower byte to upper byte and store
									; lower 8 bits will be zeroed

	ld		*AR1, 16, B				; reload, shifting to upper byte of upper word
									; this causes the proper sign extension

	sth		B, -8, *AR1				; shift byte to lower byte and save at top of filter buffer for filtering

	ld		firBufferEnd, A			; convolution start point (from bottom of buffer)
	stlm	A, AR0
	ld      #00h, A					; clear for summing in MACD

	rpt		numFIRLoops				; FIR filter convolution
	macd	*AR0-, coeffs1, A

rect4:
	nop                             ; this nop gets replaced with an instruction
									; which performs the desired rectification
									;  nop for positive half and RF, neg for
									; negative half, abs for full

$1:	stl		A, ASM, *AR3+			; store filter output in the processed buffer
									; result is shifted by ASM bits

; end of transfer block

	ret

	.newblock

; end of processSamplesWithFilter
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; setupGatesDACs
;
; Zeroes the gate and DAC section variables and sets the identifier number
; for each.
;

setupGatesDACs:

	ld      #0h, B                  ; used to zero variables

; set the ID number for each gate and zero its values

	stm     #gateBuffer, AR1        ; top of buffer
	ld      #0, A                   ; start with ID number 0
	stm     #9, BRC                 ; do 10 gates/sections

	rptb    $2

	stm     #GATE_PARAMS_SIZE-2, AR2    ; zeroes per entry -- 1 less to account for loop
										; behavior, 1 more less because ID fills a space


	stl     A, *AR1+                ; set the ID number
	add     #1, A                   ; increment to next ID number
$1:	stl     B, *AR1+                ; zero the rest of the entry
	banz    $1, *AR2-

$2: nop								; end of repeat block

; set the ID number for each DAC section and zero its values


	stm     #dacBuffer, AR1         ; top of buffer
	ld      #0, A                   ; start with ID number 0
	stm     #9, BRC                 ; do 10 DAC sections

	rptb    $4

	stm     #DAC_PARAMS_SIZE-2, AR2 ; zeroes per entry -- 1 less to account for loop
									; behavior, 1 more because ID fills a space

	stl     A, *AR1+                ; set the ID number
	add     #1, A                   ; increment to next ID number
$3:	stl     B, *AR1+                ; zero the rest of the entry
	banz    $3,	*AR2-

$4: nop								; end of repeat block

; set the ID number for each gate results section and zero its values

	stm     #gateResultsBuffer, AR1 ; top of buffer
	ld      #0, A                   ; start with ID number 0
	stm     #9, BRC                 ; do 10 gate results entries

	rptb    $6

	stm     #GATE_RESULTS_SIZE-2, AR2   ; zeroes per entry -- 1 less to account for loop
										; behavior, 1 more because ID fills a space

	stl     A, *AR1+                ; set the ID number
	add     #1, A                   ; increment to next ID number
$5:	stl     B, *AR1+                ; zero the rest of the entry
	banz    $5, *AR2-

$6:	nop								; end of repeat block

	.newblock                       ; allow re-use of $ variables

; end of setupGatesDACs
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; disableSerialTransmitter
;
; If the DMA has finished transmitting, disable the transmitter so that
; another core can send data on the shared McBSP1 serial port.
;
; NOTE: This function MUST be called as often as possible to release the
;  transmitter for another core as quickly as possible.
;

disableSerialTransmitter:

	ld      #Variables1, DP             ; point to Variables1 page

	bitf    processingFlags1, #TRANSMITTER_ACTIVE	; check if transmitter is active
	rc      NTC                         			; do nothing if inactive

	ld      #00, DP                     ; must set DP to use bitf
	bitf    DMPREC, #04h                ; DMA still enabled, not finished, do nothing
	ld      #Variables1, DP             ; point to Variables1 page before return
	rc      TC                          ; AutoInit is disabled, so DMA clears this
										; enable bit at the end of the block transfer

	; wait until XEMPTY goes low for shift register empty - even when the
	; element count reaches zero for the DMA, the transmitter may still
	; be sending the last value

	stm     #SPCR2, SPSA1               ; point subaddressing register
	ld      #00, DP                     ; must set DP to use bitf
	bitf    SPSD1, #04h                 ; check XEMPTY (bit 2) to see if all data sent
	ld      #Variables1, DP             ; point to Variables1 page before return
	rc      TC                          ; if bit=1, not empty so loop

	stm     #00h, SPSD1                 ; SPCR2 bit 0 = 0 -> place xmitter in reset

	andm    #~TRANSMITTER_ACTIVE, processingFlags1	; clear the transmitter active flag

	ret

; end of disableSerialTransmitter
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; resetMapping
;
; Resets all buffer pointers, counters, etc. related to storing and transmitting
; map data.
;

resetMapping:

	ld      #Variables1,DP

	st      #MAP_BUFFER, mapBufferInsertIndex	; prepare circular map buffer by
	st      #MAP_BUFFER, mapBufferExtractIndex  ; setting all indices to the base address
	st		#0, mapBufferCount					; start with zero words in the buffer
	st		#0, previousMapTrack				; start with zero for the track value comparison variable
	st		#0, mapPacketCount					; start with zero for the map packet count

	ret

; end of resetMapping
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; main
;
; This is the main execution startup code.
;

main:

; The input clock frequency from the FPGA is 8.33 Mhz (120 ns period).
; The PLL must be initialized to multiply this by 12 to obtain an operating
; frequency of 100 Mhz (10 ns period).

; 1011011111111111b (b7ffh)
;
; bits  15-12   = 1011          : Multiplier = 12 (value + 1) (PLLMUL)
; bit	11      = 0             : Integer Multiply Factor (PLLDIV)
; bits 	10-3    = 11111111      : PLL Startup Delay (PLLCOUNT)
; bit 	2       = 1             : PLL On   (PLLON/OFF)
; bit 	1       = 1             : PLL Mode (PLLNDIV)
; bit 	0       = 1             : PLL Mode (STATUS)
;

	ld      #Variables1,DP

	stm     endOfStack, SP          ; setup the stack pointer

	;note mks - for simulation, block out the next line after running the
	;		     code once -- the first time is useful to clear the variables
	;			 and set the index numbers for readability but then it may be
	;			 commented out for subsequent program runs if data is loaded from
	;			 disk for the Gates & DACs - otherwise this next call will erase
	;			 the data each time and it will have to be reloaded repeatedly
	;  !!re-insert the line when not simulating!!
	;  Clarification -- you need the next line for actual code!

	call    setupGatesDACs              ; setup gate and DAC variables

	st      #00h, flags1
	st      #00h, breakPointControl
	st      #00h, aScanDelay
	st      #512, softwareGain          ; default to gain of 1
	st      #1234h, trackCount
	st      #00h, reSyncCount
	st      #00h, hitCountThreshold
	st      #00h, missCountThreshold
	st      #01h, aScanScale
	st      #00h, frameCount1
	st      #00h, frameCount0
	st      #00h, frameSkipErrors
	st      #00h, frameCountFlag
	st      #00h, processingFlags1
	st      #00h, heartBeat
	st      #00h, freeTimeCnt1
	st      #00h, freeTimeCnt0
	st		#00h, numCoeffs
	st		#firBuffer+MAX_NUM_COEFFS-1, firBufferEnd

	st      #0ffffh, interfaceGateIndex     ; default to no gate index set
	st      #0ffffh, wallStartGateIndex     ; default to no gate index set
	st      #0ffffh, wallEndGateIndex       ; default to no gate index set

	st      #01h, adSamplePackedSize    ; The program will attempt to process a
										; sample set on startup before data pointers
										; and lengths are set - set this value to
										; 1 so that only a single data point will
										; be processed until real settings are
										; transferred by the host.  Related variables
										; don't have to be set because only processing
										; a single point won't cause any problems.

	stm     #00h, CLKMD					; must turn off PLL before changing values
										; (not explained very well in manual)
	nop									; give time for system to exit PLL mode
	nop
	nop
	nop

	ld      #0b7ffh, A
	stlm    A, CLKMD

	ldm     CLKMD, A					; store clock mode register so it can be
	stl     A, Variables1				; viewed with the debugger for verification

										; NOTE - only Core A can read or set CLKMD
										; Variables1 will be random for other cores

	ldm     CSIDR, A					; load the DSP Core ID number - this lets
                                        ; the software know which core it is running on

	and     #0fh, A						; lowest 4 bits are the ID (extra bits may be
										; used on future chips with more cores)

	add     #1, A						; the ID is zero based while packets from the
                                        ; host are one based - adjust here to match

	stl     A, coreID					; save the DSP ID core

	call	resetMapping				; reset all mapping control variables

	call    setupSerialPort				; prepare the McBSP1 serial port for use

	call    setupDMA					; prepare DMA channel(s) for use

	; clear data buffers used for averaging
	ld      #8000h, A
	stlm    A, AR1
	rptz    A, #7fffh
	stl     A, *AR1+

	; clear FIR filter buffer
	stm    	#firBuffer, AR1
	rptz    A, #MAX_NUM_COEFFS		; this will clear one more than MAX_NUM_COEFFS -- the buffer has an extra location
	stl     A, *AR1+

	;debug mks -- fill FIR filter buffer with incrementing value

	stm		#0, AR0
	stm    	#firBuffer, AR1
	stm		#MAX_NUM_COEFFS, BRC	; this will clear one more than MAX_NUM_COEFFS -- the buffer has an extra location
	rptb    $1
	ldm		AR0, A
	stl     A, *AR1+
$1:	mar		*AR0+

	;debug mks

	.if     debugger                ; perform setup for debugger functions
	call    initDebugger
	.endif

	b       mainLoop					; start main execution loop

	.newblock							; allow re-use of $ variables

; end of main
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; mainLoop
;
; This is the main execution code loop.
;

mainLoop:

$1:

	.if     debug                   ; see debugCode function for details
	call    debugCode
	.endif

	ld      #Variables1, DP         ; point to Variables1 page

	ld      heartBeat, A            ; increment the counter so the user can
	add     #1, A                   ; see that the program is alive when using
	stl     A, heartBeat            ; the debugger

	ld      freeTimeCnt1, 16, A     ; load 32 bit free time counter
	adds    freeTimeCnt0, A         ;  (used to calculate the amount of free
	add     #1, A                   ;   time between processing each data set
	sth     A, freeTimeCnt1         ;   this value is reset for each new data set)
	stl     A, freeTimeCnt0

; process signal samples if enabled

	bitf    flags1, #PROCESSING_ENABLED 
	bc      $2, NTC

	; check if FPGA has uploaded a new sample data set - the last value in
	; the buffer will be set to non-zero if so

	ld      fpgaADSampleBufEnd, A   ; get pointer to end of FPGA sample buffer
	stlm    A, AR3
	nop                             ; pipeline protection
	nop
	ld      *AR3, A                 ; get the flag set by the FPGA
	cc		processSamples, ANEQ    ; process the new sample set if flag non-zero

$2:	call    disableSerialTransmitter    ; call this often

	call    readSerialPort          ; read data from the serial port

; check to see if a packet is being sent and disable the serial port transmitter
; when done so that another core can send data on the shared McBSP1

	call    disableSerialTransmitter    ; call this often

	b   $1

	.newblock                       ; allow re-use of $ variables

; end of mainLoop
;-----------------------------------------------------------------------------
