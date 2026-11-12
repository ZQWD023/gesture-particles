@echo off
title Camera Reset (Admin)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0重置摄像头_管理员.ps1' -Verb RunAs"
