@echo off
setlocal enabledelayedexpansion

:: 獲取當前版本
set /p CURRENT_VERSION=<VERSION
echo 當前版本: !CURRENT_VERSION!

:: 解析版本號
for /f "tokens=1-3 delims=." %%a in ("!CURRENT_VERSION!") do (
    set MAJOR=%%a
    set MINOR=%%b
    set PATCH=%%c
)

:: 檢查參數
if "%~1"=="major" (
    set /a NEW_MAJOR=!MAJOR! + 1
    set "NEW_VERSION=!NEW_MAJOR!.0.0"
) else if "%~1"=="minor" (
    set /a NEW_MINOR=!MINOR! + 1
    set "NEW_VERSION=!MAJOR!.!NEW_MINOR!.0"
) else (
    set /a NEW_PATCH=!PATCH! + 1
    set "NEW_VERSION=!MAJOR!.!MINOR!.!NEW_PATCH!"
)

:: 更新版本文件
echo 新版本: !NEW_VERSION!
echo !NEW_VERSION! > VERSION

:: 更新 Dockerfile 中的 LABEL version
for /r %%f in (Dockerfile) do (
    if exist "%%f" (
        powershell -Command "(Get-Content '%%f') -replace 'LABEL version=.*', 'LABEL version=!NEW_VERSION!' | Set-Content '%%f'"
    )
)

echo 版本已更新為 !NEW_VERSION!
echo 請手動執行以下命令：
echo git add VERSION
for /r /d %%d in (*) do (
    if exist "%%d\Dockerfile" (
        echo git add "%%d\Dockerfile"
    )
)
echo git commit -m "Bump version to !NEW_VERSION!"
echo git tag -a "v!NEW_VERSION!" -m "Version !NEW_VERSION!"
echo git push origin main --tags

endlocal
