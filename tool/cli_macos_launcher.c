// Resolve only installed companions; never search PATH or the working directory.
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  char executable[PATH_MAX], resolved[PATH_MAX];
  uint32_t size = sizeof(executable);
  if (_NSGetExecutablePath(executable, &size) || !realpath(executable, resolved)) {
    fputs("keybay: could not locate installed runtime\n", stderr);
    return 69;
  }
  char *slash = strrchr(resolved, '/');
  if (!slash) return 69;
  *slash = '\0';
  char runtime[PATH_MAX], module[PATH_MAX];
  if (snprintf(runtime, sizeof(runtime), "%s/keybay-runtime", resolved) >= PATH_MAX ||
      snprintf(module, sizeof(module), "%s/keybay.aot", resolved) >= PATH_MAX) return 69;
  char **arguments = calloc((size_t)argc + 2, sizeof(char *));
  if (!arguments) return 71;
  arguments[0] = runtime;
  arguments[1] = module;
  for (int i = 1; i < argc; ++i) arguments[i + 1] = argv[i];
  execv(runtime, arguments);
  fputs("keybay: could not start installed runtime\n", stderr);
  free(arguments);
  return 69;
}
