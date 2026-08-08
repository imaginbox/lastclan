@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
REM ============================================================
REM  mise_a_jour.bat - Mise à jour automatique du jeu en ligne
REM  ----------------------------------------------------------
REM  PREMIÈRE UTILISATION :
REM    1. Créez un dépôt vide sur github.com (New repository),
REM       SANS cocher "Add a README" (important).
REM    2. Lancez ce script. Il vous demandera l'URL du dépôt
REM       (ex: https://github.com/VOTRE_NOM/le-last-clan.git).
REM    3. Le script initialise Git, exporte le jeu et pousse.
REM    4. Activez GitHub Pages dans le dépôt (voir fin du script).
REM
REM  UTILISATIONS SUIVANTES :
REM    Lancez ce script après avoir modifié le jeu.
REM    Il re-exporte et publie automatiquement.
REM ============================================================

set "GODOT=C:\Users\alger\OneDrive\Desktop\GODOT 4.7.1\Godot_v4.7.1-stable_win64.exe"
set "PROJECT=C:\Users\alger\OneDrive\Documents\the-last-clan-3d"
cd /d "%PROJECT%"

echo ============================================
echo   The Last Clan - Publication automatique
echo ============================================
echo.

REM --- 1. Vérifier / initialiser le dépôt Git ---
if not exist ".git" (
  echo [ETAPE 1] Initialisation du dépôt Git...
  call :ask "URL de votre dépôt GitHub (vide si pas encore créé) ? " REPO_URL

  if not "%REPO_URL%"=="" (
    echo   Initialisation du dépôt local...
    git init >nul 2>&1
  ) else (
    echo   [!] Vous devez d'abord creer un depot vide sur github.com
    echo       puis relancer ce script avec son URL.
    echo       Creation: github.com -^> New repository -^> mettre un nom.
    pause
    exit /b 1
  )
) else (
  echo [ETAPE 1] Depot Git deja initialise.
)

REM --- 2. Configurer Git (nom/email si absents) ---
echo [ETAPE 2] Configuration Git...
if "!git config user.name!"=="" (
  set /p "GIT_NAME=Votre nom GitHub (Username) : "
  git config user.name "!GIT_NAME!"
)
if "!git config user.email!"=="" (
  set /p "GIT_EMAIL=Votre email GitHub : "
  git config user.email "!GIT_EMAIL!"
)

REM --- 3. Ajouter la remote si absente ---
call :get_remote REMOTE
if "%REMOTE%"=="" (
  call :ask "URL du depot GitHub (ex: https://github.com/VOTRE_NOM/le-last-clan.git) ? " REMOTE
  git remote add origin "%REMOTE%"
)

REM --- 4. Exporter le jeu pour le Web ---
echo [ETAPE 3] Export Web (cela peut prendre ~1 minute)...
mkdir "build\web" 2>nul
"%GODOT%" --headless --path "%PROJECT%" --export-release "Web" "%PROJECT%\build\web\index.html"
if errorlevel 1 (
  echo [ERREUR] Export echoue. Verifiez Godot / export_presets.cfg.
  pause
  exit /b 1
)
echo   Export OK.

REM --- 5. Commit + push ---
echo [ETAPE 4] Commit et push sur GitHub...
git add -A
git commit -m "Mise a jour du jeu" >nul 2>&1
git branch -M main
git push -u origin main
if errorlevel 1 (
  echo [ERREUR] Push echoue. 
  echo   - Verifiez que le depot existe et que vous avez les droits.
  echo   - Verifiez votre configuration GitHub (auth).
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   ✔ PUBLICATION TERMINEE !
echo ============================================================
echo   GitHub Actions deploye automatiquement sur GitHub Pages.
echo   Votre jeu sera en ligne dans ~1-2 minutes.
echo.
echo   Lien du jeu :  https://!GIT_NAME!.github.io/le-last-clan/
echo   Rejoindre une partie : https://!GIT_NAME!.github.io/le-last-clan/?room=ABCD
echo.
echo   IMPORTANT (une seule fois) : dans GitHub, allez dans
echo   Settings -^> Pages -^> Source: "GitHub Actions" -^> Save.
echo   (Le nom du depot doit etre "le-last-clan" pour ce lien.)
echo ============================================================
pause

exit /b

REM --- Sous-routines ---
:ask
set "%~2="
set /p "%~2=%~1"
exit /b

:get_remote
set "%~1="
for /f "tokens=2" %%r in ('git remote get-url origin 2^>nul') do set "%~1=%%r"
exit /b