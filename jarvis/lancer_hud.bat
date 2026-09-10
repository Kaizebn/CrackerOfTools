@echo off
REM ============================================================
REM  Lanceur du HUD JARVIS (la fenetre transparente).
REM  Double-clique sur ce fichier pour afficher le HUD.
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo    JARVIS - HUD (fenetre transparente)
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

echo Ouverture du HUD... (glisse-le pour le deplacer, clique la croix pour fermer)
python hud.py

echo.
echo Le HUD s'est ferme. Appuie sur une touche pour fermer cette fenetre.
pause >nul
