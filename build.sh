#!/bin/bash

# Build and test script for Linux Bootloader

set -e

echo "========================================"
echo "Linux Bootloader - Build & Test Script"
echo "========================================"
echo ""

# Check dependencies
check_dependencies() {
    echo "Checking dependencies..."
    
    if ! command -v nasm &> /dev/null; then
        echo "ERROR: NASM not found. Please install: sudo apt-get install nasm"
        exit 1
    fi
    
    if ! command -v make &> /dev/null; then
        echo "ERROR: make not found. Please install: sudo apt-get install make"
        exit 1
    fi
    
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        echo "WARNING: QEMU not found. Testing will not be available."
        echo "Install with: sudo apt-get install qemu-system-x86"
    fi
    
    echo "✓ Dependencies OK"
    echo ""
}

# Build bootloader
build() {
    echo "Building bootloader..."
    make clean
    make
    echo "✓ Build complete"
    echo ""
}

# Show file information
show_info() {
    echo "Generated files:"
    ls -lh boot.bin stage2.bin bootloader.img 2>/dev/null || true
    echo ""
    
    echo "Boot sector (first 32 bytes):"
    hexdump -C bootloader.img | head -3
    echo ""
    
    echo "Boot signature (last 2 bytes of sector 1):"
    dd if=bootloader.img bs=1 skip=510 count=2 2>/dev/null | hexdump -C
    echo ""
}

# Test with QEMU
test_qemu() {
    if command -v qemu-system-x86_64 &> /dev/null; then
        echo "Starting QEMU test..."
        echo "Press Ctrl+C to exit"
        echo ""
        qemu-system-x86_64 -drive format=raw,file=bootloader.img -m 512M
    else
        echo "QEMU not available, skipping test"
    fi
}

# Create bootable USB image instructions
usb_instructions() {
    echo "========================================"
    echo "Creating Bootable USB (Linux)"
    echo "========================================"
    echo ""
    echo "WARNING: This will erase all data on the USB drive!"
    echo ""
    echo "1. Insert USB drive and find device name:"
    echo "   lsblk"
    echo ""
    echo "2. Unmount if mounted:"
    echo "   sudo umount /dev/sdX*"
    echo ""
    echo "3. Write bootloader to USB:"
    echo "   sudo dd if=bootloader.img of=/dev/sdX bs=512"
    echo ""
    echo "4. Sync and eject:"
    echo "   sync"
    echo "   sudo eject /dev/sdX"
    echo ""
    echo "Replace /dev/sdX with your actual USB device!"
    echo ""
}

# Main menu
show_menu() {
    echo "========================================"
    echo "What would you like to do?"
    echo "========================================"
    echo "1) Build bootloader"
    echo "2) Build and test with QEMU"
    echo "3) Show file information"
    echo "4) Show USB creation instructions"
    echo "5) Clean build files"
    echo "6) Exit"
    echo ""
    read -p "Enter choice [1-6]: " choice
    
    case $choice in
        1)
            build
            show_info
            ;;
        2)
            build
            show_info
            test_qemu
            ;;
        3)
            show_info
            ;;
        4)
            usb_instructions
            ;;
        5)
            make clean
            echo "✓ Clean complete"
            ;;
        6)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
    
    echo ""
    show_menu
}

# Start
check_dependencies

if [ "$1" == "--build" ]; then
    build
    show_info
elif [ "$1" == "--test" ]; then
    build
    show_info
    test_qemu
else
    show_menu
fi
