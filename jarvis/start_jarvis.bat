@echo off
setlocal enableextensions
cd /d "%~dp0"
title JARVIS

REM ============================================================
REM  Lanceur JARVIS en un double-clic.
REM  1er lancement : installe tout (peut prendre plusieurs minutes).
REM  Ensuite      : ouvre directement l'interface (tray + HUD).
REM ============================================================

if not exist ".venv\Scripts\pythonw.exe" goto :install
goto :launch

:install
echo.
echo === Premiere installation de JARVIS ===
echo.

REM --- Trouver un Python 3.11+ ---
set "PYLAUNCH="
py -3.11 --version >nul 2>nul && set "PYLAUNCH=py -3.11"
if not defined PYLAUNCH ( py -3 --version >nul 2>nul && set "PYLAUNCH=py -3" )
if not defined PYLAUNCH ( python --version >nul 2>nul && set "PYLAUNCH=python" )
if not defined PYLAUNCH (
  echo Python 3.11+ est introuvable.
  echo J'ouvre la page de telechargement : coche "Add python.exe to PATH" a l'installation.
  start "" "https://www.python.org/downloads/"
  pause
  exit /b 1
)

echo Creation de l'environnement...
%PYLAUNCH% -m venv .venv || (echo Echec venv & pause & exit /b 1)
call ".venv\Scripts\activate.bat"

echo Installation des dependances (cela peut prendre plusieurs minutes)...
python -m pip install --upgrade pip
pip install -r requirements.txt || (echo Echec installation des dependances & pause & exit /b 1)
pip install -e . || (echo Echec installation du paquet & pause & exit /b 1)

if not exist ".env" copy ".env.example" ".env" >nul

echo.
echo === Presque pret ! ===
echo  1) Colle ta cle ANTHROPIC_API_KEY dans le fichier .env qui va s'ouvrir.
echo  2) (Voix) depose la voix Piper dans models\piper\ (voir README).
echo  3) Double-clique a nouveau sur start_jarvis.bat pour lancer JARVIS.
echo.
notepad .env
pause
exit /b 0

:launch
call ".venv\Scripts\activate.bat"
REM pythonw = pas de fenetre noire : seuls le tray et le HUD apparaissent.
start "" ".venv\Scripts\pythonw.exe" "%~dp0run.py"
exit /b 0
