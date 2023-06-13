#ifndef KLIB_H
#define KLIB_H

#include <stdint.h>
#include <stddef.h>
void puts(char buffer[]);
void gets(char buffer[]);
int CreateProcess(char filename[]);
void ExitProcess();
void TerminateProcess(int pid);
void WaitForProcess(int pid);

#endif
