@echo off
REM SmartSumbong -- local dev server for the admin portal, rooted at this
REM project folder (admin/includes/config.php looks for .env here).
REM
REM It talks to the same live Supabase project as the deployed portal:
REM look freely, but anything you click changes real data.
REM
REM Close any other "php -S" window for this project first, so nothing is
REM holding port 8000. Other devices on the same wifi can use this PC's
REM address instead of 127.0.0.1 (see "ipconfig").

cd /d "%~dp0"
echo.
echo Starting SmartSumbong on:
echo   Admin login:      http://127.0.0.1:8000/admin/login.php
echo   Admin dashboard:  http://127.0.0.1:8000/admin/dashboard.php
echo.
echo Press Ctrl+C here to stop the server.
echo.
php -S 0.0.0.0:8000 -t .
pause
