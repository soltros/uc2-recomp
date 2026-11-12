set pagination off
set confirm off
set architecture i386
target remote localhost:1234

# Capture the raw six-argument wait call at UC2's worker polling site. The
# recomp logs the same values before resolving its emulated handles.
set $uc2_wait_count = 0
set $uc2_main_event_handle = 0
set $uc2_single_wait_count = 0
set $uc2_worker_h0_0 = 0
set $uc2_worker_h1_0 = 0
set $uc2_worker_h0_1 = 0
set $uc2_worker_h1_1 = 0
set $uc2_worker_h0_2 = 0
set $uc2_worker_h1_2 = 0
set $uc2_worker_h0_3 = 0
set $uc2_worker_h1_3 = 0
break *0x002667DE
commands
  silent
  set $uc2_wait_count = $uc2_wait_count + 1
  if $uc2_wait_count <= 16 || $uc2_wait_count % 64 == 0
    set $uc2_wait_n = *(unsigned int*)$esp
    set $uc2_wait_handles = *(unsigned int*)($esp+4)
    printf "UC2 NtWaitForMultipleObjectsEx args=%08x/%08x/%08x/%08x/%08x/%08x", $uc2_wait_n, $uc2_wait_handles, *(unsigned int*)($esp+8), *(unsigned int*)($esp+12), *(unsigned int*)($esp+16), *(unsigned int*)($esp+20)
    if $uc2_wait_n == 2 && $uc2_wait_handles != 0
      printf " handles=%08x/%08x", *(unsigned int*)$uc2_wait_handles, *(unsigned int*)($uc2_wait_handles+4)
    end
    printf "\n"
  end
  continue
end

# Trace the game's single-object wait wrapper as well as the XPP worker. The
# long-lived load transition waits here on its main event (or on a null,
# infinite timeout while waiting on that event).
break *0x00266760
commands
  silent
  set $uc2_single_wait_count = $uc2_single_wait_count + 1
  set $uc2_single_wait_handle = *(unsigned int*)$esp
  set $uc2_single_wait_alertable = *(unsigned int*)($esp+8)
  set $uc2_single_wait_timeout_ptr = *(unsigned int*)($esp+12)
  if $uc2_single_wait_timeout_ptr == 0
    set $uc2_main_event_handle = $uc2_single_wait_handle
    printf "UC2 infinite NtWaitForSingleObjectEx handle=%08x alertable=%u timeout=null\n", $uc2_single_wait_handle, $uc2_single_wait_alertable
  else
    set $uc2_single_wait_timeout = *(long long*)$uc2_single_wait_timeout_ptr
    if $uc2_single_wait_timeout == 0x7fffffffffffffff
      set $uc2_main_event_handle = $uc2_single_wait_handle
      printf "UC2 infinite NtWaitForSingleObjectEx handle=%08x alertable=%u timeout=%lld\n", $uc2_single_wait_handle, $uc2_single_wait_alertable, $uc2_single_wait_timeout
    else
      if $uc2_single_wait_count <= 8 || $uc2_single_wait_count % 128 == 0
        printf "UC2 NtWaitForSingleObjectEx handle=%08x alertable=%u timeout=%lld\n", $uc2_single_wait_handle, $uc2_single_wait_alertable, $uc2_single_wait_timeout
      end
    end
  end
  continue
end

break *0x00266766
commands
  silent
  if $uc2_main_event_handle != 0 && *(unsigned int*)($ebp+8) == $uc2_main_event_handle
    printf "UC2 main single wait return handle=%08x status=%08x\n", *(unsigned int*)($ebp+8), $eax
  end
  continue
end

# The match-load worker is UC2's routine at 0x2E780. Its context is passed
# on the stack; sub_2EA50 polls two handles in that context and processes a
# completion only after the wait leaves STATUS_TIMEOUT (0x102).
break *0x0002E780
commands
  silent
  set $uc2_worker_ctx = *(unsigned int*)($esp+4)
  set $uc2_worker_h0_3 = $uc2_worker_h0_2
  set $uc2_worker_h1_3 = $uc2_worker_h1_2
  set $uc2_worker_h0_2 = $uc2_worker_h0_1
  set $uc2_worker_h1_2 = $uc2_worker_h1_1
  set $uc2_worker_h0_1 = $uc2_worker_h0_0
  set $uc2_worker_h1_1 = $uc2_worker_h1_0
  set $uc2_worker_h0_0 = *(unsigned int*)($uc2_worker_ctx+0x0c)
  set $uc2_worker_h1_0 = *(unsigned int*)($uc2_worker_ctx+0x10)
  printf "UC2 match worker start ctx=%08x handles=%08x/%08x flags=%08x/%08x\n", $uc2_worker_ctx, *(unsigned int*)($uc2_worker_ctx+0x0c), *(unsigned int*)($uc2_worker_ctx+0x10), *(unsigned int*)($uc2_worker_ctx+0xb4), *(unsigned int*)($uc2_worker_ctx+0xb8)
  x/7wx $uc2_worker_ctx+0xbc
  continue
