#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "klib.h"

#define MEM_BYTES_PER_APP 0x3000
#define MEM_BYTES_PER_SEGMENT 0x10
#define MEM_SEGMENTS_PER_APP (MEM_BYTES_PER_APP/MEM_BYTES_PER_SEGMENT)
#define DISK_BYTES_PER_BLOCK 512
#define DISK_BLOCKS_PER_APP (MEM_BYTES_PER_APP/DISK_BYTES_PER_BLOCK)
#define DISK_APPS_OFFSET_IN_BLOCKS 0x3D
#define MEM_APPS_OFFSET_IN_SEGMENTS 0x820
#define PROC_MAX 16
const int PROC_IDLE_PID = 16;
#define VIDEO_PAGES_TOTAL 4
#define LINE_LENGTH_MAX 16

uint16_t procCurrentPID = 0;
int BOOT_DISK_NUM = 0;
int SECTORS_PER_TRACK = 36;
unsigned ttyCurrent = 0;
char keyboardBuffer[VIDEO_PAGES_TOTAL][LINE_LENGTH_MAX];
int keyboardBufferHead[VIDEO_PAGES_TOTAL];

typedef struct Proc {
  int16_t sp;
  int16_t ss;
  bool isPresent;
  int parentID;
  int terminalID;
  int waitingForExitID;
  bool isWaitingForInput;
  char input[16];
  int inputLength;
} Proc;

Proc procTable[PROC_MAX+1];

void Syscall_Puts(char * str);
void Syscall_Gets(char * str);
int Syscall_CreateProcess(char name[]);
void Syscall_ExitProcess();
void Syscall_WaitForProcess(int pid);
void Syscall_TerminateProcess(int procID);

extern void Interrupt_Init();
extern void WriteCharToTty(int page, char);

int ConvertPidToSegment(int pid);
void WriteStringToTty(int page, char * str);

void print_digit_decimal(int digit);
void print_ud(uint32_t n);
int strcmp(char * str1, char * str2);
void ConvertLBAToCHS(int lba, int *track, int *head, int *sector);
void CopyFromDiskToMemoryLBA(int srcBlock, int dstSegment, int countBlocks);
char * FS_IndexToName(int i);
int GetSrcBlockFromFilename(char name[]);
int FindFreeProcTableEntry();
void SpawnProcTableEntry(int entry);

void Proc_TerminateChildrenTree(int procID);
void Proc_SaveStackRegsAsCurrent(int sp, int ss);
int Proc_GetCurrentSS();
int Proc_GetCurrentSP();
bool Proc_IsResumable(int pid);

void Proc_Schedule();
void Input_Handler(uint8_t ascii, uint8_t scan);
void _main();

#define NO_SUCH_FILE -1
#define NO_MEMORY_AVAILABLE -1

int Syscall_CreateProcess(char name[])
{
  int srcBlock = GetSrcBlockFromFilename(name);
  
  int pid = FindFreeProcTableEntry();
  if (srcBlock != NO_SUCH_FILE && pid != NO_MEMORY_AVAILABLE) {
    CopyFromDiskToMemoryLBA(srcBlock, ConvertPidToSegment(pid), DISK_BLOCKS_PER_APP);
    Proc_CreateWithEntryAddress(ConvertPidToSegment(pid), 0, DISK_BLOCKS_PER_APP*DISK_BYTES_PER_BLOCK, pid);
    SpawnProcTableEntry(pid);
  }
  return pid;
}

int ConvertPidToSegment(int pid)
{
  return MEM_APPS_OFFSET_IN_SEGMENTS + MEM_SEGMENTS_PER_APP*pid;
}

void WriteStringToTty(int page, char * str)
{
  int i = 0;
  while (str[i] != 0) {
    WriteCharToTty(page, str[i]);
    i++;
  }
}

void Syscall_Puts(char * str)
{
  WriteStringToTty(procTable[procCurrentPID].terminalID, str);
}

