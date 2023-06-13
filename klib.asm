bits 16

extern _main
global Puts
global Gets
global CreateProcess
global ExitProcess
global TerminateProcess
global WaitForProcess

global _start
_start:
  sti
  call dword _main
  call dword ExitProcess

SYSCALL_INT_NUM equ 0x80
PUTS equ 0x00
GETS equ 0x01
CREATE_PROCESS equ 0x02
EXIT_PROCESS equ 0x03
TERMINATE_PROCESS equ 0x04
WAIT_FOR_PROCESS equ 0x05

Puts:
  mov al, PUTS
  int SYSCALL_INT_NUM
  sti
  retd

Gets:
  mov al, GETS
  int SYSCALL_INT_NUM
  sti
  retd

CreateProcess:
  mov al, CREATE_PROCESS
  int SYSCALL_INT_NUM
  sti
  retd

ExitProcess:
  mov al, EXIT_PROCESS
  int SYSCALL_INT_NUM
  sti
  retd

TerminateProcess:
  mov al, TERMINATE_PROCESS
  int SYSCALL_INT_NUM
  sti
  retd

WaitForProcess:
  mov al, WAIT_FOR_PROCESS
  int SYSCALL_INT_NUM
  sti
  retd

