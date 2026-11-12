#include <atomic>
#include <cstdint>
#include <cstdio>

#include "core/log.h"
#include "cpu/x86_ops.h"
#include "kernel/kernel.h"
#include "kernel/memory.h"

namespace {

constexpr uint32_t kUnreadable = 0xFFFFFFFF;

uint32_t GuestWord(uint32_t address) {
    if (address > 0xFFFFFFFC || !mem::IsCommitted(address)) return kUnreadable;
    return kernel::R32(address);
}

bool ShouldTrace(std::atomic<uint32_t>& counter, uint32_t& sample) {
    sample = counter.fetch_add(1, std::memory_order_relaxed);
    return sample < 32 || (sample % 16) == 0;
}

void GuestString(uint32_t address, uint8_t* base, char (&out)[256]) {
    out[0] = '\0';
    if (address > 0xFFFFFF00) return;
    for (uint32_t i = 0; i < 255 && address + i <= 0xFFFFFF00; ++i) {
        if (!mem::IsCommitted(address + i)) break;
        char c = static_cast<char>(base[address + i]);
        if (c == '\0') break;
        if (c < 0x20 || c > 0x7e) break;
        out[i] = c;
        out[i + 1] = '\0';
    }
}

void TraceLoaderRoutine(const char* name, std::atomic<uint32_t>& calls, X86Context& ctx) {
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);
    if (sample >= 64 && sample % 16 != 0) return;

    uint32_t return_address = GuestWord(ctx.esp);
    uint32_t stack0 = GuestWord(ctx.esp + 4);
    uint32_t stack1 = GuestWord(ctx.esp + 8);
    uint32_t stack2 = GuestWord(ctx.esp + 12);
    LOGI("UC2 %s[%u] esp=%08X ret=%08X args=%08X/%08X/%08X eax=%08X ebx=%08X ecx=%08X edx=%08X esi=%08X edi=%08X",
         name, sample, ctx.esp, return_address, stack0, stack1, stack2,
         ctx.eax, ctx.ebx, ctx.ecx, ctx.edx, ctx.esi, ctx.edi);
}

}  // namespace

void UC2_TraceLoaderLoop(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    TraceLoaderRoutine("loader loop", calls, ctx);
}

void UC2_TracePackageWorker(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    TraceLoaderRoutine("package worker", calls, ctx);
}

void UC2_TracePackageWorkerResult(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);
    if (sample >= 64 && sample % 128 != 0) return;

    // This is the instruction after FUN_00028410 returns and before its caller
    // tests [ESP+0x18] to decide whether to invoke FUN_00028540.
    LOGI("UC2 package worker result[%u] esp=%08X ret=%08X local14=%08X local18=%08X local1c=%08X object=%08X",
         sample, ctx.esp, GuestWord(ctx.esp), GuestWord(ctx.esp + 0x14),
         GuestWord(ctx.esp + 0x18), GuestWord(ctx.esp + 0x1C), ctx.edi);
}

void UC2_TracePackageProcess(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    TraceLoaderRoutine("package process", calls, ctx);
}

void UC2_TracePackageProcessResult(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    TraceLoaderRoutine("package process return", calls, ctx);
}

void UC2_TraceCacheLookup(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    TraceLoaderRoutine("cache lookup", calls, ctx);
}

void UC2_TraceCacheCopy(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    TraceLoaderRoutine("cache copy", calls, ctx);
}

void UC2_TraceLoaderMethod(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = 0;
    if (!ShouldTrace(calls, sample)) return;

    uint32_t object = ctx.edi;
    // At 0x283CC ECX is the interface object and EAX is its vtable pointer.
    // The interface's first word is itself the vtable; reading +0x14 from
    // ECX (or object+8) reports an unrelated field, not the call target.
    uint32_t interface = ctx.ecx;
    uint32_t vtable = ctx.eax;
    uint32_t method = vtable <= 0xFFFFFFEB ? GuestWord(vtable + 0x14) : kUnreadable;
    uint32_t event_handle = interface <= 0xFFFFFFFB ? GuestWord(interface + 4) : kUnreadable;
    uint32_t state10 = object <= 0xFFFFFFEF ? GuestWord(object + 0x10) : kUnreadable;
    uint32_t state14 = object <= 0xFFFFFFEB ? GuestWord(object + 0x14) : kUnreadable;
    LOGI("UC2 loader method before[%u] object=%08X interface=%08X event=%08X vtable=%08X method=%08X state10=%08X state14=%08X",
         sample, object, interface, event_handle, vtable, method, state10, state14);
}

