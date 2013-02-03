"..\..\..\TMS320C54x Tools\asm500.exe" "%~1.asm" -l
"..\..\..\TMS320C54x Tools\lnk500.exe" "%~1.cmd"
"..\..\..\TMS320C54x Tools\hex500.exe" -a "%~1.out" -o "%~1.hex" -romwidth 16
pause