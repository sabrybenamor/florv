@echo off
rem Compiles the VHDL and runs one testbench in Vivado's simulator (xsim), without
rem the Vivado GUI. Run it from anywhere:
rem
rem     tools\sim.bat tb_alu
rem
rem The argument is the testbench entity. A testbench must print PASS when every
rem check passed, and stop with "assert ... severity failure" when one did not.
rem
rem Exit codes: 0 the testbench printed PASS, 1 it failed or did not compile,
rem             2 wrong usage or Vivado not found.
rem
rem All simulator output goes to sim_out\ at the repo root, which git ignores.
rem The log of a run is sim_out\NAME.log.

setlocal

if "%~1"=="" (
    echo usage: tools\sim.bat TESTBENCH        for example: tools\sim.bat tb_alu
    exit /b 2
)
set "NAME=%~1"
for %%I in ("%~dp0..") do set "ROOT=%%~fI"

rem xvhdl, xelab and xsim are not on the PATH; this Vivado script adds them.
rem Set VIVADO_SETTINGS before calling to use another installation.
if not defined VIVADO_SETTINGS set "VIVADO_SETTINGS=C:\AMDDesignTools\2025.2\Vivado\settings64.bat"
if not exist "%VIVADO_SETTINGS%" (
    echo sim: %VIVADO_SETTINGS% not found. Set VIVADO_SETTINGS to your settings64.bat.
    exit /b 2
)
call "%VIVADO_SETTINGS%"

rem ---------------------------------------------------------------------------
rem The files, in compile order: a file comes after everything it uses, so the
rem package is first, then rtl\, then the testbenches. Add one line per new file.
rem ---------------------------------------------------------------------------
set FILES=
set FILES=%FILES% "%ROOT%\rtl\rv32i_pkg.vhd"
set FILES=%FILES% "%ROOT%\rtl\decode_pkg.vhd"
set FILES=%FILES% "%ROOT%\rtl\regfile.vhd"
set FILES=%FILES% "%ROOT%\rtl\alu.vhd"
set FILES=%FILES% "%ROOT%\rtl\imm_gen.vhd"
set FILES=%FILES% "%ROOT%\rtl\decode.vhd"
set FILES=%FILES% "%ROOT%\rtl\rv_core.vhd"
set FILES=%FILES% "%ROOT%\tb\tb_regfile.vhd"
set FILES=%FILES% "%ROOT%\tb\tb_alu.vhd"
set FILES=%FILES% "%ROOT%\tb\tb_imm_gen.vhd"
set FILES=%FILES% "%ROOT%\tb\tb_decode.vhd"
set FILES=%FILES% "%ROOT%\tb\tb_rv_core.vhd"
set FILES=%FILES% "%ROOT%\tb\tb_rv_core_insns.vhd"

set "OUT=%ROOT%\sim_out"
if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"

rem Start from nothing, so a deleted or renamed entity cannot linger from an old run.
if exist xsim.dir rmdir /s /q xsim.dir
if exist "%NAME%.log" del "%NAME%.log"

rem Every Vivado tool below is itself a batch file. Without "call", this script
rem would end as soon as the first one finished.

echo sim: compiling
call xvhdl -2008 -nolog %FILES%
if errorlevel 1 goto failed_compile

echo sim: elaborating %NAME%
call xelab -debug typical -nolog %NAME% -s %NAME%_sim
if errorlevel 1 goto failed_elaborate

echo sim: running %NAME%
call xsim %NAME%_sim -runall -log "%NAME%.log"
if errorlevel 1 goto failed_run

rem xsim exits with 0 even when an assertion stopped the run, so the result is read
rem from the log: no failure or error line, and the word PASS.
findstr /B /C:"Failure:" /C:"Error:" /C:"ERROR:" "%NAME%.log" >nul
if not errorlevel 1 goto failed_test
findstr /C:"PASS" "%NAME%.log" >nul
if errorlevel 1 goto no_pass

popd
echo sim: %NAME% passed
exit /b 0

:failed_compile
popd
echo sim: FAILED, xvhdl reported an error
exit /b 1

:failed_elaborate
popd
echo sim: FAILED, xelab could not build %NAME%. Is the file in the list in tools\sim.bat?
exit /b 1

:failed_run
popd
echo sim: FAILED, xsim reported an error
exit /b 1

:failed_test
popd
echo sim: %NAME% FAILED, see the Failure or Error line above
exit /b 1

:no_pass
popd
echo sim: %NAME% FAILED, it ended without printing PASS
exit /b 1
