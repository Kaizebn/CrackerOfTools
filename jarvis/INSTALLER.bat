@echo off
REM ============================================================
REM  INSTALLATION COMPLETE DE JARVIS - a faire UNE SEULE FOIS.
REM  Double-clique. Ca installe tout : composants, IA, modeles.
REM  Ensuite, tu lanceras "lancer_jarvis_complet".
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo    INSTALLATION COMPLETE DE JARVIS  (une seule fois)
echo ============================================================
echo.

echo [1/5] Verification de Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo    Installation de Python...
    winget install -e --id Python.Python.3.12
    echo.
    echo    ^>^>^> Python vient d'etre installe.
    echo    ^>^>^> FERME cette fenetre et relance INSTALLER une 2e fois.
    echo.
    pause
    exit /b
)
echo    Python OK.
echo.

echo [2/5] Installation des composants (voix, HUD, reseau)...
python -m pip install -r requirements.txt
echo.

echo [3/5] Installation de l'IA Ollama...
where ollama >nul 2>&1
if errorlevel 1 (
    winget install -e --id Ollama.Ollama
    echo    ^>^>^> Ollama installe. Si l'etape 4 echoue avec "ollama introuvable",
    echo    ^>^>^> ferme et relance INSTALLER une 2e fois.
)
echo.

echo [4/5] Telechargement du cerveau (modele Llama ~2 Go)... patiente.
ollama pull llama3.2:3b
echo.

echo [5/5] Telechargement de l'oreille (modele vocal francais ~40 Mo)...
python -c "import os,voix; print('deja present') if os.path.isdir(voix.CHEMIN_MODELE) else voix._telecharger_modele()"
echo.

echo ============================================================
echo    TERMINE ! Lance maintenant : lancer_jarvis_complet
echo ============================================================
pause
