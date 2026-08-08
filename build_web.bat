@echo off
REM ============================================================
REM  build_web.bat - Re-exporte le jeu pour le Web
REM  Usage:  build_web.bat
REM  Produit: build/web/ (index.html, index.wasm, index.pck, ...)
REM  Ensuite, poussez sur GitHub pour mise à jour automatique.
REM ============================================================
setlocal

set "GODOT=C:\Users\alger\OneDrive\Desktop\GODOT 4.7.1\Godot_v4.7.1-stable_win64.exe"
set "PROJECT=C:\Users\alger\OneDrive\Documents\the-last-clan-3d"

mkdir "%PROJECT%\build\web" 2>nul
echo [1/2] Export Web (release)...
"%GODOT%" --headless --path "%PROJECT%" --export-release "Web" "%PROJECT%\build\web\index.html"
if errorlevel 1 (
  echo [ERREUR] Export echoue.
  exit /b 1
)

echo [2/2] Export termine avec succes.
echo.
echo Fichiers dans: %PROJECT%\build\web\
echo Puis: cd %PROJECT% ^&^& git add . ^&^& git commit -m "mise a jour" ^&^& git push
echo GitHub Actions deployera automatiquement sur GitHub Pages.
pause