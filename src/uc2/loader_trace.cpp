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
    return sample < 32 || (sample % 128) == 0;
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

}  // namespace

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
    uint32_t state10 = object <= 0xFFFFFFEF ? GuestWord(object + 0x10) : kUnreadable;
    uint32_t state14 = object <= 0xFFFFFFEB ? GuestWord(object + 0x14) : kUnreadable;
    LOGI("UC2 loader method before[%u] object=%08X interface=%08X vtable=%08X method=%08X state10=%08X state14=%08X",
         sample, object, interface, vtable, method, state10, state14);
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
    uint32_t sample = 0;
    if (!ShouldTrace(calls, sample)) return;

    char path[256];
    GuestString(ctx.ebx, base, path);
    LOGI("UC2 package cache check[%u] result=%u path=%s ebx=%08X", sample, ctx.eax, path, ctx.ebx);
}

void UC2_TracePackageQueueInsert(X86Context& ctx, uint8_t* base) {
    static std::atomic<uint32_t> calls{0};
    uint32_t sample = 0;
    if (!ShouldTrace(calls, sample)) return;

    char esi[256];
    char ebx[256];
    GuestString(ctx.esi, base, esi);
    GuestString(ctx.ebx, base, ebx);
    LOGI("UC2 package queue insert[%u] esi=%08X '%s' ebx=%08X '%s' eax=%08X",
         sample, ctx.esi, esi, ctx.ebx, ebx, ctx.eax);
}
