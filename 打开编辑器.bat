@echo off
setlocal

rem ============================================================
rem  《云阙行：九灯照夜》 打开 Godot 编辑器
rem
rem  用来改场景、调材质、试参数。
rem  注意：编辑器保存 project.godot 时会重写文件头注释。
rem ============================================================

set "ROOT=%~dp0"
set "PROJ=%ROOT%yunque"
set "GODOT=%ROOT%tools\Godot\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" goto no_engine
if not exist "%PROJ%\project.godot" goto no_project

start "" "%GODOT%" -e --path "%PROJ%"
exit /b 0

:no_engine
echo.
echo [错误] 找不到 Godot 引擎：%GODOT%
echo        tools\Godot\ 不入库，需要手动放置（见 启动游戏.bat 的提示）。
echo.
pause
exit /b 1

:no_project
echo.
echo [错误] 找不到游戏工程：%PROJ%\project.godot
echo        本脚本要放在仓库根目录（和 yunque 同级）。
echo.
pause
exit /b 1
