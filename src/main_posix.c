/* POSIX host entry point, using only xboxrecomp runtime APIs. */
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>

#include <xbox/xboxrecomp.h>
#include "recomp_types.h"
#include "kernel/xbox_memory_layout.h"
#include "kernel/nv2a_backend.h"
#include "kernel/nv2a_backend_gl.h"
#include "video/video_player.h"

#define UC2_ENTRY_POINT 0x0026867Fu
#define UC2_XBE_PATH "game/default.xbe"
#define UC2_GAME_DIR "game"

typedef void (*recomp_func_t)(void);
extern recomp_func_t recomp_lookup(uint32_t xbox_va);
extern int recomp_dispatch_init(void);
extern MCPXAPUState *g_apu_state;
static MCPXAPUState *s_apu_exit_cleanup;

static void shutdown_apu_at_exit(void)
{
    MCPXAPUState *apu = s_apu_exit_cleanup;

    if (!apu)
        return;
    s_apu_exit_cleanup = NULL;
    g_apu_state = NULL;
    mcpx_apu_shutdown(apu);
}

/* UC2's statically linked D3D keeps the GPU semaphore VA in its singleton
 * root at 0x393888 + 0x30. xboxrecomp's pushbuffer executor can publish
 * BACK_END_WRITE_SEMAPHORE_RELEASE there, but needs the title's semaphore VA
 * registered through nv2a_pb_set_semaphore_target(). The D3D root is created
 * by guest code, so watch for it after boot starts instead of hard-coding the
 * allocator's current contiguous-memory address. */
static atomic_int s_sem_watch_stop;

static void *watch_d3d_semaphore(void *unused)
{
    const struct timespec delay = { 0, 1000000 };
    const uintptr_t mem_offset = (uintptr_t)xbox_GetMemoryOffset();

    (void)unused;
    while (!atomic_load_explicit(&s_sem_watch_stop, memory_order_relaxed)) {
        uint32_t root = *(volatile uint32_t *)(mem_offset + 0x00393888u);

        if (root >= 0x00010000u && root < 0x00400000u) {
            uint32_t sem = *(volatile uint32_t *)(mem_offset + root + 0x30u);

            if (sem >= 0x80000000u && sem < 0x84000000u) {
                nv2a_pb_set_semaphore_target(sem);
                fprintf(stderr, "[NV2A] D3D semaphore release target: 0x%08X\n",
                        sem);
                fflush(stderr);
                return NULL;
            }
        }
        nanosleep(&delay, NULL);
    }
    return NULL;
}

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
    MCPXAPUState *apu = NULL;
    pthread_t sem_watch;
    int sem_watch_started = 0;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    fprintf(stderr, "Unreal Championship 2 recomp\n");

    /* The NV2A executor is required: without it the toolkit's fallback
     * rasterizer writes guest pixels on the CPU. UC2 always uses the GPU. */
    if (!getenv("RECOMP_PB_EXEC"))
        setenv("RECOMP_PB_EXEC", "1", 1);

    if (!load_xbe(UC2_XBE_PATH, &xbe_data, &xbe_size))
        return 1;
    if (!xbox_MemoryLayoutInit(xbe_data, xbe_size)) {
        fprintf(stderr, "Xbox memory layout initialization failed\n");
        free(xbe_data);
        return 1;
    }

    /* xboxrecomp unmaps the APU register aperture when AC'97 emulation is
     * enabled. Initialize its matching APU model before guest MMIO can fault. */
    if (getenv("RECOMP_AC97_READY")) {
        apu = mcpx_apu_init_standalone((uint8_t *)xbox_GetMemoryBase());
        if (!apu) {
            fprintf(stderr, "[BOOT] xboxrecomp APU initialization failed\n");
            xbox_MemoryLayoutShutdown();
            free(xbe_data);
            return 1;
        }
        g_apu_state = apu;
        s_apu_exit_cleanup = apu;
        atexit(shutdown_apu_at_exit);
    }

    xbox_kernel_init();
    xbox_path_init(UC2_GAME_DIR, NULL);
    xbox_kernel_bridge_init();
    g_esp = XBOX_STACK_TOP;

    /* Opt-in xboxrecomp diagnostic: dumps the guest register/stack state and
     * exits after RECOMP_WATCHDOG_SECS while the title is still running. */
    if (getenv("RECOMP_WATCHDOG_SECS"))
        xbox_WatchdogStart();

    if (!recomp_dispatch_init())
        fprintf(stderr, "[BOOT] flat dispatch unavailable; using lookup fallback\n");

    entry = recomp_lookup(UC2_ENTRY_POINT);
    if (!entry) {
        fprintf(stderr, "No recompiled entry point for VA 0x%08X\n",
                UC2_ENTRY_POINT);
        s_apu_exit_cleanup = NULL;
        g_apu_state = NULL;
        mcpx_apu_shutdown(apu);
        xbox_kernel_shutdown();
        xbox_MemoryLayoutShutdown();
        free(xbe_data);
        return 1;
    }

    /* UC2 uses the low-level NV2A pushbuffer path rather than the toolkit's
     * D3D8 API. Require its OpenGL GPU rasterizer so a missing hardware driver
     * cannot silently send the game through the CPU pixel renderer. */
    if (!nv2a_gl_backend_init()) {
        fprintf(stderr, "[BOOT] could not initialize the required OpenGL GPU renderer\n");
        s_apu_exit_cleanup = NULL;
        g_apu_state = NULL;
        mcpx_apu_shutdown(apu);
        xbox_kernel_shutdown();
        xbox_MemoryLayoutShutdown();
        free(xbe_data);
        return 1;
    }

    fprintf(stderr, "Starting guest entry point 0x%08X\n", UC2_ENTRY_POINT);
    atomic_store_explicit(&s_sem_watch_stop, 0, memory_order_relaxed);
    if (pthread_create(&sem_watch, NULL, watch_d3d_semaphore, NULL) == 0)
        sem_watch_started = 1;
    else
        fprintf(stderr, "[NV2A] could not start D3D semaphore watcher\n");
    entry();

    nv2a_gl_backend_shutdown();

    atomic_store_explicit(&s_sem_watch_stop, 1, memory_order_relaxed);
    if (sem_watch_started)
        pthread_join(sem_watch, NULL);

    s_apu_exit_cleanup = NULL;
    g_apu_state = NULL;
    mcpx_apu_shutdown(apu);
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
    /* With the OpenGL NV2A backend, let the toolkit scan out its render
     * target directly when the framebuffer window is enabled. Set to 0 to
     * retain SDL's CPU-copy presenter for comparison. */
    if (getenv("RECOMP_FB_WINDOW") && !getenv("RECOMP_GL_PRESENT"))
        setenv("RECOMP_GL_PRESENT", "1", 0);
    /* The toolkit's GP/EP DSP is a passthrough HLE. Soft limiting prevents
     * its multi-mixbin fallback from hard-clipping dense UC2 effects. */
    if (!getenv("RECOMP_APU_DSP_SOFT_LIMIT"))
        setenv("RECOMP_APU_DSP_SOFT_LIMIT", "1", 0);
    return xbox_HostWindowMain(boot_and_run);
}
