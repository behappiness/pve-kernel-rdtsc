#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Define the branch name and kernel package name as variables
BRANCH_NAME="bookworm-6.8"
KERNEL_PACKAGE_NAME="proxmox-kernel-6.8"
REPO_NAME="pve-kernel-rdtsc"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

echo "Updating package lists..."
apt update -y

echo "Installing necessary packages..."
apt install -y git devscripts dh-python python3-sphinx

echo "Cloning or updating the kernel repository..."
if [ ! -d "$REPO_NAME" ]; then
    git clone https://github.com/behappiness/$REPO_NAME
fi
cd $REPO_NAME
git pull

echo "Checking out the specific branch..."
git checkout "$BRANCH_NAME"

echo "Initializing and updating submodules..."
git submodule update --init --recursive

echo "Creating a fresh build directory..."
make build-dir-fresh

BUILD_DIR=$(find . -type d -name "proxmox-kernel-*" -print -quit)
if [ -z "$BUILD_DIR" ]; then
    echo "Build directory not found!"
    exit 1
fi
echo "Found build directory: $BUILD_DIR"

echo "Installing build dependencies..."
mk-build-deps -ir "$BUILD_DIR/debian/control" || true

echo "Building the kernel package..."
make deb

echo "Installing the built kernel package..."
dpkg -i *.deb

echo "Fixing dependencies..."
apt install -f -y

# Pin the kernel using proxmox-boot-tool
KERNEL_VERSION=$(proxmox-boot-tool kernel list | grep 'pve-rdtsc$' | head -n 1)
if [ -z "$KERNEL_VERSION" ]; then
    echo "Failed to find the kernel version to pin"
    exit 1
fi
echo "Pinning the kernel version: $KERNEL_VERSION"
proxmox-boot-tool kernel pin "$KERNEL_VERSION"
# Interactive, have to apply ESPs config

echo "Freezing the kernel package to prevent updates..."
apt-mark hold "$KERNEL_PACKAGE_NAME"

echo "Rebooting the system..."
reboot