end

# The UC2 wrapper stores NtCreateEvent's output handle in its fourth stack
# slot. Record successful and named-object reuse results so worker handles can
# be classified against file opens and event creation.
break *0x002665C2
commands
  silent
  printf "UC2 NtCreateEvent return status=%08x handle=%08x caller=%08x\n", $eax, *(unsigned int*)($ebp+0x14), *(unsigned int*)($ebp+4)
  continue
end

# Event wrappers reveal who signals or resets either completion handle. The
# worker-start breakpoint above records the pair used by the active worker.
break *0x002665EC
commands
  silent
  set $uc2_event_handle = *(unsigned int*)($esp+4)
  if $uc2_event_handle != 0 && ($uc2_event_handle == $uc2_main_event_handle || $uc2_event_handle == $uc2_worker_h0_0 || $uc2_event_handle == $uc2_worker_h1_0 || $uc2_event_handle == $uc2_worker_h0_1 || $uc2_event_handle == $uc2_worker_h1_1 || $uc2_event_handle == $uc2_worker_h0_2 || $uc2_event_handle == $uc2_worker_h1_2 || $uc2_event_handle == $uc2_worker_h0_3 || $uc2_event_handle == $uc2_worker_h1_3)
    printf "UC2 NtSetEvent handle=%08x caller=%08x\n", $uc2_event_handle, *(unsigned int*)$esp
  end
  continue
end

break *0x002665F8
commands
  silent
  # The kernel stdcall has popped its return address and both arguments, so
  # ESP is back at the wrapper's entry frame: return PC at [ESP], handle at
  # [ESP+4].
  set $uc2_event_handle = *(unsigned int*)($esp+4)
  if $uc2_event_handle != 0 && ($uc2_event_handle == $uc2_main_event_handle || $uc2_event_handle == $uc2_worker_h0_0 || $uc2_event_handle == $uc2_worker_h1_0 || $uc2_event_handle == $uc2_worker_h0_1 || $uc2_event_handle == $uc2_worker_h1_1 || $uc2_event_handle == $uc2_worker_h0_2 || $uc2_event_handle == $uc2_worker_h1_2 || $uc2_event_handle == $uc2_worker_h0_3 || $uc2_event_handle == $uc2_worker_h1_3)
    printf "UC2 NtSetEvent return handle=%08x status=%08x\n", $uc2_event_handle, $eax
  end
  continue
end

break *0x0026660C
commands
  silent
  set $uc2_event_handle = *(unsigned int*)($esp+4)
  if $uc2_event_handle != 0 && ($uc2_event_handle == $uc2_main_event_handle || $uc2_event_handle == $uc2_worker_h0_0 || $uc2_event_handle == $uc2_worker_h1_0 || $uc2_event_handle == $uc2_worker_h0_1 || $uc2_event_handle == $uc2_worker_h1_1 || $uc2_event_handle == $uc2_worker_h0_2 || $uc2_event_handle == $uc2_worker_h1_2 || $uc2_event_handle == $uc2_worker_h0_3 || $uc2_event_handle == $uc2_worker_h1_3)
    printf "UC2 NtClearEvent handle=%08x caller=%08x\n", $uc2_event_handle, *(unsigned int*)$esp
  end
  continue
end

