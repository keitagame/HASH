AS = nasm
ASFLAGS = -f bin

all: bootloader.img
bootloader.bin: boot.bin stage2.bin
	cat boot.bin stage2.bin > bootloader.bin

bootloader.img: boot.bin stage2.bin
	@echo "Creating bootloader image..."
	dd if=/dev/zero of=bootloader.img bs=512 count=2880
	dd if=boot.bin of=bootloader.img conv=notrunc bs=512 count=1
	dd if=stage2.bin of=bootloader.img conv=notrunc bs=512 seek=1

boot.bin: boot.asm
	@echo "Assembling Stage 1..."
	$(AS) $(ASFLAGS) boot.asm -o boot.bin

stage2.bin: stage2.asm
	@echo "Assembling Stage 2..."
	$(AS) $(ASFLAGS) stage2.asm -o stage2.bin

clean:
	rm -f *.bin *.img

test: bootloader.img
	@echo "Testing with QEMU..."
	qemu-system-x86_64 -drive format=raw,file=bootloader.img

test-with-kernel: bootloader.img
	@echo "Testing with Linux kernel..."
	@echo "Note: You need to copy a Linux kernel to sector 34 of the image"
	qemu-system-x86_64 -drive format=raw,file=bootloader.img -m 512M

.PHONY: all clean test test-with-kernel
