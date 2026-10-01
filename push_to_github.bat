@echo off
chcp 65001 >nul
echo ========================================================
echo   Загрузка VPN Cluster в ваш репозиторий GitHub
echo ========================================================
echo.
echo Репозиторий: https://github.com/your-username/autoXray-advanced-personal-davida.git
echo Ветка: main
echo.
echo Отправка файлов...
git push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo  [УСПЕХ] Проект успешно опубликован на вашем GitHub!
    echo ========================================================
) else (
    echo.
    echo [ОШИБКА] Не удалось отправить. Проверьте подключение или права.
)

echo.
pause
