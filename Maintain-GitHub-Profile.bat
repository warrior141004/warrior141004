@echo off
title Maintain GitHub Profile
echo Running GitHub profile maintenance...
echo.
wsl.exe bash -lc "cd /home/warrior14/warrior141004-profile-work && OPEN_PROFILE=1 ./Maintain-GitHub-Profile.sh"
echo.
pause
