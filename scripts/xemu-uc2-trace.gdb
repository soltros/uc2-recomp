set pagination off
set confirm off
set architecture i386
target remote localhost:1234

define uc2-log-read
  printf "UC2 NtReadFile pc=%08x handle=%08x event=%08x iosb=%08x buffer=%08x len=%u offset_ptr=%08x\n", $eip, *(unsigned int*)$esp, *(unsigned int*)($esp+4), *(unsigned int*)($esp+16), *(unsigned int*)($esp+20), *(unsigned int*)($esp+24), *(unsigned int*)($esp+28)
  x/gx *(unsigned int*)($esp+28)
end

define uc2-log-read-result
  printf "UC2 NtReadFile return pc=%08x status=%08x\n", $eip, $eax
end

# UC2's shared file-open wrapper returns from NtCreateFile here. EBP+8 is
# its ANSI path argument; EBP-4 receives the resulting Xbox file handle.
break *0x002622AF
commands
  silent
  set $uc2_path = *(unsigned int*)($ebp+8)
  printf "UC2 NtCreateFile return pc=%08x status=%08x handle=%08x path_ptr=%08x\n", $eip, $eax, *(unsigned int*)($ebp-4), $uc2_path
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