void print_digit_decimal(int digit)
{
  if (digit < 0)
    digit = 0;
  if (digit > 9)
    digit = 9;
  WriteCharToTty(0, '0' + digit);
}

void print_ud(uint32_t n)
{
  int base = 1;
  while (base <= n/10) {
    base *= 10;
  }
  int k = n;
  while (base != 1) {
    print_digit_decimal(k / base);
    k %= base;
    base /= 10;
  }
  print_digit_decimal(k);
  WriteCharToTty(0, ' ');
}

int strcmp(char * str1, char * str2)
{
  const int NOT_READY = 42;
  const int EQUAL = 0;
  const int LOWER = -1;
  const int GREATER = 1;
  int cmp = NOT_READY;
  int i = 0;
  while (cmp == NOT_READY) {
    if (str1[i] < str2[i]) {
      cmp = LOWER;
    } else if (str1[i] > str2[i]) {
      cmp = GREATER;
    } else if ((str1[i] == 0) && (str2[i] == 0)) {
      cmp = EQUAL;
    }
    i++;
  }
  return cmp;
}

void ConvertLBAToCHS(int lba, int *track, int *head, int *sector)
{
	(*track) = (lba / (SECTORS_PER_TRACK * 2));
	(*head) = (lba % (SECTORS_PER_TRACK * 2)) / SECTORS_PER_TRACK;
	(*sector) = (lba % SECTORS_PER_TRACK + 1);
}

void CopyFromDiskToMemoryLBA(int srcBlock, int dstSegment, int countBlocks)
{
  int cylinder;
  int head;
  int sector;
  ConvertLBAToCHS(srcBlock, &cylinder, &head, &sector);
  CopyFromDiskToMemoryCHS(BOOT_DISK_NUM, dstSegment, countBlocks, cylinder, head, sector);
}

char * FS_IndexToName(int i)
{
  return (char*)0x8000 + 0x20*i;
}

int GetSrcBlockFromFilename(char name[])
{
  for (int i = 0; i < PROC_MAX; i++) {
    if (strcmp(name, FS_IndexToName(i)) == 0) {
      return DISK_APPS_OFFSET_IN_BLOCKS + i*DISK_BLOCKS_PER_APP;
    }
  }
  return NO_SUCH_FILE;
}

int FindFreeProcTableEntry()
{
  int i;
  for (i = 0; i < PROC_MAX; i++) {
    if (procTable[i].isPresent == false) {
      break;
    }
  }
  if (i == PROC_MAX) {
    return -1;
  }
  return i;
}

void SpawnProcTableEntry(int entry)
{
  procTable[entry].isPresent = true;
  procTable[entry].waitingForExitID = -1;
  procTable[entry].isWaitingForInput = false;
  procTable[entry].parentID = procCurrentPID;
  procTable[entry].terminalID = procTable[procCurrentPID].terminalID;
  procTable[entry].inputLength = 0;
}

void Syscall_ExitProcess()
{
  procTable[procCurrentPID].isPresent = false;
  Proc_Switch();
}

void Syscall_WaitForProcess(int pid)
{
  procTable[procCurrentPID].waitingForExitID = pid;
  Proc_Switch(); 
}

void Syscall_TerminateProcess(int procID)
{
  if (procTable[procID].parentID == procCurrentPID) {
    Proc_TerminateChildrenTree(procID);
  }
}

void Proc_TerminateChildrenTree(int procID)
{
  if (procID < 0 || procID >= PROC_MAX) {
    return;
  }
  procTable[procID].isPresent = false;
  for (int i = 0; i < PROC_MAX; i++) {
    if (procTable[i].isPresent) {
      if (procTable[i].parentID == procID) {
        Proc_TerminateChildrenTree(i);
      } else if (procTable[i].waitingForExitID == procID) {
        procTable[i].waitingForExitID = -1;
      }
    }
  }
}