break *0x00266616
commands
  silent
  # NtClearEvent's stdcall has popped its return address and handle; ESP is
  # back at the wrapper entry, with the handle at [ESP+4].
  set $uc2_event_handle = *(unsigned int*)($esp+4)
  if $uc2_event_handle != 0 && ($uc2_event_handle == $uc2_main_event_handle || $uc2_event_handle == $uc2_worker_h0_0 || $uc2_event_handle == $uc2_worker_h1_0 || $uc2_event_handle == $uc2_worker_h0_1 || $uc2_event_handle == $uc2_worker_h1_1 || $uc2_event_handle == $uc2_worker_h0_2 || $uc2_event_handle == $uc2_worker_h1_2 || $uc2_event_handle == $uc2_worker_h0_3 || $uc2_event_handle == $uc2_worker_h1_3)
    printf "UC2 NtClearEvent return handle=%08x status=%08x\n", $uc2_event_handle, $eax
  end
  continue
end

break *0x0026662A
commands
  silent
  set $uc2_event_handle = *(unsigned int*)($esp+4)
  if $uc2_event_handle != 0 && ($uc2_event_handle == $uc2_main_event_handle || $uc2_event_handle == $uc2_worker_h0_0 || $uc2_event_handle == $uc2_worker_h1_0 || $uc2_event_handle == $uc2_worker_h0_1 || $uc2_event_handle == $uc2_worker_h1_1 || $uc2_event_handle == $uc2_worker_h0_2 || $uc2_event_handle == $uc2_worker_h1_2 || $uc2_event_handle == $uc2_worker_h0_3 || $uc2_event_handle == $uc2_worker_h1_3)
    printf "UC2 NtPulseEvent handle=%08x caller=%08x\n", $uc2_event_handle, *(unsigned int*)$esp
  end
  continue
end

break *0x00266636
commands
  silent
  # As with NtSetEvent, the kernel stdcall has restored the wrapper-entry
  # stack; the event handle is at [ESP+4].
  set $uc2_event_handle = *(unsigned int*)($esp+4)
  if $uc2_event_handle != 0 && ($uc2_event_handle == $uc2_worker_h0_0 || $uc2_event_handle == $uc2_worker_h1_0 || $uc2_event_handle == $uc2_worker_h0_1 || $uc2_event_handle == $uc2_worker_h1_1 || $uc2_event_handle == $uc2_worker_h0_2 || $uc2_event_handle == $uc2_worker_h1_2 || $uc2_event_handle == $uc2_worker_h0_3 || $uc2_event_handle == $uc2_worker_h1_3)
    printf "UC2 NtPulseEvent return handle=%08x status=%08x\n", $uc2_event_handle, $eax
  end
  continue
end

# XPP converts asynchronous event handles to dispatcher-object pointers before
# it calls KeSetEvent. At this return site, ESI is the XPP state record and
# stores both the original handle (+4) and ObReferenceObjectByHandle output
# pointer (+0x0c).
break *0x0039652F
commands
  silent
  printf "UC2 XPP ObReferenceObjectByHandle handle=%08x status=%08x object=%08x\n", *(unsigned int*)($esi+4), $eax, *(unsigned int*)($esi+0x0c)
  continue
end

# XPP's async completion paths signal dispatcher objects through KeSetEvent,
# not NtSetEvent. Capture each XPP call site before entering the kernel thunk;
# its three stack arguments are object, increment, and wait.
define uc2-log-xpp-ke-set
  printf "UC2 XPP KeSetEvent site=%08x object=%08x increment=%08x wait=%08x\n", $eip, *(unsigned int*)$esp, *(unsigned int*)($esp+4), *(unsigned int*)($esp+8)
end

break *0x00395E86
commands
  silent
  uc2-log-xpp-ke-set
  continue
end

break *0x00396067
commands
  silent
  uc2-log-xpp-ke-set
  continue
end

break *0x00396BCC
commands
  silent
  uc2-log-xpp-ke-set
  continue
end

break *0x0039B90F
commands
  silent
  uc2-log-xpp-ke-set
  continue
end

break *0x0039BE52
commands
  silent
  uc2-log-xpp-ke-set
  continue
end

# XPP's device initialization helper creates virtual device objects here. The
# return status controls whether it initializes that device's extension, so
# capture both the six arguments and status during the reference run. This
# shows whether this path is active while loading Aqueduct.
break *0x00395879
commands
  silent
  printf "UC2 IoCreateDevice args=%08x/%08x/%08x/%08x/%08x/%08x\n", *(unsigned int*)$esp, *(unsigned int*)($esp+4), *(unsigned int*)($esp+8), *(unsigned int*)($esp+12), *(unsigned int*)($esp+16), *(unsigned int*)($esp+20)
  continue
end

