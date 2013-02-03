"..\..\..\TMS320C54x Tools\asm500.exe" "Capulin UT DSP.asm" -l
"..\..\..\TMS320C54x Tools\asm500.exe" "Capulin UT DSP Debug.asm" -l
"..\..\..\TMS320C54x Tools\lnk500.exe" "Capulin UT DSP.cmd"
"..\..\..\TMS320C54x Tools\hex500.exe" -a "Capulin UT DSP.out" -o "CapulinUTDSP.hex" -romwidth 16
pause