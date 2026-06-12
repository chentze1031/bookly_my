@echo off
cd /d "%~dp0"
echo ========================================
echo  Bookly MY - Cleanup and Push
echo ========================================
echo.

echo [1/4] Deleting unnecessary files...
if exist "Bookly"  rmdir /s /q "Bookly"
if exist ".config" rmdir /s /q ".config"
if exist ".ssh"    rmdir /s /q ".ssh"
if exist ".bashrc" del /f /q ".bashrc"
if exist "push.bat" del /f /q "push.bat"
if exist "supabase_inventory_setup.sql" del /f /q "supabase_inventory_setup.sql"
echo        Done

echo [2/4] Removing from git tracking...
git rm -r --cached Bookly .bashrc .config .ssh push.bat supabase_inventory_setup.sql >nul 2>&1
echo        Done

echo [3/4] Committing changes...
git add -A
git commit -m "chore: cleanup residue files, fix AAB GEMINI_KEY injection, add full DB setup"
echo        Done

echo [4/4] Pushing to GitHub...
git push
echo.
echo ========================================
echo  ALL DONE! Check GitHub Actions page
echo  Green check = build success
echo ========================================
pause
