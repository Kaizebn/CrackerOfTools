@echo off
REM ============================================================
REM  Lanceur de JARVIS pour Windows.
REM  Double-clique sur ce fichier pour demarrer l'agent.
REM  La fenetre RESTE ouverte (grace a "pause" a la fin).
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo    JARVIS - demarrage...
echo ============================================
echo.

REM Verifie que Python est installe.
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Python n'est pas installe ou introuvable.
    echo Installe-le puis relance ce fichier :
    echo    winget install -e --id Python.Python.3.12
    echo.
    pause
    exit /b
)

REM Installe la dependance (Pillow) si besoin - silencieux.
python -m pip install -r requirements.txt >nul 2>&1

REM Lance l'agent.
python main.py

echo.
echo ============================================
echo    JARVIS s'est arrete. Appuie sur une touche pour fermer.
echo ============================================
pause >nul
