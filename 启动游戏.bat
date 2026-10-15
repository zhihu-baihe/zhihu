@echo off
setlocal

rem ============================================================
rem  《云阙行：九灯照夜》 一键启动（玩游戏）
rem
rem  用法：
rem    双击本文件          —— 直接开玩（无控制台窗口）
rem    启动游戏.bat debug  —— 保留日志窗口，排查问题时用
rem
rem  额外参数：设环境变量 YQ_EXTRA 可透传给引擎，例如
rem    set YQ_EXTRA=--fullscreen
rem    set YQ_EXTRA=--resolution 1280x720
rem ============================================================

set "ROOT=%~dp0"
set "PROJ=%ROOT%yunque"
set "GODOT=%ROOT%tools\Godot\Godot_v4.7.2-stable_win64.exe"
set "GODOT_CONSOLE=%ROOT%tools\Godot\Godot_v4.7.2-stable_win64_console.exe"

if not exist "%GODOT%" goto no_engine
if not exist "%PROJ%\project.godot" goto no_project

rem 首次运行没有 .godot 缓存：先做一次资源导入，否则可能黑屏或丢材质
if not exist "%PROJ%\.godot" (
    echo.
    echo [首次运行] 正在导入资源，大约需要 30 秒，请稍候...
    echo.
    "%GODOT_CONSOLE%" --headless --path "%PROJ%" --import
    echo.
)

if /i "%~1"=="debug" (
    echo ==========================================================
    echo  调试模式：日志会打印在本窗口
    echo ==========================================================
    echo.
    "%GODOT_CONSOLE%" --path "%PROJ%" %YQ_EXTRA%
    echo.
    echo 游戏已退出（退出码 %ERRORLEVEL%）
    pause
    exit /b 0
)

rem 正常模式：异步启动后立刻收掉黑窗
start "" "%GODOT%" --path "%PROJ%" %YQ_EXTRA%
exit /b 0

:no_engine
echo.
echo [错误] 找不到 Godot 引擎。
echo.
echo   期望路径：%GODOT%
echo.
echo   tools\Godot\ 不入 git 仓库，需要手动放好：
echo     1. 下载 godotengine/godot 的 Godot_v4.7.2-stable_win64.exe.zip
echo     2. 解压出 Godot_v4.7.2-stable_win64.exe 和
echo        Godot_v4.7.2-stable_win64_console.exe
echo     3. 两个文件都放到 %ROOT%tools\Godot\ 下
echo.
pause
exit /b 1

:no_project
echo.
echo [错误] 找不到游戏工程。
echo.
echo   期望路径：%PROJ%\project.godot
echo.
echo   本脚本必须放在仓库根目录（和 yunque 文件夹同级）。
echo.
pause
exit /b 1
