#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    if (argc != 3 || getuid() == 0 || !isatty(1) || !isatty(2))
        return 26;

    if (strcmp(argv[1], "live") == 0) {
        /* No fflush: a terminal should make stdout line buffered. */
        puts("pty-live-ready");
        int attempt;
        for (attempt = 0; attempt < 150; attempt++) {
            if (access(argv[2], F_OK) == 0)
                break;
            usleep(100000);
        }
        if (attempt == 150)
            return 27;
    } else if (strcmp(argv[1], "burst") == 0) {
        for (int i = 0; i < 4096; i++) {
            printf("stdout-%04d\n", i);
            fprintf(stderr, "stderr-%04d\n", i);
        }
    } else if (strcmp(argv[1], "fail") == 0) {
        puts("pty-final-stdout");
        fputs("pty-final-stderr\n", stderr);
        return 23;
    } else if (strcmp(argv[1], "signal") == 0) {
        puts("pty-before-signal");
        raise(SIGTERM);
        return 29;
    }

    FILE *output = fopen(getenv("out"), "w");
    if (!output)
        return 28;
    fputs("pty-ok\n", output);
    return fclose(output) != 0;
}
