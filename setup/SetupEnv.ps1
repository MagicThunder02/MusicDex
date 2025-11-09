<#
.SYNOPSIS
    Automated Development Environment Setup for MusicDex on Windows 11.
.DESCRIPTION
    This script installs all necessary tools for MusicDex development
    (Flutter, Python, PostgreSQL, Build Tools) using Chocolatey.
    It checks if tools are already installed.
    
    It MUST be run from an ELEVATED (Administrator) PowerShell terminal.
.NOTES
    - Author: Gemini
    - Date: 2025-11-09
    - This script will install a lot of software and may take a long time.
    - You MUST set a password for PostgreSQL. This script attempts to set
      a default 'mysecretpassword'. CHANGE THIS in a production setting.
#>

# Function to check if a command exists
function Test-Command {
    param($command)
    return (Get-Command $command -ErrorAction SilentlyContinue)
}

# 1. Check for Administrator Privileges
Write-Host "Checking for Administrator privileges..."
if (-Not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as Administrator."
    Write-Warning "Please re-open PowerShell as an Administrator and run this script again."
    Start-Sleep -Seconds 10
    Exit 1
}
Write-Host "Administrator check passed." -ForegroundColor Green

# 2. Check for and Install Chocolatey
Write-Host "Checking for Chocolatey package manager..."
if (-Not (Test-Command choco)) {
    Write-Host "Chocolatey not found. Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    try {
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Host "Chocolatey installed successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to install Chocolatey. Please install it manually and re-run this script."
        Exit 1
    }
} else {
    Write-Host "Chocolatey is already installed." -ForegroundColor Green
}

# 3. Install Core Tools
Write-Host "Installing Core Tools (Git, Python, PostgreSQL)..."

# Git
if (Test-Command git) {
    Write-Host "Git is already installed. Skipping." -ForegroundColor Green
} else {
    Write-Host "Installing Git..."
    choco install git -y
}

# Python 3.11 (with version check)
Write-Host "Checking Python installation..."
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    try {
        $ver = (python --version) 2>&1
        Write-Host "Found existing Python: $ver"
        if ($ver -match "Python (\d+)\.(\d+)") {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 10)) {
                Write-Error "Found incompatible Python version ($ver). Please uninstall it or update your PATH. This script requires 3.10+."
                Exit 1
            }
            Write-Host "Found compatible Python. Ensuring version 3.11.5 is installed (choco will update if needed)..."
            choco install python --version=3.11.5 -y
        } else {
            Write-Warning "Could not parse python version string '$ver'. Attempting installation..."
            choco install python --version=3.11.5 -y
        }
    } catch {
        Write-Warning "Could not execute 'python --version'. Attempting installation..."
        choco install python --version=3.11.5 -y
    }
} else {
    Write-Host "Python not found. Installing Python 3.11.5..."
    choco install python --version=3.11.5 -y
}

# PostgreSQL 15
if (Test-Command psql) {
    Write-Host "psql command found. Skipping PostgreSQL installation." -ForegroundColor Green
} else {
    Write-Host "psql command not found. Installing PostgreSQL 15..."
    Write-Warning "The default postgres user password will be set to 'mysecretpassword'. Change this!"
    choco install postgresql15 --params "'/Password:mysecretpassword'" -y
}

# 4. Install Flutter & Native Dependencies
Write-Host "Installing Flutter, VS Build Tools, and CMake..."

# Flutter SDK
if (Test-Command flutter) {
    Write-Host "Flutter is already installed. Skipping." -ForegroundColor Green
} else {
    Write-Host "Installing Flutter SDK..."
    choco install flutter -y
}

# Visual Studio 2022 Build Tools (Check by package name)
Write-Host "Checking for Visual Studio Build Tools..."
choco list --local-only -r visualstudio2022-buildtools
if ($LASTEXITCODE -eq 0) {
    Write-Host "Visual Studio Build Tools are already installed. Skipping." -ForegroundColor Green
} else {
    Write-Host "Installing Visual Studio 2022 Build Tools (C++ Workload)... This will take time."
    choco install visualstudio2022-buildtools --package-parameters "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64" -y
}

# CMake
if (Test-Command cmake) {
    Write-Host "CMake is already installed. Skipping." -ForegroundColor Green
} else {
    Write-Host "Installing CMake..."
    choco install cmake -y
}

# 5. Final Instructions
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         SETUP SCRIPT COMPLETED SUCCESSFULLY" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT NEXT STEPS:"
Write-Host "1. RESTART YOUR TERMINAL (or reboot) for all PATH changes to apply."
Write-Host "2. Open a new terminal and run 'flutter doctor'."
Write-Host "3. Follow 'flutter doctor' instructions to install Android Studio ('choco install android-studio') and the Android SDK."
Write-Host "4. Manually create the PostgreSQL database and user (see setup_guide.md)."
Write-Host ""