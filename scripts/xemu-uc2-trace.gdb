set pagination off
set confirm off
set architecture i386
target remote localhost:1234

# The match-load worker is UC2's routine at 0x2E780. Its context is passed
# on the stack; sub_2EA50 polls two handles in that context and processes a
# completion only after the wait leaves STATUS_TIMEOUT (0x102).
break *0x0002E780
commands
  silent
  set $uc2_worker_ctx = *(unsigned int*)($esp+4)
  printf "UC2 match worker start ctx=%08x handles=%08x/%08x flags=%08x/%08x\n", $uc2_worker_ctx, *(unsigned int*)($uc2_worker_ctx+0x0c), *(unsigned int*)($uc2_worker_ctx+0x10), *(unsigned int*)($uc2_worker_ctx+0xb4), *(unsigned int*)($uc2_worker_ctx+0xb8)
  x/7wx $uc2_worker_ctx+0xbc
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
  set $uc2_read_iosb = *(unsigned int*)($esp+16)
  set $uc2_offset_ptr = *(unsigned int*)($esp+28)
  printf "UC2 NtReadFile pc=%08x handle=%08x event=%08x iosb=%08x buffer=%08x len=%u offset_ptr=%08x\n", $eip, $uc2_read_handle, $uc2_read_event, $uc2_read_iosb, *(unsigned int*)($esp+20), *(unsigned int*)($esp+24), $uc2_offset_ptr
  if $uc2_offset_ptr != 0
    printf "  explicit byte offset (low, high): "
    x/2wx $uc2_offset_ptr
  else
    printf "  byte offset is null; use the file object's current position\n"
  end
end

define uc2-log-read-result
  # At the caller return address, the original NtReadFile arguments are
  # still on the stack. Recover IOSB from this thread's own stack rather than
  # a global GDB convenience variable that another guest thread can replace.
  set $uc2_result_iosb = *(unsigned int*)($esp+16)
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
