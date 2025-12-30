@echo off
setlocal enabledelayedexpansion

:: This script reads secrets from a .dev.vars file and intelligently uploads them
:: to two separate Cloudflare accounts using cfman. It checks a hash of the secret
:: in KV storage to avoid unnecessary 'put' operations.
:: It exits immediately if any command fails.

:: --- Pre-flight Checks ---

:: 1. Check for cfman
where cfman >nul 2>nul
if %errorlevel% neq 0 (
    echo ❌ Error: cfman is not installed or not in your PATH.
    echo Please install it globally with: npm install -g cfman
    echo Then, configure your accounts using: cfman setup
    exit /b 1
)

:: 2. Load environment variables from .env file in the project root
set "ENV_FILE=..\.env"
if exist "%ENV_FILE%" (
    :: Load variables, ignoring comments and empty lines
    for /f "usebackq tokens=1,* delims==" %%a in ("%ENV_FILE%") do (
        set "%%a=%%b"
    )
) else (
    echo ❌ Error: %ENV_FILE% file not found in the parent directory.
    exit /b 1
)

:: 3. Check for required account aliases
if not defined CF_ACCOUNT_ONE_ALIAS (
    echo ❌ Error: CF_ACCOUNT_ONE_ALIAS not set in %ENV_FILE%
    exit /b 1
)
if not defined CF_ACCOUNT_TWO_ALIAS (
    echo ❌ Error: CF_ACCOUNT_TWO_ALIAS not set in %ENV_FILE%
    exit /b 1
)

:: 4. Check for .dev.vars file in the parent directory
set "DEV_VARS_FILE=..\.dev.vars"
if not exist "%DEV_VARS_FILE%" (
    echo ❌ Error: %DEV_VARS_FILE% file not found in the parent directory.
    exit /b 1
)

:: --- Main Logic ---

:: List of account aliases to upload secrets to
set "ACCOUNTS=%CF_ACCOUNT_ONE_ALIAS% %CF_ACCOUNT_TWO_ALIAS%"

:: Loop through each account
for %%a in (%ACCOUNTS%) do (
    echo 🚀 Syncing secrets for Account: %%a...

    :: Read .dev.vars, filter out comments and empty lines, and process each secret
    for /f "usebackq tokens=1,* delims==" %%k in ('findstr /v /r /c:"^[[:space:]]*#" /c:"^[[:space:]]*$" "%DEV_VARS_FILE%"') do (
        set "key=%%k"
        set "value=%%l"

        :: Log which key is being processed
        echo   - Processing secret for key: '!key!'...

        if defined key (
            :: Calculate the hash of the new value
            :: We need a temp file because certutil works on files
            set "TEMP_SECRET_FILE=%TEMP%\secret.tmp"
            (echo|set /p="!value!") > "!TEMP_SECRET_FILE!"
            
            set "new_hash="
            for /f "delims=" %%h in ('certutil -hashfile "!TEMP_SECRET_FILE!" SHA256 ^| findstr /v /i "sha256"') do (
                set "new_hash=%%h"
            )
            del "!TEMP_SECRET_FILE!" >nul 2>nul

            set "kv_key=secret_hash_!key!"

            :: Get the old hash from KV storage, suppressing "key not found" errors
            set "old_hash="
            for /f "delims=" %%h in ('cfman wrangler --account %%a kv:key get "!kv_key!" 2^>nul') do (
                set "old_hash=%%h"
            )

            :: Compare hashes
            if "!new_hash!" == "!old_hash!" (
                echo     - ✅ Hash matches. Secret '!key!' is up-to-date.
            ) else (
                echo     - 🔄 Hash differs. Uploading new secret for '!key!'...
                :: Use wrangler secret put, passing the value via stdin for safety
                (echo !value!) | cfman wrangler --account %%a secret put "!key!"
                if !errorlevel! neq 0 (
                    echo ❌ Failed to upload secret for key '!key!'.
                    exit /b 1
                )

                :: Update the hash in KV storage for the new value
                echo     - 💾 Updating hash for '!key!' in KV storage.
                cfman wrangler --account %%a kv:key put "!kv_key!" "!new_hash!"
                if !errorlevel! neq 0 (
                    echo ❌ Failed to update hash for key '!key!'.
                    exit /b 1
                )
            )
        )
    )

    echo ✅ Secret sync completed for Account: %%a.
    echo ----------------------------------------
)

echo 🎉 All secrets synced successfully!
endlocal