break *0x0039587F
commands
  silent
  if ($eax & 0x80000000) == 0
    printf "UC2 IoCreateDevice return status=%08x device=%08x\n", $eax, *(unsigned int*)($ebp-4)
  else
    printf "UC2 IoCreateDevice return status=%08x\n", $eax
  end
  continue
end

# These XPP packet dispatch sites include the device object and IRP so an
# active request can be correlated with the same device and completion path
# in the recomp.
break *0x0039C187
commands
  silent
  printf "UC2 IoStartPacket device=%08x irp=%08x key=%08x\n", *(unsigned int*)$esp, *(unsigned int*)($esp+4), *(unsigned int*)($esp+8)
  continue
end

break *0x0039C18D
commands
  silent
  printf "UC2 IoStartPacket return status=%08x device=%08x\n", $eax, $edi
  continue
end

break *0x0039C1D5
commands
  silent
  printf "UC2 IoStartNextPacket device=%08x\n", *(unsigned int*)$esp
  continue
end

break *0x0039C1DB
commands
  silent
  printf "UC2 IoStartNextPacket return status=%08x device=%08x\n", $eax, *(unsigned int*)$esi
  continue
end

# At this point EAX is the result of the worker's wait-for-multiple-objects.
# Ignore ordinary timeout polls and stop only when Xemu reports a signal or
# another wait result, then log and continue automatically.
break *0x0002EAA8 if $eax != 0x102
commands
  silent
  printf "UC2 match worker wait result=%08x ctx=%08x ebx_gate=%08x previous_result=%08x handles=%08x/%08x flags=%08x/%08x\n", $eax, $esi, $ebx, $edi, *(unsigned int*)($esi+0x0c), *(unsigned int*)($esi+0x10), *(unsigned int*)($esi+0xb4), *(unsigned int*)($esi+0xb8)
  continue
end

# At this call site the worker has tested EBX and is about to run the
# completion handler. Logging entry distinguishes a signaled wait that the
# worker ignores from one it actually consumes.
break *0x0002EAAE
commands
  silent
  printf "UC2 match worker completion call ctx=%08x wait_result=%08x handles=%08x/%08x flags=%08x/%08x\n", $esi, $edi, *(unsigned int*)($esi+0x0c), *(unsigned int*)($esi+0x10), *(unsigned int*)($esi+0xb4), *(unsigned int*)($esi+0xb8)
  continue
end

# This point follows sub_2E310, which the worker calls only after a
# non-timeout wait result. Record zero as well as nonzero returns so the
# reference trace shows whether a wake was consumed or ignored.
break *0x0002EAB3
commands
  silent
  printf "UC2 match worker sub_2E310 return=%08x ctx=%08x handles=%08x/%08x flags=%08x/%08x\n", $eax, $esi, *(unsigned int*)($esi+0x0c), *(unsigned int*)($esi+0x10), *(unsigned int*)($esi+0xb4), *(unsigned int*)($esi+0xb8)
  continue
end

define uc2-log-read
  set $uc2_read_handle = *(unsigned int*)$esp
  set $uc2_read_event = *(unsigned int*)($esp+4)
  set $uc2_read_apc = *(unsigned int*)($esp+8)
  set $uc2_read_apc_ctx = *(unsigned int*)($esp+12)
  set $uc2_read_iosb = *(unsigned int*)($esp+16)
  set $uc2_offset_ptr = *(unsigned int*)($esp+28)
  printf "UC2 NtReadFile pc=%08x handle=%08x event=%08x apc=%08x apc_ctx=%08x iosb=%08x buffer=%08x len=%u offset_ptr=%08x\n", $eip, $uc2_read_handle, $uc2_read_event, $uc2_read_apc, $uc2_read_apc_ctx, $uc2_read_iosb, *(unsigned int*)($esp+20), *(unsigned int*)($esp+24), $uc2_offset_ptr
  if $uc2_offset_ptr != 0
    printf "  explicit byte offset (low, high): "
    x/2wx $uc2_offset_ptr
  else
    printf "  byte offset is null; use the file object's current position\n"
  end
end

