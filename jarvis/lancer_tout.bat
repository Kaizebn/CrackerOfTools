@echo off
REM ============================================================
REM  Lanceur COMPLET de JARVIS (Etape 3) :
REM  le HUD + le backend relies. Tape une commande dans cette
REM  fenetre et regarde le HUD reagir.
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo    JARVIS - version reliee (HUD + backend)
echo ============================================
echo.

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Python n'est pas installe ou introuvable.
    echo    winget install -e --id Python.Python.3.12
    echo.
    pause
    exit /b
)

echo Preparation (installation des dependances au 1er lancement)...
python -m pip install -r requirements.txt >nul 2>&1

echo Ouverture de JARVIS...
python app.py

echo.
echo JARVIS s'est arrete. Appuie sur une touche pour fermer.
pause >nul
