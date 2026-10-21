/* Inject a child setup failure before Nix sends its startup success marker. */
#include <dlfcn.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

static pid_t parent;
static int (*real_chdir)(const char *);

__attribute__((constructor)) static void init(void)
{
    parent = getpid();
    real_chdir = dlsym(RTLD_NEXT, "chdir");
    if (!real_chdir)
        _exit(99);
}

int chdir(const char *path)
{
    const char *name = strrchr(path, '/');
    if (getpid() != parent && name && strncmp(name + 1, "nix-", 4) == 0) {
        errno = EACCES;
        return -1;
    }
    return real_chdir(path);
}