void UC2_TraceLoaderMethodResult(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> returns{0};
    uint32_t sample = 0;
    if (!ShouldTrace(returns, sample)) return;

    uint32_t object = ctx.edi;
    uint32_t state10 = object <= 0xFFFFFFEF ? GuestWord(object + 0x10) : kUnreadable;
    uint32_t state14 = object <= 0xFFFFFFEB ? GuestWord(object + 0x14) : kUnreadable;
    LOGI("UC2 loader method after[%u] object=%08X eax=%08X state10=%08X state14=%08X",
         sample, object, ctx.eax, state10, state14);
}

void UC2_TracePackageCacheResult(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    uint32_t call = calls.fetch_add(1, std::memory_order_relaxed);

    char path[256];
    GuestString(ctx.ebx, base, path);
    LOGI("UC2 package cache check[%u] result=%u path=%s ebx=%08X", call, ctx.eax, path, ctx.ebx);
}

void UC2_TracePackageQueueInsert(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    uint32_t call = calls.fetch_add(1, std::memory_order_relaxed);

    // At 0x28A61 the game appends the string at [ESP+0x1C] to its pending
    // package list. ESI is the prior list count and EBX is the string length;
    // neither register points to a string at this instruction.
    uint32_t path_slot = ctx.esp <= 0xFFFFFFE3 ? ctx.esp + 0x1C : kUnreadable;
    uint32_t path_ptr = path_slot == kUnreadable ? kUnreadable : GuestWord(path_slot);
    char path[256];
    if (path_ptr == kUnreadable) path[0] = '\0';
    else GuestString(path_ptr, base, path);
    LOGI("UC2 package queue insert[%u] count=%u length=%u path=%s path_ptr=%08X",
         call, ctx.esi, ctx.ebx, path, path_ptr);
}

void UC2_TracePackageDispatchGate(X86Context& ctx, uint8_t* base) {
    (void)base;
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);

    // FUN_00028540 checks [ESP+0x14] at 0x289E4 before deciding whether to
    // process the staged package/cache operation or skip to its cleanup path.
    // The Xemu trace reaches the async map open after this loader pass, while
    // the recomp trace returns to its event wait. Capture the exact branch
    // value and surrounding guest state to locate that divergence.
    uint32_t gate = GuestWord(ctx.esp + 0x14);
    uint32_t stack18 = GuestWord(ctx.esp + 0x18);
    uint32_t stack1c = GuestWord(ctx.esp + 0x1C);
    uint32_t list_count = GuestWord(ctx.ebp + 0x24);
    uint32_t list_capacity = GuestWord(ctx.ebp + 0x28);
    char path[256];
    if (stack1c == kUnreadable) path[0] = '\0';
    else GuestString(stack1c, base, path);
    LOGI("UC2 package dispatch gate[%u] esp=%08X ebp=%08X value=%08X stack18=%08X stack1c=%08X path=%s list=%08X/%08X eax=%08X ebx=%08X esi=%08X edi=%08X",
         sample, ctx.esp, ctx.ebp, gate, stack18, stack1c, path, list_count,
         list_capacity, ctx.eax, ctx.ebx, ctx.esi, ctx.edi);
}

void UC2_TracePackageDispatchTaken(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);
    uint32_t path_ptr = GuestWord(ctx.esp + 0x1C);
    char path[256];
    if (path_ptr == kUnreadable) path[0] = '\0';
    else GuestString(path_ptr, base, path);
    LOGI("UC2 package dispatch selected[%u] esp=%08X ebp=%08X path_ptr=%08X path=%s list=%08X/%08X eax=%08X ebx=%08X esi=%08X edi=%08X",
         sample, ctx.esp, ctx.ebp, path_ptr, path, GuestWord(ctx.ebp + 0x24),
         GuestWord(ctx.ebp + 0x28), ctx.eax, ctx.ebx, ctx.esi, ctx.edi);
}

void UC2_TracePackageDispatchComplete(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);
    uint32_t path_ptr = GuestWord(ctx.esp + 0x1C);
    char path[256];
    if (path_ptr == kUnreadable) path[0] = '\0';
    else GuestString(path_ptr, base, path);
    LOGI("UC2 package dispatch complete[%u] esp=%08X ebp=%08X path_ptr=%08X path=%s list=%08X/%08X eax=%08X ebx=%08X esi=%08X edi=%08X",
         sample, ctx.esp, ctx.ebp, path_ptr, path, GuestWord(ctx.ebp + 0x24),
         GuestWord(ctx.ebp + 0x28), ctx.eax, ctx.ebx, ctx.esi, ctx.edi);
}

