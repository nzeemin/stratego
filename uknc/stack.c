/* The program's stack: START (STRAT1.MAC) points SP at its end.  A C array so it
 * lives in bss and costs nothing in the .SAV file.  Size = STKSIZ in STRAT1.MAC. */
char g_stack[1024] __attribute__((aligned(2)));
