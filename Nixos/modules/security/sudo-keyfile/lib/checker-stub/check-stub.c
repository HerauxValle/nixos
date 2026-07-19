#include <unistd.h>
int main(void) {
  execl("@BASH_BIN@", "bash", "-p", "@CHECKER_BIN@", (char *)NULL);
  return 1;
}
