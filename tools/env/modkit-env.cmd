@echo off
rem Sets MODKIT_ROOT to the project root (two levels above this file) unless it is already set.
if not defined MODKIT_ROOT for %%I in ("%~dp0..\..") do set "MODKIT_ROOT=%%~fI"
