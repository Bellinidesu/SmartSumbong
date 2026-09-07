@echo off
REM SmartSumbong -- single dev server, rooted at this project folder.
REM
REM Replaces the two-server workaround (one "php -S ... -t admin", one
REM "php -S ... -t public") we were using earlier. That split broke every
REM relative link between the two folders -- the barangay seal image, the
REM fonts, and the Leaflet map library on the public transparency page all
REM 404'd, because that server could only ever see "public/", never the
REM sibling "admin/" its own asset paths point into.
REM
REM One server rooted at the project folder sees both "admin/" and
REM "public/" as siblings, which is what admin/includes/config.php's own
REM ".env" lookup and public/transparency.php's own "../admin/assets/..."
REM links already assumed from the start.
REM
REM Before running this: close (or Ctrl+C) any other "php -S" windows you
REM still have open for this project, so nothing is holding port 8000.

cd /d "%~dp0"
echo.
echo Starting SmartSumbong on:
echo   Admin login:        http://192.168.1.4:8000/admin/login.php
echo   Admin dashboard:    http://192.168.1.4:8000/admin/dashboard.php
echo   Public transparency page:  http://192.168.1.4:8000/public/transparency.php
echo.
echo Press Ctrl+C here to stop the server.
echo.
php -S 0.0.0.0:8000 -t .
pause
