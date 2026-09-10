@echo off
REM ============================================================
REM  Test de la VOIX de JARVIS (Etape 4).
REM  Double-clique : JARVIS t'ecoute et te repond a voix haute.
REM  Dis "au revoir" pour arreter.
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo    JARVIS - test de la voix
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

echo Preparation (1er lancement : installation + telechargement du modele vocal)...
echo Sois patient, ca peut prendre quelques minutes la premiere fois.
python -m pip install -r requirements.txt >nul 2>&1

echo.
echo Lancement de l'ecoute... parle en francais !
python voix.py

echo.
echo Ecoute arretee. Appuie sur une touche pour fermer.
pause >nul