void UC2_TracePackageHandoff(X86Context& ctx, uint8_t* base) {
    uint32_t object = ctx.edi;
    uint32_t vtable = ctx.eax;
    uint32_t method = vtable <= 0xFFFFFFFB ? GuestWord(vtable + 4) : kUnreadable;
    uint32_t count = GuestWord(ctx.ebp + 0x24);
    uint32_t entries = GuestWord(ctx.ebp + 0x20);
    uint32_t path_ptr = ctx.esp <= 0xFFFFFFE3 ? GuestWord(ctx.esp + 0x1C) : kUnreadable;
    char path[256];
    if (path_ptr == kUnreadable) path[0] = '\0';
    else GuestString(path_ptr, base, path);
    LOGI("UC2 package handoff before object=%08X vtable=%08X method=%08X path=%s count=%u entries=%08X args=%08X/%08X",
         object, vtable, method, path, count, entries, GuestWord(ctx.esp + 4),
         GuestWord(ctx.esp + 8));
}

void UC2_TracePackageHandoffResult(X86Context& ctx, uint8_t* base) {
    (void)base;
    LOGI("UC2 package handoff after object=%08X result=%08X count=%u entries=%08X esi=%08X edi=%08X",
         ctx.edi, ctx.eax, GuestWord(ctx.ebp + 0x24), GuestWord(ctx.ebp + 0x20),
         ctx.esi, ctx.edi);
}

void UC2_TracePackageFinalize(X86Context& ctx, uint8_t* base) {
    (void)base;
    uint32_t object = ctx.edi;
    uint32_t vtable = ctx.eax;
    uint32_t method = vtable <= 0xFFFFFFF7 ? GuestWord(vtable + 8) : kUnreadable;
    LOGI("UC2 package finalize before object=%08X vtable=%08X method=%08X count=%u entries=%08X",
         object, vtable, method, GuestWord(ctx.ebp + 0x24), GuestWord(ctx.ebp + 0x20));
}

void UC2_TracePackageFinalizeResult(X86Context& ctx, uint8_t* base) {
    (void)base;
    LOGI("UC2 package finalize after object=%08X result=%08X count=%u entries=%08X esi=%08X edi=%08X",
         ctx.edi, ctx.eax, GuestWord(ctx.ebp + 0x24), GuestWord(ctx.ebp + 0x20),
         ctx.esi, ctx.edi);
}

void UC2_TracePackageOpenSource(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);
    char path[256];
    GuestString(ctx.eax, base, path);
    LOGI("UC2 package open source[%u] pc=00028937 path_ptr=%08X path=%s args=%08X/%08X/%08X/%08X/%08X/%08X/%08X",
         sample, ctx.eax, path, GuestWord(ctx.esp), GuestWord(ctx.esp + 4),
         GuestWord(ctx.esp + 8), GuestWord(ctx.esp + 12),
         GuestWord(ctx.esp + 16), GuestWord(ctx.esp + 20),
         GuestWord(ctx.esp + 24));
}

void UC2_TracePackageOpenDestination(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);
    char path[256];
    GuestString(ctx.eax, base, path);
    LOGI("UC2 package open destination[%u] pc=00028980 path_ptr=%08X path=%s args=%08X/%08X/%08X/%08X/%08X/%08X/%08X",
         sample, ctx.eax, path, GuestWord(ctx.esp), GuestWord(ctx.esp + 4),
         GuestWord(ctx.esp + 8), GuestWord(ctx.esp + 12),
         GuestWord(ctx.esp + 16), GuestWord(ctx.esp + 20),
         GuestWord(ctx.esp + 24));
}

namespace {

void TraceResourceEntry(const char* name, std::atomic<uint32_t>& calls,
                        X86Context& ctx, uint8_t* base) {
    uint32_t sample = calls.fetch_add(1, std::memory_order_relaxed);
    // These routines enumerate package objects rather than running each
    // frame. Retain enough startup context and then periodic samples so a
    // later level transition remains visible in long interactive runs.
    if (sample >= 128 && sample % 128 != 0) return;

    uint32_t arg0 = GuestWord(ctx.esp + 4);
    uint32_t arg1 = GuestWord(ctx.esp + 8);
    uint32_t arg2 = GuestWord(ctx.esp + 12);
    uint32_t arg3 = GuestWord(ctx.esp + 16);
    char string0[256];
    char string1[256];
    GuestString(arg0, base, string0);
    GuestString(arg1, base, string1);
    LOGI("UC2 %s[%u] caller=%08X esp=%08X args=%08X/%08X/%08X/%08X strings='%s'/'%s' eax=%08X ebx=%08X ecx=%08X edx=%08X esi=%08X edi=%08X",
         name, sample, GuestWord(ctx.esp), ctx.esp, arg0, arg1, arg2, arg3,
         string0, string1, ctx.eax, ctx.ebx, ctx.ecx, ctx.edx, ctx.esi,
         ctx.edi);
}

}  // namespace

void UC2_TraceResourceEnumeration(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    TraceResourceEntry("resource enumeration", calls, ctx, base);
}

void UC2_TraceResourceObjectCreate(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    TraceResourceEntry("resource object create", calls, ctx, base);
}
