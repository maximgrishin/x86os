bits 16

global Create_IdleProc
global Proc_Switch
global Interrupt_Init

INT_SYSCALL equ 0x80
PUTS equ 0x00
GETS equ 0x01
CREATE_PROCESS equ 0x02
EXIT_PROCESS equ 0x03
TERMINATE_PROCESS equ 0x04
WAIT_FOR_PROCESS equ 0x05

INT_CLOCK equ 0x08
KERNEL_SEGMENT equ 0
extern PROC_IDLE_PID

IdleProc:
  sti
.halt:
  hlt
  jmp .halt
times 600 db 0 ; for stack
IdleProcEnd:
db 0
dw 4
 IdleProcEnd2:

Create_IdleProc:
  push dword [PROC_IDLE_PID]
  push dword IdleProcEnd
  push dword IdleProc
  push dword KERNEL_SEGMENT
  call dword Proc_CreateWithEntryAddress
  add esp, 16
  retd

Proc_Switch:
  int INT_CLOCK
  retd

Interrupt_Init:
  cli
  mov [INT_SYSCALL*4], word ISR_Syscall
  mov [INT_SYSCALL*4+2], cs
  mov [INT_CLOCK*4], word ISR_Clock
  mov [INT_CLOCK*4+2], cs
  sti
  retd


NESTED_LEVEL equ 26 ; iret (6) + retd (4) + retd (4)

extern Syscall_Puts
extern Syscall_Gets
extern Syscall_CreateProcess
extern Syscall_ExitProcess
extern Syscall_TerminateProcess
extern Syscall_WaitForProcess

ISR_Syscall:
  pusha
  cmp al, PUTS
  je .Puts
  cmp al, GETS
  je .Gets
  cmp al, CREATE_PROCESS
  je .create_process
  cmp al, EXIT_PROCESS
  je .exit_process
  cmp al, TERMINATE_PROCESS
  je .terminate_process
  cmp al, WAIT_FOR_PROCESS
  je .wait_for_process
  jmp .end
.Puts:
  mov eax, [esp+16+6+4]
  push eax
  call dword Syscall_Puts
  add esp, 4
  jmp .end
.Gets:
  mov eax, [esp+16+6+4]
  push eax
  call dword Syscall_Gets
  add esp, 4
  jmp .end
.create_process:
  mov eax, [esp+16+6+4]
  push eax
  call dword Syscall_CreateProcess
  add esp, 4
  jmp .end
.exit_process:
  mov eax, [esp+16+6+4]
  push eax
  call dword Syscall_ExitProcess
  add esp, 4
  jmp .end
.terminate_process:
  mov eax, [esp+16+6+4]
  push eax
  call dword Syscall_TerminateProcess
  add esp, 4
  jmp .end
.wait_for_process:
  mov eax, [esp+16+6+4]
  push eax
  call dword Syscall_WaitForProcess
  add esp, 4
  jmp .end
.end:
  popa
  iret

global WriteCharToTty
extern ttyCurrent

WriteCharToTty:
  mov eax, [esp+4]
  mov ah, 0x05
  int 0x10
  mov eax, [esp+8]
  mov ah, 0x0E
  int 0x10
  mov eax, [ttyCurrent]
  mov ah, 0x05
  int 0x10
  retd

extern procCurrentPID

global CopyFromDiskToMemoryCHS
CopyFromDiskToMemoryCHS:
  pusha
  mov dl, 0 ; DiskNum
.DiskReset:
  mov ah, 0
  int 0x13
  jc .DiskReset

  mov ax, [esp+0x18] ; dst segment
  mov es, ax
  mov bx, 0x0000 ; offset
  mov ah, 0x02
  mov al, [esp+0x1C] ; no. of segments
  mov ch, [esp+0x20] ; cylinder
  mov cl, [esp+0x28] ; sector ; 36 sectors per track; we need sector "42"
  mov dh, [esp+0x24] ; head
  ;mov dl, [esp+0x14] ; disk no.
  int 0x13
  jnc .ReadDone
  jmp .DiskReset
.ReadDone:
  popa
  retd

