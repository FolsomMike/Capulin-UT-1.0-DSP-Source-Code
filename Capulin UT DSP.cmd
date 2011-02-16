/*****************************************************************************/
/*                                                                           */
/*	Capulin UT DSP.cmd                                                       */
/*  	Mike Schoonover 5/19/2009                                            */
/*                                                                           */
/*	This linker command file is used with "Capulin UT DSP.asm".              */
/*                                                                           */
/*	Description                                                              */
/*	===========                                                              */
/*                                                                           */
/*	This is the linker command file for "Capulin UT DSP.asm".                */
/*                                                                           */
/*	Instructions                                                             */
/*	============                                                             */
/*                                                                           */
/*                                                                           */
/*                                                                           */
/*                                                                           */
/*****************************************************************************/

"Capulin UT DSP.obj"				/* this is the input file from asm500.exe */
-o "Capulin UT DSP.out"				/* this is the output file */
-m "Capulin UT DSP.map"				/* map output file */

/* NOTE NOTE NOTE */
/* The reference manual "TMS320C54x Assembly Language Tools" 1997 has the   */
/* following errors:                                                        */
/*                                                                          */
/* for the line: 	vectors:	load = 0ff80h							    */
/*                                                                          */
/*  the book shows a period before "vectors" - do not use a period in front */
/*   of a named section, such as when using .sect							*/
/*  the book omits the leading zero of 0ff80h - this causes the linker to   */
/*   use ff80h as a named memory page instead of an address                 */

MEMORY
{

	/* Each DSP core in the TMS320VC5441 has multiple pages of program  */
	/* and data memory.  The program is loaded into page MPAB0 of the   */
	/* shared memory space for cores A & B and page MPCD0 of the shared */
	/* memory space for cores C & D.  The HPI bus accesses MPAB0 by via */
	/* page 0 of program memory on core A and MPCD0 via page 0 of       */
	/* program memory on core B.  Thus writing to core A also installs  */
	/* the code for core B and writing to core C also installs code for */
	/* core D.                                                          */
	/* For simplicity, only page 0 of the data memory and page 0 of the */
	/* program memory are defined here.  These are easily accessible    */
	/* for installing code and data via the HPI bus.  The code can make */
	/* use of the other pages dynamically if needed.					*/
	/* Note that only the upper half of each program memory page is     */
	/* actual RAM (8000h - 0ffffh) - the lower half simply mirrors data */
	/* memory.  Here we define addresses in the page from 8000h - 0ffffh*/
	/* to limit assembly the valid areas.								*/

	PAGE 0:		SharedP0 	: origin = 8000h, length = 8000h

	PAGE 1:		DataP0		: origin = 80h, length = 0ff00h

	PAGE 2:		Registers	: origin = 00h, length = 60h

	

}/* end of MEMORY */

SECTIONS
{

	.data:		load = SharedP0
	.text:		load = SharedP0
	vectors:	load = 0ff80h
	.bss:		load = DataP0

}/* end of SECTIONS */

