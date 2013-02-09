"..\..\..\TMS320C54x Tools\asm500.exe" "%~1.asm" -l

"..\..\..\TMS320C54x Tools\lnk500.exe" "%~1.cmd"

@REM note that hex500 cannot output to a filename with spaces, so %2 is used to provide a usable name

"..\..\..\TMS320C54x Tools\hex500.exe" -a "%~1.out" -o "%~2.hex" -romwidth 16

"..\..\..\TMS320C54x Tools\abs500.exe" "%~1.out"

"..\..\..\TMS320C54x Tools\asm500.exe" -a "%~1.abs"

pause