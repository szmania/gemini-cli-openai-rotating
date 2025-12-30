@echo off
setlocal

:: --- Pre-flight Check ---
:: Ensure cfman is installed and available in the system's PATH.
where cfman >nul 2>nul
if %errorlevel% neq 0 (
    echo ❌ Error: cfman is not installed or not in your PATH.
    echo Please install it globally with: npm install -g cfman
    echo Then, configure your accounts using: cfman setup
    exit /b 1
)

:: Load environment variables from .env file in the project root
set "ENV_FILE=..\.env"
if not exist "%ENV_FILE%" (
    echo Error: %ENV_FILE% file not found.
    exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%a in ("%ENV_FILE%") do (
    set "%%a=%%b"
)

:: Check for required environment variables
if not defined CF_ACCOUNT_ONE_ALIAS (
    echo Error: CF_ACCOUNT_ONE_ALIAS not set in %ENV_FILE%
    exit /b 1
)
if not defined CF_ACCOUNT_TWO_ALIAS (
    echo Error: CF_ACCOUNT_TWO_ALIAS not set in %ENV_FILE%
    exit /b 1
)

:: --- Deployment to Account One ---
echo 🚀 Deploying to Account One (%CF_ACCOUNT_ONE_ALIAS%)...

:: Direct cfman deployment using environment variable
cfman wrangler --account "%CF_ACCOUNT_ONE_ALIAS%" deploy
if %errorlevel% neq 0 (
    echo ❌ Deployment to Account One failed.
    exit /b 1
)

echo ✅ Successfully deployed to Account One.
echo ----------------------------------------


:: --- Deployment to Account Two ---
echo 🚀 Deploying to Account Two (%CF_ACCOUNT_TWO_ALIAS%)...

:: Direct cfman deployment using environment variable
cfman wrangler --account "%CF_ACCOUNT_TWO_ALIAS%" deploy
if %errorlevel% neq 0 (
    echo ❌ Deployment to Account Two failed.
    exit /b 1
)

echo ✅ Successfully deployed to Account Two.
echo ----------------------------------------

echo 🎉 All deployments completed successfully!
endlocal
