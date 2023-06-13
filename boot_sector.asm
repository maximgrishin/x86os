KERNEL_SEGMENT equ 0
KERNEL_OFFSET equ 0x0600
KERNEL_SIZE equ 0x7600
KERNEL_SP equ 0x8000
SECTOR_SIZE equ 0x200
KERNEL_SIZE_IN_SECTORS equ 0x3b

org 0x7c00
bits 16

  jmp KERNEL_SEGMENT:Begin
Begin:
  xor ax, ax
  mov ss, ax
  mov es, ax
  mov ds, ax
  mov sp, KERNEL_SP
  mov [DiskNum], dl
  sti

Bootstrap:
.DiskReset:
  mov ah, 0
  int 0x13
  jc .DiskReset
  mov ax, KERNEL_SEGMENT
  mov es, ax
  mov bx, KERNEL_OFFSET
  mov ah, 0x02
  mov al, KERNEL_SIZE_IN_SECTORS
  mov ch, 0x00 ; cylinder
  mov cl, 0x02 ; sector
  mov dh, 0x00 ; head
  mov dl, [DiskNum]
  int 0x13
  jnc .ReadDone
  mov si, ReadErrorMsg
  call WriteString
  jmp .DiskReset
.ReadDone:

  jmp KERNEL_SEGMENT:KERNEL_OFFSET
  
WriteString:
  push bx
  mov bx, 0
.PrintLoop:
  lodsb ; mov al, [ds:si] 
  or al, al
  jz .PrintDone
  mov ah, 0xe ; BIOS: Write Teletype to Active Page
  int 0x10
  jmp .PrintLoop
.PrintDone:
  pop bx
  ret
  
DiskNum:
  db 0
  
ReadErrorMsg db 'Read error. Retrying...', 10, 13, 0

  times 510-($-$$) db 0
  ; Boot Signature
  dw 0xAA55
  
