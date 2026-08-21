/* &desc: "Setuid-root stub -- execve()s bash directly with -p (bypasses binfmt_script's setuid-script stripping and bash's own ruid!=euid auto-drop) to run the checker script as root." */

#include <unistd.h>
int main(void) {
  execl("@BASH_BIN@", "bash", "-p", "@CHECKER_BIN@", (char *)NULL);
  return 1;
}
