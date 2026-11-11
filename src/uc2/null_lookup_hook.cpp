#include "core/log.h"
#include "cpu/x86_ops.h"

// sub_002A6E6E walks the lookup array at [esi + index * 4 + 0x194].
// UC2 can call it with a null optional array; report the same not-found
// HRESULT used by the guest when an array entry is absent.
bool UC2_NullLookupArray(X86Context& ctx, uint8_t* base) {
    (void)base;
    if (ctx.esi != 0 || ctx.eax == 0xF000 || ctx.edi == 0) return false;

    ctx.ebx = 0x80070490;
    LOG_FIRST(4, "UC2: lookup array is null (container %08X index %u); returning STATUS_NOT_FOUND", ctx.edi,
              ctx.eax);
    return true;
}
