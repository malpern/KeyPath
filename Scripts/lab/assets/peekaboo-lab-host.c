#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    const char *home = getenv("HOME");
    char executable[PATH_MAX];
    char support[PATH_MAX];
    char socket_path[PATH_MAX];

    if (home == NULL || home[0] != '/') {
        return 64;
    }
    if (snprintf(executable, sizeof(executable), "%s/.local/bin/peekaboo", home) >=
            (int)sizeof(executable) ||
        snprintf(support, sizeof(support), "%s/Library/Application Support/Peekaboo", home) >=
            (int)sizeof(support) ||
        snprintf(socket_path, sizeof(socket_path), "%s/daemon.sock", support) >=
            (int)sizeof(socket_path)) {
        return 65;
    }

    if (mkdir(support, 0700) != 0 && errno != EEXIST) {
        return 73;
    }
    unlink(socket_path);
    execl(executable,
          executable,
          "daemon",
          "run",
          "--mode",
          "manual",
          "--bridge-socket",
          socket_path,
          "--idle-timeout-seconds",
          "31536000",
          "--input-strategy",
          "actionFirst",
          (char *)NULL);
    return 127;
}
