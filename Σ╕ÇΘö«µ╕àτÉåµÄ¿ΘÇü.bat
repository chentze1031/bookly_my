@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ════════════════════════════════════════
echo  Bookly MY 一键清理 + 推送
echo ════════════════════════════════════════
echo.

echo [1/4] 删除不需要的文件...
if exist "Bookly"  rmdir /s /q "Bookly"
if exist ".config" rmdir /s /q ".config"
if exist ".ssh"    rmdir /s /q ".ssh"
if exist ".bashrc" del /f /q ".bashrc"
if exist "push.bat" del /f /q "push.bat"
if exist "supabase_inventory_setup.sql" del /f /q "supabase_inventory_setup.sql"
echo       完成

echo [2/4] 从 git 跟踪中移除...
git rm -r --cached Bookly .bashrc .config .ssh push.bat supabase_inventory_setup.sql >nul 2>&1
echo       完成

echo [3/4] 提交所有变更...
git add -A
git commit -m "chore: cleanup residue files, fix AAB GEMINI_KEY injection, add full DB setup"
echo       完成

echo [4/4] 推送到 GitHub...
git push
echo.
echo ════════════════════════════════════════
echo  全部完成！请打开 GitHub 的 Actions 页面
echo  查看构建是否成功（绿色勾 = 成功）
echo ════════════════════════════════════════
pause
