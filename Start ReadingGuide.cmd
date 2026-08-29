@echo off
rem Launches ReadingGuide without leaving a console window open.
rem This file does exactly one thing: run ReadingGuide.ps1 from this folder.
start "" /min powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ReadingGuide.ps1"
