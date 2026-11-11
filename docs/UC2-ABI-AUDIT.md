# UC2 Xbox calling-convention audit

This audit covers the custom argument-location overrides in `config/uc2.toml`. The rest of the executable and all imported XDK functions are outside its scope.

## Method and limits

XboxXBERecomp's `xbe_symbols` scanner was run against the local `default.xbe` using the XDK 5849 signatures. It identified 13 LTCG D3D entry points whose register-use shape or callee stack-pop size differs from the reference library. The generated `x86_recomp.*.cpp` files preserve the title's call-site register moves and stack pushes, which are the primary evidence for UC2's argument locations. The corresponding runtime HLE definitions show how those mapped arguments are consumed.

The scanner reports registers read before being overwritten and the callee's stack-pop size. It does not identify API argument meaning or ordering. Therefore, matching register sets alone is not treated as a complete ABI proof. Runtime behavior currently verifies device creation and sustained D3D execution, but has not yet verified visible gameplay.

## Overrides

| Function | Mapping in API argument order | Evidence and status |
|---|---|---|
| `CDevice_KickOff` | `edx` | At `0x003868F4`, the guest moves the device pointer from ESI to EDX before the call. The runtime HLE ignores the argument. Location verified; semantic use is not exercised by the HLE. |
| `D3D_InitializeDevicePushState` | `esi` | At `0x0038B0B1`, the caller moves the device pointer from EBP to ESI before calling `0x003867A0`; the callee dereferences the device through ESI. Directly verified. |
| `D3DDevice_DrawVertices` | `stack`, `ecx`, `eax` | At `0x00201488`, the caller pushes EBP and calls with ECX and EAX live. EBP is the primitive; the HLE maps the remaining arguments to start and count. The guest draw helper uses EAX as its count and ECX as its start value. Strong call-site and callee evidence. |
| `D3DDevice_SelectVertexShader` | `eax`, `ebx` | At `0x00208148`, EAX carries the selected handle and EBX is zero for the slot. The HLE consumes handle then slot. Directly supported by the call site. |
| `D3DDevice_SetIndices` | `ebx`, `stack` | At `0x00207372`, EBX is live and the caller has pushed the second argument. The guest body stores EBX as the index buffer and the stack argument as the base vertex. Directly supported by the callee. |
| `D3DDevice_SetPixelShaderConstant` | `ecx`, `stack`, `eax` | At `0x0020827B`, ECX is the first register argument, a data pointer is pushed, and EAX carries the final value argument. The HLE consumes register, data, count in that order. Directly supported. |
| `D3DDevice_SetRenderTargetFast` | `stack`, `ebx`, `eax` | At `0x001FEF52`, the caller pushes the first argument and supplies EBX/EAX for the remaining arguments. The guest callee reads the first argument from the stack; the HLE uses the first two arguments as render and depth targets and ignores flags. Locations are supported; the ignored flags value is not runtime-validated. |
| `D3DDevice_SetStreamSource` | `eax`, `ebx`, `stack` | At `0x002081DA`, EAX is the stream number, EBX the vertex buffer, and the caller-pushed value is the stride. The HLE consumes stream, buffer, stride. Directly supported. |
| `D3DDevice_SetTransform` | `eax`, `edx` | At `0x0038AE97`, EAX is the transform index and EDX points to the matrix. Directly supported. |
| `D3DDevice_Swap` | `eax` | The scanner reports EAX as the title's register argument. The HLE ignores the value; its semantic meaning is not runtime-validated. |
| `D3DResource_IsBusy` | `ecx` | At `0x00030170`, the resource pointer is loaded into ECX before the call. The HLE consumes that resource pointer. Directly supported. |
| `D3D_InternalRelease` | `esi` | At `0x003816D6`, the object pointer is loaded into ESI before the call. The HLE consumes the object pointer. Directly supported. |
| `DSOUND_Export_B0098` | `edi`, `stack`, `stack` | At `0x00365147`, the worker calls with EDI and two pushed arguments. The HLE uses the first two as stream and packet data; the final completion argument is not used by this implementation. Locations match the worker call. |
| `D3D_MakeRequestedSpace` | `eax`, `stack` | The scanner reports one EAX register argument and one stack argument. At `0x003839D7`, ECX is pushed; the runtime HLE ignores both values and allocates scratch push space. Location shape is verified; value semantics are not exercised by the HLE. |
| `Direct3D_CreateDevice` | `edx`, `ebx`, `esi`, `eax`, `stack`, `ecx` | The title call at `0x00019591` uses this mixed register/stack form. The fifth argument, presentation parameters, is read from the mapped stack slot by the HLE; the resulting runtime log reports the expected 640x480 parameters. This validates that argument's location and value. The other arguments are not all consumed or runtime-validated by the HLE. |

`stack` means the next stack argument slot in API order; the mapped wrapper accounts for stack cleanup according to the title's callee convention.

## Current conclusion

The mappings above have a mixture of direct call-site evidence and partial runtime evidence. They should remain explicit in the title config because the executable's D3D8 library is LTCG and does not follow the reference library's default convention. A rendered gameplay frame and follow-up run are still needed to validate the draw path end to end.
