/*
 * qmx-launcher.c - main program of "QMX+ Configurator.app".
 *
 * A compiled main program is what lets the app be signed with a Developer ID
 * and notarized by Apple: a shell script as the main program keeps its
 * signature in extended attributes, which git and most zip tools drop.
 * All the real work is in Contents/Resources/qmx-launcher.sh, which this
 * program runs with /bin/bash. Built by qmx-sign-notarize-app.sh:
 *
 *   clang -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 \
 *         -o "QMX+ Configurator.app/Contents/MacOS/qmx-launcher" launcher/qmx-launcher.c
 */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

static int self_path(char *out, size_t size) {
#ifdef __APPLE__
    char raw[PATH_MAX * 2];
    uint32_t n = sizeof raw;
    if (_NSGetExecutablePath(raw, &n) != 0) return -1;
    return realpath(raw, out) ? 0 : -1;
#else
    ssize_t n = readlink("/proc/self/exe", out, size - 1);   /* for testing on Linux */
    if (n < 0) return -1;
    out[n] = '\0';
    return 0;
#endif
}

int main(void) {
    char exe[PATH_MAX], script[PATH_MAX + 64];
    if (self_path(exe, sizeof exe) != 0) {
        perror("qmx-launcher: cannot find its own location");
        return 1;
    }
    char *slash = strrchr(exe, '/');                 /* .../Contents/MacOS/qmx-launcher */
    if (!slash) return 1;
    *slash = '\0';                                   /* .../Contents/MacOS */
    snprintf(script, sizeof script, "%s/../Resources/qmx-launcher.sh", exe);
    char *argv[] = {"bash", script, NULL};
    execv("/bin/bash", argv);
    perror("qmx-launcher: cannot run /bin/bash");
    return 1;
}
