#include <xs1.h>
// Output a block of memory.
// We break the communication down into 3 parts:
// part1: data[size - 1] to *align_down(&data[size])
// part2: *align_down(&data[size]) to *align_up(data[0])
// part3: *align_up(data[0]) to data[0]
.globl local_sout_char_array
.typestring local_sout_char_array, "f{0}(m:chd,&(a(!1:c:uc)),ui)"
.type local_sout_char_array, @function
.cc_top local_sout_char_array.function
#if defined(__XS2A__)
// Call boot ROM version of local_sout_char_array
.align 4
.issue_mode dual
local_sout_char_array:
  { ldw r11, cp[.Llocal_sout_char_array_rom_addr] }
  { nop ; bau r11 }
#else
.align 2
local_sout_char_array:
  // Output bytewise if size < 8
  shr r11, r2, 3
  bf r11, .Lpart_3_loop_test
  // r3 = align_down(dst + size)
  add r11, r1, r2
  shr r3, r11, 2
  shl r3, r3, 2
  // r1 = num misaligned bytes after align_down(dst + size)
  sub r1, r11, r3
  bf r1, .Lskip_part_1
  sub r2, r2, r1
.Lpart_1_loop:
  sub r1, r1, 1
  ld8u r11, r3[r1]
  outt res[r0], r11
  bt r1, .Lpart_1_loop
.Lskip_part_1:
  // r11 = num quad words rem
  shr r11, r2, 4
  // r1 = num words remaining (after dealing with quad words)
  shr r1, r2, 2
  zext r1, 2
  // r2 = num bytes remaining (after dealing with words)
  zext r2, 2
  ldaw r3, r3[-r1]
  bru r1
  // No need to jump to the loop test if words remainder is zero, since
  // this can only happen if num quad words > 0 (an earlier check ensures there
  // is always at least one word to output).
  .jmptable .Lpart_2_loop, .Lrem1, .Lrem2, .Lrem3
.Lpart_2_loop:
  ldaw r3, r3[-4]
.Lrem0:
  sub r11, r11, 1
  ldw r1, r3[3]
  out res[r0], r1
.Lrem3:
  ldw r1, r3[2]
  out res[r0], r1
.Lrem2:
  ldw r1, r3[1]
  out res[r0], r1
.Lrem1:
  ldw r1, r3[0]
  out res[r0], r1
  bt r11, .Lpart_2_loop
  // Handle misaligned bytes
  bf r2, .Llocal_sout_char_array_ret
  sub r1, r3, r2
.Lpart_3_loop:
  sub r2, r2, 1
  ld8u r11, r1[r2]
  outt res[r0], r11
.Lpart_3_loop_test:
  bt r2, .Lpart_3_loop
.Llocal_sout_char_array_ret:
  retsp 0
#endif
.size local_sout_char_array, .-local_sout_char_array
.cc_bottom local_sout_char_array.function
.globl local_sout_char_array.nstackwords
.globl local_sout_char_array.maxchanends
.globl local_sout_char_array.maxtimers
.globl local_sout_char_array.maxcores
.set local_sout_char_array.nstackwords, 0
.set local_sout_char_array.maxchanends, 0
.set local_sout_char_array.maxtimers, 0
.set local_sout_char_array.maxcores, 0
.set local_sout_char_array.locnochandec, 1
.set local_sout_char_array.locnoglobalaccess, 1
.set local_sout_char_array.locnointerfaceaccess, 1
.set local_sout_char_array.locnonotificationselect, 1