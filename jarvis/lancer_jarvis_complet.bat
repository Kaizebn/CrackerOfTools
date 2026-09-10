@echo off
REM ============================================================
REM  JARVIS COMPLET : HUD plein ecran + voix + IA + controle PC.
REM  Double-clique. Dis "Jarvis, ..." pour parler.
REM  Quitter : croix en haut a droite (ou Alt+F4).
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo    J.A.R.V.I.S - version complete
echo ============================================
echo.

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Python n'est pas installe.
    echo    winget install -e --id Python.Python.3.12
    echo.
    pause
    exit /b
)

echo Preparation (1er lancement : installation + modele vocal ~40 Mo)...
echo Sois patient quelques minutes la premiere fois.
python -m pip install -r requirements.txt >nul 2>&1

REM Info : l'IA (Ollama) est optionnelle. Sans elle, JARVIS marche en mode simple.
where ollama >nul 2>&1
if errorlevel 1 (
    echo.
    echo [INFO] Ollama n'est pas installe : JARVIS fonctionnera en "mode simple".
    echo Pour l'IA Llama :  winget install -e --id Ollama.Ollama
    echo puis, dans un AUTRE terminal :  ollama pull llama3.2:3b
    echo.
)

echo Lancement de JARVIS...
python jarvis.py

echo.
echo JARVIS s'est arrete. Appuie sur une touche pour fermer.
pause >nul