void Proc_SaveStackRegsAsCurrent(int sp, int ss)
{
  procTable[procCurrentPID].ss = ss;
  procTable[procCurrentPID].sp = sp;
}

int Proc_GetCurrentSS()
{
  return procTable[procCurrentPID].ss;
}

int Proc_GetCurrentSP()
{
  return procTable[procCurrentPID].sp;
}

void Syscall_Gets(char * str)
{
  procTable[procCurrentPID].isWaitingForInput = true;
  Proc_Switch();
  int i;
  for (i = 0; i < procTable[procCurrentPID].inputLength; i++) {
    str[i] = procTable[procCurrentPID].input[i];
  }
  str[i] = 0;
}

bool Proc_IsResumable(int pid)
{
  return (procTable[pid].isPresent
    && (procTable[pid].waitingForExitID == -1)
    && !procTable[pid].isWaitingForInput);
}

void Proc_Schedule()
{
  int i;
  for (i = 0; i < PROC_MAX; i++) {
    int candidate_pid = (procCurrentPID + i + 1)%PROC_MAX;
    if (Proc_IsResumable(candidate_pid) && candidate_pid != PROC_IDLE_PID) {
      procCurrentPID = candidate_pid;
      break;
    }
  }
  if (i == PROC_IDLE_PID) {
    procCurrentPID = PROC_IDLE_PID;
  }
}

void Input_Handler(uint8_t ascii, uint8_t scan)
{
  const char ENTER = 0x1C;
  const char BACKSPACE = 0x0E;
  const char F1 = 0x3B;
  const char F4 = 0x3E;
  if (scan == ENTER) {
    for (int i = 0; i < PROC_MAX; i++) {
      if (procTable[i].isWaitingForInput == true && procTable[i].terminalID == ttyCurrent) {
        procTable[i].inputLength = keyboardBufferHead[ttyCurrent];
        for (int j = 0; j < procTable[i].inputLength; j++) {
          procTable[i].input[j] = keyboardBuffer[ttyCurrent][j];
        }
        procTable[i].isWaitingForInput = false;
      }
    }
    WriteStringToTty(ttyCurrent, "\n\r");
    keyboardBufferHead[ttyCurrent] = 0;
  }
  else if (scan == BACKSPACE) {
    keyboardBufferHead[ttyCurrent]--;
    if (keyboardBufferHead[ttyCurrent] < 0)
      keyboardBufferHead[ttyCurrent] = 0;
    WriteStringToTty(ttyCurrent, "\b \b");
  }
  else if (F1 <= scan && scan <= F4) {
    ttyCurrent = scan - F1;
    Video_ChangeActivePage(ttyCurrent);
  }
  else {
    if (keyboardBufferHead[ttyCurrent] < LINE_LENGTH_MAX) {
      keyboardBuffer[ttyCurrent][keyboardBufferHead[ttyCurrent]] = ascii;
      WriteCharToTty(ttyCurrent, ascii);
      keyboardBufferHead[ttyCurrent]++;
    }
  }
}

void _main()
{
  for (int i = 0; i < PROC_MAX; i++) {
    procTable[i].isPresent = false;
  }
  procCurrentPID = 0;
  procTable[0].terminalID = 0;
  SpawnProcTableEntry(0);
  Interrupt_Init();
  Create_IdleProc();
  CopyFromDiskToMemoryLBA(0x3C, 0x800, 1);
  
  WriteStringToTty(0, "display page 1\n\r");
  WriteStringToTty(1, "display page 2\n\r");
  WriteStringToTty(2, "display page 3\n\r");
  WriteStringToTty(3, "display page 4\n\r");
  
  
  char super[16];
  Gets(super);
  Puts(super);
  Puts("\n\r");
  
  int pid;
  pid = CreateProcess("print_digits");

  int u;
  while (1) {
    Puts("a");
    u = 1e8;
    while(u--);
  }
}