global Proc_CreateWithEntryAddress
Proc_CreateWithEntryAddress:
  mov ax, [esp+0x04]
  mov [.proc_segment], ax
  mov ax, [esp+0x08]
  mov [.proc_offset], ax
  mov ax, [esp+0x0C]
  mov [.proc_size], ax
  mov ax, [esp+0x10]
  mov [.proc_ID], ax
  cli
  push ds
  mov ax, cs
  mov ds, ax
  ;
  mov [.saved_ss], ss
  mov [.saved_sp], sp
  mov ax, [procCurrentPID]
  mov [.saved_proc], ax
  ;
  mov ax, [.proc_segment]
  mov ss, ax
  mov sp, [.proc_size]
  ; form interrupt return address
  mov ax, [.proc_offset]
  push ax
  mov ax, [.proc_segment]
  push ax
  pushf
  ;
  mov cx, [.proc_ID]
  mov [procCurrentPID], cx
  mov ds, ax
  call dword SaveSnapshot
  mov ax, cs
  mov ds, ax
  ;
  mov ax, [.saved_proc]
  mov [procCurrentPID], ax
  mov ss, [.saved_ss]
  mov sp, [.saved_sp]
  ;
  pop ds
  sti
  retd
.saved_proc dw 0
.saved_ss dw 0
.saved_sp dw 0
.proc_segment dw 0
.proc_offset dw 0
.proc_size dw 0
.proc_ID dw 0

extern Proc_Schedule
ISR_Clock:
  call dword UpdateKeyboardBuffer
  call dword SaveSnapshot
  call dword Proc_Schedule
  call dword LoadSnapshot
.EOI:
  push ax
  mov al, 0x20
  out 0x20, al
  pop ax
  iret

UpdateKeyboardBuffer:
  push ax
  pushf
.read_key:
  mov ah, 0x01
  int 0x16
  jz .no_char
  mov ah, 0x00
  int 0x16
  pusha
  push ds
  push es
  xor cx, cx
  mov cl, ah
  xor bx, bx
  mov bl, al
  mov ax, cs
  mov ds, ax
  mov es, ax
  push word 0
  push cx
  push word 0
  push bx
extern Input_Handler
  call dword Input_Handler
  add esp, 8
  pop es
  pop ds
  popa
  jmp .read_key
.no_char:
  popf
  pop ax
  retd

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

.halt:
  cli
  hlt
  jmp .halt

global Video_ChangeActivePage
Video_ChangeActivePage:
  mov eax, [esp+4]
  mov ah, 0x05
  int 0x10
  retd

SaveSnapshot: ; save all the registers on stack and update the table
  push eax
  mov eax, [esp+4]
  sub esp, 42 ; 22-4-4
  push eax
  add esp, 46 ; 22-4
  pop eax
  add esp, 4 ; forget ret address
  pushad
  pushf
  push 0
  push es
  push 0
  push ds
  push 0
  push ss
  push 0
  push cs
  sub esp, 4 ; remember ret address
  ;


  mov ax, cs
  mov ds, ax
  ;
  push 0
  push ss
  mov ax, sp
  add ax, 8
  push eax
  extern Proc_SaveStackRegsAsCurrent
  call dword Proc_SaveStackRegsAsCurrent
  add esp, 8
  retd
.ret_address dw 0

LoadSnapshot:
  pop edx
  
extern Proc_GetCurrentSS
  call dword Proc_GetCurrentSS
  mov ss, ax
  
extern Proc_GetCurrentSP
  call dword Proc_GetCurrentSP
  mov sp, ax
  
  push edx
  ;
  add esp, 4
  pop ax
  pop ax
  pop ss
  pop ax
  pop ds
  pop ax
  pop es
  pop ax
  popf
  popad
  sub esp, 4 ; make room for ret address
  push eax
  mov eax, [esp-46]
  add esp, 8
  push eax
  sub esp, 4
  pop eax
  retd

global Wait1Sec
Wait1Sec:
  mov ecx, 100000000
.loop:
  dec ecx
  jnz .loop
  retd

