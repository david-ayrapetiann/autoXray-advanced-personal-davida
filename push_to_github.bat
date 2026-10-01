@echo off
chcp 65001 >nul
echo ========================================================
echo   Загрузка VPN Cluster в ваш репозиторий GitHub
echo ========================================================
echo.
set /p REPO_URL="Введите URL вашего GitHub репозитория (например, https://github.com/username/vpn-cluster.git): "

if "%REPO_URL%"=="" (
    echo [ОШИБКА] URL не может быть пустым.
    pause
    exit /b 1
)

echo.
echo [1/3] Проверка remote origin...
git remote remove origin 2>nul
git remote add origin %REPO_URL%

echo [2/3] Проверка ветки main...
git branch -M main

echo [3/3] Отправка на GitHub (откроется окно авторизации если нужно)...
git push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo  [УСПЕХ] Проект успешно опубликован на вашем GitHub!
    echo ========================================================
) else (
    echo.
    echo [ОШИБКА] Не удалось отправить. Проверьте права доступа и URL.
)

pause
