@echo off
rem Install the M9 kernel for Jupyter on Windows: install.py does the
rem work, the same as on Linux and macOS.
rem
rem   install.cmd              say what it found, ask, install
rem   install.cmd -y --check   install without asking, run one cell
rem   install.cmd --help       every option
rem
rem It needs Python (python.org's, with the py launcher, or any other
rem on PATH) -- Jupyter itself is Python, so a Jupyter user has one.
where py >nul 2>nul
if %ERRORLEVEL%==0 (
  py -3 "%~dp0install.py" %*
) else (
  python "%~dp0install.py" %*
)
exit /b %ERRORLEVEL%
