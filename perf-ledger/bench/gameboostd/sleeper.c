/* Stand-in process for evbench/scanbench: keeps the argv it was exec'd with. */
#include <unistd.h>
int main(void) {
  for (;;)
    pause();
}