define uc2-log-read-result
  # NtReadFile is stdcall with eight stack arguments. Its return has popped
  # the return address and all 32 argument bytes, so the fifth argument
  # (IOSB, originally at entry ESP+20) is now at caller ESP-16.
  # Recover it from this thread's stack rather than a global convenience
  # variable that another guest thread can replace.
  set $uc2_result_iosb = *(unsigned int*)($esp-16)
  printf "UC2 NtReadFile return pc=%08x status=%08x iosb=%08x\n", $eip, $eax, $uc2_result_iosb
  if $uc2_result_iosb != 0
    printf "  I/O status block (status, information): "
    x/2wx $uc2_result_iosb
  end
end

# The shared file-open wrapper loads its path argument into EDI immediately
# before converting it to a counted string. Capture it here, before the
# wrapper reuses its stack arguments to build OBJECT_ATTRIBUTES. The kernel
# call returns at 0x2622AF, where EBP-4 contains the output handle.
break *0x002621E7
commands
  silent
  printf "UC2 NtCreateFile path input pc=%08x ptr=%08x\n", $eip, $edi
  if $edi != 0
    x/s $edi
  end
  continue
end

# Capture CreateOptions before the common file-open wrapper's nine-argument
# NtCreateFile call. The output handle is at [ESP], and CreateOptions is the
# ninth stack argument at [ESP+32]. This lets the Xemu trace classify handles
# using FILE_SYNCHRONOUS_IO_ALERT/NONALERT, matching the recomp HLE trace.
break *0x002622A9
commands
  silent
  set $uc2_open_options = *(unsigned int*)($esp+32)
  set $uc2_open_disposition = *(unsigned int*)($esp+28)
  set $uc2_open_path = *(unsigned int*)($ebp-8)
  printf "UC2 NtCreateFile args path_ptr=%08x disposition=%08x options=%08x\n", $uc2_open_path, $uc2_open_disposition, $uc2_open_options
  if $uc2_open_path != 0
    x/s $uc2_open_path
  end
  continue
end

break *0x002622AF
commands
  silent
  # The wrapper repurposes [ebp+8] as a trailing-separator flag. The
  # RtlInitAnsiString local at ebp-0xC retains its Buffer pointer at ebp-8.
  set $uc2_return_path = *(unsigned int*)($ebp-8)
  printf "UC2 NtCreateFile return pc=%08x status=%08x handle=%08x path_ptr=%08x\n", $eip, $eax, *(unsigned int*)($ebp-4), $uc2_return_path
  if $uc2_return_path != 0
    x/s $uc2_return_path
  end
  continue
end

# Log closes so the trace can distinguish an event handle from a later file
# handle that reused the same numeric value.
break *0x0026640E
commands
  silent
  printf "UC2 NtClose handle=%08x caller=%08x\n", *(unsigned int*)($esp+4), *(unsigned int*)$esp
  continue
end

# All direct NtReadFile import call sites found in UC2's XBE disassembly.
break *0x002624AB
commands
  silent
  uc2-log-read
  continue
end
break *0x002624B1
commands
  silent
  uc2-log-read-result
  continue
end

break *0x00262662
commands
  silent
  uc2-log-read
  continue
end
break *0x00262668
commands
  silent
  uc2-log-read-result
  continue
end

break *0x002626A7
commands
  silent
  uc2-log-read
  continue
end
break *0x002626AD
commands
  silent
  uc2-log-read-result
  continue
end

# This caller waits on the file handle when NtReadFile returns STATUS_PENDING.
# The IOSB is a local at EBP-8; inspect it after the wait to record the actual
# completion status and byte count rather than only the initial pending result.
break *0x002626BF
commands
  silent
  printf "UC2 NtReadFile completion wait return pc=%08x handle=%08x status=%08x iosb=%08x\n", $eip, *(unsigned int*)($ebp+8), $eax, $ebp-8
  printf "  completed I/O status block (status, information): "
  x/2wx $ebp-8
  continue
end

break *0x00262C22
commands
  silent
  uc2-log-read
  continue
end
break *0x00262C28
commands
  silent
  uc2-log-read-result
  continue
end

break *0x0026804A
commands
  silent
  uc2-log-read
  continue
end
break *0x00268050
commands
  silent
  uc2-log-read-result
  continue
end

break *0x00322B44
commands
  silent
  uc2-log-read
  continue
end
break *0x00322B4A
commands
  silent
  uc2-log-read-result
  continue
end

break *0x0038969B
commands
  silent
  uc2-log-read
  continue
end
break *0x003896A1
commands
  silent
  uc2-log-read-result
  continue
end

continue
