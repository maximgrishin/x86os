CC = gcc
AS = nasm
LD = ld
ASFLAGS = -f elf
CFLAGS = -ffreestanding -m16 -O2 -c

img.img: system.bin fs.img print_digits.bin
	python makeimg.py

system.bin: boot_sector.bin kernel.bin
	cat boot_sector.bin kernel.bin > system.bin

boot_sector.bin: boot_sector.asm
	$(AS) boot_sector.asm -f bin -o boot_sector.bin

kernel.bin: klib.asm kernel.asm kernel.c 
	$(AS) klib.asm -f elf -o klib.o
	$(AS) kernel.asm -f elf -o kernel_asm.o
	$(CC) $(CFLAGS) kernel.c -o kernel.o
	$(LD) -o kernel.bin -nostdlib -Ttext 0x600 --oformat binary klib.o kernel_asm.o kernel.o

print_digits.bin: print_digits.c klib.o
	$(CC) $(CFLAGS) print_digits.c -o print_digits.o
	$(LD) -o print_digits.bin -nostdlib -Ttext 0x0 --oformat binary klib.o print_digits.o

qemu: img.img
	qemu-system-i386 -fda img.img

clean:
	rm *.bin *.o
