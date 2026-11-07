/* POSIX host entry point, using only xboxrecomp runtime APIs. */
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <xbox/xboxrecomp.h>
#include "recomp_types.h"
#include "kernel/xbox_memory_layout.h"
#include "video/video_player.h"

#define UC2_ENTRY_POINT 0x0026867Fu
#define UC2_XBE_PATH "game/default.xbe"
#define UC2_GAME_DIR "game"

typedef void (*recomp_func_t)(void);
extern recomp_func_t recomp_lookup(uint32_t xbox_va);
extern int recomp_dispatch_init(void);

static void on_fault(int sig, siginfo_t *info, void *context)
{
    if (xbox_PosixMmioFault(context, (uintptr_t)info->si_addr))
        return;

    fprintf(stderr, "[FAULT] signal %d at %p\n", sig, info->si_addr);
    signal(sig, SIG_DFL);
    raise(sig);
}

static int load_xbe(const char *path, void **data_out, size_t *size_out)
{
    FILE *file = fopen(path, "rb");
    long length;
    void *data;

    if (!file) {
        perror(path);
        return 0;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (length = ftell(file)) <= 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        fprintf(stderr, "Could not determine XBE size: %s\n", path);
        return 0;
    }

    data = malloc((size_t)length);
    if (!data) {
        fclose(file);
        fprintf(stderr, "Out of memory reading XBE (%ld bytes)\n", length);
        return 0;
    }
    if (fread(data, 1, (size_t)length, file) != (size_t)length) {
        fprintf(stderr, "Short read loading XBE: %s\n", path);
        free(data);
        fclose(file);
        return 0;
    }

    fclose(file);
    *data_out = data;
    *size_out = (size_t)length;
    return 1;
}

static int boot_and_run(void)
{
    void *xbe_data = NULL;
    size_t xbe_size = 0;
    recomp_func_t entry;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    fprintf(stderr, "Unreal Championship 2 recomp\n");

    if (!load_xbe(UC2_XBE_PATH, &xbe_data, &xbe_size))
        return 1;
    if (!xbox_MemoryLayoutInit(xbe_data, xbe_size)) {
        fprintf(stderr, "Xbox memory layout initialization failed\n");
        free(xbe_data);
        return 1;
    }

    xbox_kernel_init();
    xbox_path_init(UC2_GAME_DIR, NULL);
    xbox_kernel_bridge_init();
    g_esp = XBOX_STACK_TOP;

    if (!recomp_dispatch_init())
        fprintf(stderr, "[BOOT] flat dispatch unavailable; using lookup fallback\n");

    entry = recomp_lookup(UC2_ENTRY_POINT);
    if (!entry) {
        fprintf(stderr, "No recompiled entry point for VA 0x%08X\n",
                UC2_ENTRY_POINT);
        xbox_kernel_shutdown();
        xbox_MemoryLayoutShutdown();
        free(xbe_data);
        return 1;
    }

    fprintf(stderr, "Starting guest entry point 0x%08X\n", UC2_ENTRY_POINT);
    entry();

    xbox_kernel_shutdown();
    xbox_MemoryLayoutShutdown();
    free(xbe_data);
    return 0;
}

int main(void)
{
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = on_fault;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGSEGV, &action, NULL);
#ifdef SIGBUS
    sigaction(SIGBUS, &action, NULL);
#endif
    return xbox_HostWindowMain(boot_and_run);
}
