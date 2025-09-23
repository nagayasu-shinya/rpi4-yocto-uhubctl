# Yocto-based USB Power Control for RPi4

A Yocto-based Linux system for Raspberry Pi 4 that controls power to USB-powered devices and enables automated boot testing.

## Overview

This project provides a system to control USB port power ON/OFF on Raspberry Pi 4 for testing USB-powered devices.
It uses uhubctl for VBUS control to power cycle connected devices and supports remote control via SSH for automated testing scenarios.

## Features

- USB port power control (VBUS ON/OFF)
- SSH access with fixed IP address
- USB device boot completion detection
- Minimal embedded Linux environment
- Python 3 support for automation scripts

## Hardware Requirements

- Raspberry Pi 4B
- microSD card (8GB+)
- Ethernet connection
- USB device for power control testing

## Build Instructions

```bash
git clone https://github.com/nagayasu-shinya/rpi4-yocto-uhubctl.git
cd rpi4-yocto-uhubctl
repo init -u file://$(realpath .) -b main
repo sync
TEMPLATECONF=../meta-template/conf source poky/oe-init-build-env build
bitbake core-image-full-cmdline
```

## Write Image to SD Card

After building, write the image to an SD card using one of these methods:

### Method 1: Raspberry Pi Imager (Recommended)

The `wic.bz2` image file is typically a symbolic link.
It's recommended to copy and decompress it to your current directory before using Imager.

```bash
cp tmp/deploy/images/raspberrypi4-64/core-image-full-cmdline-raspberrypi4-64.wic.bz2 .
bunzip2 core-image-full-cmdline-raspberrypi4-64.wic.bz2
```

1. Start Raspberry Pi Imager.
2. Select Use custom.
3. Choose `core-image-full-cmdline-raspberrypi4-64.wic` (the decompressed file in your current directory)
4. Select your SD card and write.

### Method 2: bmaptool (Fast Writing)

Replace /dev/sdX with your SD card device name (e.g., /dev/sdb).

```bash
sudo bmaptool copy \
  tmp/deploy/images/raspberrypi4-64/core-image-full-cmdline-raspberrypi4-64.wic.bz2 \
  /dev/sdX
```

## How to Change IP Address

The system is initially configured with the fixed IP address 192.168.244.10.

```bash
# SSH connection
ssh root@192.168.244.10
```

**Security Warning:**
This system is configured for root SSH access without password authentication for testing convenience.
This poses security risks and should only be used in isolated test environments.
For production use, configure proper SSH key authentication and disable root login.

### Method 1: Change Before Build (Recommended)

To change the fixed IP address, edit the configuration file before building:
`meta-custom/recipes-connectivity/connman/files/ethernet.config`

The file content is:
```
[service_ether]
Type = ethernet
IPv4 = 192.168.244.10/255.255.255.0
IPv6 = off
```

After modifying, a rebuild is required:

```bash
# Rebuild connman package only
bitbake -c cleansstate connman
bitbake core-image-full-cmdline
```

### Method 2: Edit Built Image Directly

Edit the built image file directly without rebuilding:

```bash
# Set up image as a loopback device
IMAGE_FILE=core-image-full-cmdline-raspberrypi4-64.wic
sudo losetup -P /dev/loop0 $IMAGE_FILE

# Mount rootfs partition (e.g., loop0p2)
sudo mkdir -p /mnt/rpi-rootfs
sudo mount /dev/loop0p2 /mnt/rpi-rootfs

# Edit configuration file
sudo vim /mnt/rpi-rootfs/var/lib/connman/ethernet.config

# Example change:
# IPv4 = 192.168.1.100/255.255.255.0

# Unmount and cleanup
sudo umount /mnt/rpi-rootfs
sudo losetup -d /dev/loop0
```

## Usage

This system uses the uhubctl command to control USB port power.
For detailed usage and supported hub information, please refer to the [uhubctl official repository](https://github.com/mvp/uhubctl?tab=readme-ov-file#raspberry-pi-4b "readme-ov-file#raspberry-pi-4b").

```bash
# Check connected USB hubs
uhubctl

# USB power OFF
uhubctl --location 1-1 --action 0

# USB power ON
uhubctl --location 1-1 --action 1

# Power cycle (OFF → ON)
uhubctl --location 1-1 --action cycle --delay 1
```

## Automated Boot Test Script (Example)

This example script demonstrates how to automate the power cycling and device detection process.
It connects to the Raspberry Pi via SSH, uses `uhubctl` to power cycle the USB port, and then
waits for a specific USB device (identified by its vendor ID) to reappear.

```bash
#!/bin/bash -eu
# Script to perform automated boot testing of a USB-powered device
# connected to a Raspberry Pi 4.
# It power cycles the USB port via uhubctl on the Pi and waits for
# the specified USB device to become active.

usage() {
    cat << EOF
Usage: $0 [--help] [--rpi-host <Pi4 host address>] [--vendor-id <USB vendor ID>] [--timeout <timeout in sec>]

Examples:
    $0 --rpi-host 192.168.244.10 --vendor FFFF --timeout 60
    $0 -r 192.168.244.10 -v FFFF -t 60
EOF
}

#---------------------------------------------------------------------------------------------------
# Option Parsing
#---------------------------------------------------------------------------------------------------
TEMP=$(getopt --options 'r:v:t:h' --longoptions rpi-host:,vendor-id:,timeout:,help --name "$0" -- "$@")

eval set -- "$TEMP"
while true ; do
    case "$1" in
        -r|--rpi-host) RPI_HOST="$2" ; shift 2 ;;
        -v|--vendor-id) VENDOR_ID="$2" ; shift 2 ;;
        -t|--timeout) TIMEOUT="$2" ; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift ; break ;;
        *) echo "Invalid argumetns." ; exit 1 ;;
    esac
done

# Default values if not set by options
RPI_HOST="${RPI_HOST:-192.168.244.10}"
VENDOR_ID="${VENDOR_ID:-FFFF}"
TIMEOUT="${TIMEOUT:-60}"

echo "🚀 USB boot test starting..."

#---------------------------------------------------------------------------------------------------
# Power Cycle (OFF -> 1s wait -> ON)
#---------------------------------------------------------------------------------------------------
echo "🔌 Cycling USB power..."
ssh root@"$RPI_HOST" "uhubctl --location 1-1 --action cycle --delay 1" > /dev/null

#---------------------------------------------------------------------------------------------------
# Wait for USB device to appear
# Note: uhubctl's detection is used here because 'lsusb' might still show devices
# after power off if the kernel is older than 6.0.
# Refer to uhubctl's documentation for details:
# https://github.com/mvp/uhubctl/tree/master?tab=readme-ov-file#usb-devices-are-not-removed-after-port-power-down-on-linux
#---------------------------------------------------------------------------------------------------
echo "👀 Waiting for USB device on Pi4..."

spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
for i in $(seq 1 "$TIMEOUT"); do
    ssh root@"$RPI_HOST" uhubctl 2> /dev/null | grep -q "$VENDOR_ID" && break
    printf "\r${spinner[$((i % ${#spinner[@]}))]} Waiting... %s sec" "${i}"
    sleep 1
done

echo ""
if [[ $i == "$TIMEOUT" ]]; then
    echo "❌ Timeout: USB device not detected after ${TIMEOUT}sec"
    exit 1
fi

echo "✅ USB device detected on Pi4 - boot completed in ${i}sec"
exit 0
```
