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
  printf "UC2 match worker wait result=%08x ctx=%08x handles=%08x/%08x flags=%08x/%08x\n", $eax, $esi, *(unsigned int*)($esi+0x0c), *(unsigned int*)($esi+0x10), *(unsigned int*)($esi+0xb4), *(unsigned int*)($esi+0xb8)
  continue
end

# A nonzero result from sub_2E310 indicates that the worker consumed a
# completion condition. Log only that transition, not every polling loop.
break *0x0002EAB3 if $eax != 0
commands
  silent
  printf "UC2 match worker processed completion result=%08x ctx=%08x handles=%08x/%08x flags=%08x/%08x\n", $eax, $esi, *(unsigned int*)($esi+0x0c), *(unsigned int*)($esi+0x10), *(unsigned int*)($esi+0xb4), *(unsigned int*)($esi+0xb8)
  continue
end

define uc2-log-read
  set $uc2_offset_ptr = *(unsigned int*)($esp+28)
  printf "UC2 NtReadFile pc=%08x handle=%08x event=%08x iosb=%08x buffer=%08x len=%u offset_ptr=%08x\n", $eip, *(unsigned int*)$esp, *(unsigned int*)($esp+4), *(unsigned int*)($esp+16), *(unsigned int*)($esp+20), *(unsigned int*)($esp+24), $uc2_offset_ptr
  if $uc2_offset_ptr != 0
    printf "  explicit byte offset (low, high): "
    x/2wx $uc2_offset_ptr
  else
    printf "  byte offset is null; use the file object's current position\n"
  end
end

define uc2-log-read-result
  printf "UC2 NtReadFile return pc=%08x status=%08x\n", $eip, $eax
end

# UC2's shared file-open wrapper returns from NtCreateFile here. It keeps the
# RtlInitAnsiString buffer at EBP-8; EBP+8 is overwritten with a directory
# flag while building OBJECT_ATTRIBUTES. EBP-4 receives the resulting handle.
break *0x002622AF
commands
  silent
  set $uc2_path = *(unsigned int*)($ebp-8)
  printf "UC2 NtCreateFile return pc=%08x status=%08x handle=%08x path_ptr=%08x directory_flag=%08x\n", $eip, $eax, *(unsigned int*)($ebp-4), $uc2_path, *(unsigned int*)($ebp+8)
  if $uc2_path != 0
    x/s $uc2_path
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

continue
