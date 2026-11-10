@echo off
rem Builds the eight test programs of tests\asm into tests\build, each linked with
rem tests\start.S and tests\link.ld. Run it from anywhere:
rem
rem     tools\build_tests.bat
rem
rem tests\build is generated output and is not committed.

setlocal

set "ROOT=%~dp0.."
set "GCC=riscv64-unknown-elf-gcc"

rem The compiler comes from MSYS2. Use that folder when it is not on the PATH already.
where %GCC% >nul 2>nul
if errorlevel 1 set "PATH=C:\msys64\ucrt64\bin;%PATH%"
where %GCC% >nul 2>nul
if errorlevel 1 (
    echo build_tests: %GCC% not found. Install it in MSYS2 or add it to the PATH.
    exit /b 1
)

if not exist "%ROOT%\tests\build" mkdir "%ROOT%\tests\build"

rem --no-warn-rwx-segments: code and data share one RAM region on purpose.
set FLAGS=-march=rv32i -mabi=ilp32 -nostdlib -Wl,--no-warn-rwx-segments

for %%N in (alu_basic shifts compare_signed_unsigned branches_all jal_jalr loads_stores_widths lui_auipc fib_loop) do (
    echo building %%N
    %GCC% %FLAGS% -T "%ROOT%\tests\link.ld" "%ROOT%\tests\start.S" "%ROOT%\tests\asm\%%N.S" -o "%ROOT%\tests\build\%%N.elf"
    if errorlevel 1 (
        echo build_tests: FAILED on %%N
        exit /b 1
    )
)

echo build_tests: 8 programs built in tests\build
exit /b 0
