#include "klib.h"

void _main()
{
  char a[16];
  volatile int i;
  while (1) {
    Puts("1");
    i = 1e8;
    while(i--);
  }
}

