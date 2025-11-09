#!/bin/bash
#
# Automated Development Environment Setup for MusicDex on Manjaro Linux.
#
# This script installs all necessary tools for MusicDex development
# (Flutter, Python, PostgreSQL, Build Tools) using pamac.
# It checks if tools are already installed.
#
# It MUST be run with sudo privileges.

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

echo "Starting MusicDex development environment setup..."
echo "This script will use 'pamac' to install packages from official repositories and the AUR."

# Helper function to check for command and install package if missing
check_and_install() {
  local package=$1
  local command_to_check=$2
  
  if command -v $command_to_check &> /dev/null; then
    echo "$package ($command_to_check) is already installed. Skipping."
  else
    echo "Installing $package..."
    pamac install $package --no-confirm
  fi
}

# 2. Update package lists
echo "Updating package databases..."
pamac checkupdates -a

# 3. Install base-devel (essential for building packages/libs)
echo "Ensuring 'base-devel' build tools are installed (pamac will skip if present)..."
pamac install base-devel --no-confirm

# 4. Install Core Dependencies
echo "Checking Core Dependencies..."

# Git
check_and_install "git" "git"
# PostgreSQL
check_and_install "postgresql" "psql"
# CMake
check_and_install "cmake" "cmake"
# Chromaprint (command is fpcalc)
check_and_install "chromaprint" "fpcalc"

# Special check for Python
echo "Checking Python installation..."
if command -v python &> /dev/null; then
  ver=$(python --version 2>&1)
  echo "Found existing Python: $ver"
  if [[ $ver =~ Python[[:space:]]([0-9]+)\.([0-9]+) ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    if [ $major -lt 3 ] || { [ $major -eq 3 ] && [ $minor -lt 10 ]; }; then
      echo "Error: Found incompatible Python version ($ver)." >&2
      echo "Please uninstall it or fix your PATH. This script requires 3.10+." >&2
      exit 1
    fi
    echo "Found compatible Python. Skipping Python installation."
  else
    echo "Could not parse python version string '$ver'. Assuming compatible."
  fi
else
  echo "Python not found. Installing..."
  pamac install python python-pip python-virtualenv --no-confirm
fi

# 5. Install Flutter (from AUR)
check_and_install "flutter" "flutter"

# 6. Initialize and Configure PostgreSQL
echo "Configuring PostgreSQL..."

if [ -d /var/lib/postgres/data/base ]; then
  echo "PostgreSQL cluster already initialized. Skipping initdb."
else
  echo "Initializing PostgreSQL database cluster..."
  sudo -u postgres initdb -D /var/lib/postgres/data
fi

echo "Enabling and starting PostgreSQL service..."
systemctl enable --now postgresql.service

# Give Postgres a moment to start
sleep 2

# 7. Create Database and User (Idempotent checks)
DB_NAME="musicdex_db"
DB_USER="musicdex_user"
DB_PASS="apassword" # CHANGE THIS in production

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
  echo "Database '$DB_NAME' already exists. Skipping creation."
else
  echo "Creating PostgreSQL database '$DB_NAME'..."
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
fi

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
  echo "User '$DB_USER' already exists. Skipping creation."
else
  echo "Creating PostgreSQL user '$DB_USER'..."
  sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
fi

echo "Granting privileges..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"

echo "PostgreSQL setup complete."

# 8. Add current user to flutter group
SUDO_USER=${SUDO_USER:-$(whoami)}
if [ "$SUDO_USER" != "root" ]; then
  if getent group flutter | grep -q "\b${SUDO_USER}\b"; then
    echo "User '$SUDO_USER' is already in 'flutter' group. Skipping."
  else
    echo "Adding user '$SUDO_USER' to the 'flutter' group..."
    usermod -aG flutter $SUDO_USER
    echo "NOTE: $SUDO_USER must log out and log back in for group changes to apply."
  fi
else
  echo "Script run as root. Skipping user group addition. Please add your dev user to the 'flutter' group manually."
fi


# 9. Final Instructions
echo ""
echo "=========================================================="
echo "         SETUP SCRIPT COMPLETED SUCCESSFULLY"
echo "================================S=========================="
echo ""
echo "IMPORTANT NEXT STEPS:"
echo "1. LOG OUT and LOG BACK IN if you were added to the 'flutter' group."
echo "2. Open a new terminal and run 'flutter doctor'."
echo "3. Follow 'flutter doctor' instructions to install the Android SDK."
echo "   (You can install Android Studio via 'pamac install android-studio')."
echo ""