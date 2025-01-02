#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Define the branch name and kernel package name as variables
BRANCH_NAME="bookworm-6.8"
KERNEL_PACKAGE_NAME="proxmox-kernel-6.8"
REPO_NAME="pve-kernel-rdtsc"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "[INSTALL_ERROR] Please run as root"
    exit 1
fi

echo "[INSTALL_INFO] Updating package lists..."
apt update -y

echo "[INSTALL_INFO] Installing necessary packages..."
apt install -y git devscripts dh-python python3-sphinx

# Check if we are already inside the repository directory
if [ ! -d ".git" ]; then
    echo "[INSTALL_INFO] Cloning the repository..."
    if [ ! -d "$REPO_NAME" ]; then
        git clone https://github.com/behappiness/$REPO_NAME.git
    fi
    if [ -f install.sh ]; then
        rm install.sh
    fi
    cd $REPO_NAME
else
    echo "[INSTALL_INFO] Already inside the repository directory."
    git pull
fi

echo "[INSTALL_INFO] Checking out the specific branch..."
git checkout "$BRANCH_NAME"

echo "[INSTALL_INFO] Cleaning up previous builds..."
make distclean
make clean

echo "[INSTALL_INFO] Initializing and updating submodules..."
make submodule

echo "[INSTALL_INFO] Creating a fresh build directory..."
make build-dir-fresh

BUILD_DIR=$(find . -type d -name "proxmox-kernel-*" -print -quit)
if [ -z "$BUILD_DIR" ]; then
    echo "[INSTALL_ERROR] Build directory not found!"
    exit 1
fi
echo "[INSTALL_INFO] Found build directory: $BUILD_DIR"

echo "[INSTALL_INFO] Installing build dependencies..."
mk-build-deps -ir "$BUILD_DIR/debian/control"

echo "[INSTALL_INFO] Building the kernel package..."
make deb

echo "[INSTALL_INFO] Installing the built kernel packages..."
for package in *.deb; do
    if ! dpkg -i "$package"; then
        echo "[INSTALL_WARNING] Failed to install $package. Continuing with the next package."
    fi
done

echo "[INSTALL_INFO] Fixing dependencies..."
apt install -f -y

# Pin the kernel using proxmox-boot-tool
KERNEL_VERSION=$(proxmox-boot-tool kernel list | grep 'pve-rdtsc$' | head -n 1)
if [ -z "$KERNEL_VERSION" ]; then
    echo "[INSTALL_ERROR] Failed to find the kernel version to pin"
    exit 1
fi
echo "[INSTALL_INFO] Pinning the kernel version: $KERNEL_VERSION. Write y to apply ESPs config!"
proxmox-boot-tool kernel pin "$KERNEL_VERSION"
# Interactive, have to apply ESPs config

echo "[INSTALL_INFO] Freezing the kernel package to prevent updates..."
apt-mark hold "$KERNEL_PACKAGE_NAME"

echo "[INSTALL_INFO] Reboot the system for changes to take effect..."
read -p "Do you want to reboot the system now? (y/n): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    reboot
else
    echo "[INSTALL_INFO] Reboot canceled."
fi