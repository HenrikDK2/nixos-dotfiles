/* hold: sleeps until killed; exec'd with the argv a fake process should show */
#include <unistd.h>
int main(void) { for (;;) pause(); }
