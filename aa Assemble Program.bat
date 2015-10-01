"..\..\..\TMS320C54x Tools\asm500.exe" "%~1.asm" -l 1>>results.txt 2>&1

"..\..\..\TMS320C54x Tools\asm500.exe" "%~1 Debug.asm" -l 1>>results.txt 2>&1

"..\..\..\TMS320C54x Tools\lnk500.exe" "%~1.cmd" 1>>results.txt 2>&1


@REM note that hex500 cannot output to a filename with spaces, so %2 is used to provide a usable name

"..\..\..\TMS320C54x Tools\hex500.exe" -a "%~1.out" -o "%~2.hex" -romwidth 16  1>>results.txt 2>&1


@REM Run the absolute address generator on the file to produce a listing with absolute addresses

"..\..\..\TMS320C54x Tools\abs500.exe" "%~1.out" 1>>results.txt 2>&1

"..\..\..\TMS320C54x Tools\asm500.exe" -a "%~1.abs" 1>>results.txt 2>&1

copy "CapulinUTDSP.hex" "c:\Users\Mike\Documents\7 - Java Projects\Chart\DSP\"
