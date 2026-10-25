/* kwin-usr1-guard: works around a kscreenlocker bug (ksldapp.cpp, KSldApp::lock):
 *   kill(m_lockProcess->processId(), SIGUSR1);
 * When the lock-screen greeter is not running, processId() is 0 and kill(0, ...)
 * signals KWin's whole process group; kwin_wayland_wrapper has no USR1 handler and
 * dies, taking the whole Plasma session with it (seen 2026-10-06 05:27:53).
 * This drops exactly kill(0, SIGUSR1) and passes every other kill() through. */
#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>

int kill(pid_t pid, int sig)
{
    if (pid == 0 && sig == SIGUSR1) {
        fprintf(stderr, "kwin-usr1-guard: blocked kill(0, SIGUSR1) (kscreenlocker greeter not running)\n");
        return 0;
    }
    return syscall(SYS_kill, pid, sig);
}

/* Keep the preload in kwin_wayland_wrapper and kwin_wayland only, not in apps they start. */
__attribute__((constructor)) static void usr1guard_init(void)
{
    char comm[32] = {0};
    FILE *f = fopen("/proc/self/comm", "r");
    if (f) { if (!fgets(comm, sizeof comm, f)) comm[0] = 0; fclose(f); }
    comm[strcspn(comm, "\n")] = 0;
    if (strcmp(comm, "kwin_wayland_wr") != 0)
        unsetenv("LD_PRELOAD");
}
