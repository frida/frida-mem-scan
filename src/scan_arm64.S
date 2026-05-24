// Self-contained, relocation-free scanner blob.
//
//   _scan_parallel  / _scan1_parallel   — GCD-parallel wrappers; caller
//                                         supplies dispatch_apply_f and
//                                         the queue as function-pointer
//                                         arguments.
//   _scan           — multi-target (up to 4 in NEON, scalar otherwise).
//   _scan1          — single-target fast path (4 u64 slots / iteration).
//
// All four live in the same __text section so workers can call into
// _scan / _scan1 via PC-relative `bl`. The blob can be copied to any
// executable page and run.

.text

// ===============================================================
// _scan_parallel
//
//   x0 = dispatch_apply_f
//   x1 = queue
//   x2 = buf
//   x3 = qcount
//   x4 = mask
//   x5 = targets
//   x6 = ntargets
//   x7 = out_flat
//   [sp+ 0] out_cap_each
//   [sp+ 8] out_counts
//   [sp+16] out_chunk_offs
//   [sp+24] nthreads
//
// 96-byte frame: ctx at [sp+0..+79], saved fp/lr at [sp+80..+95].
// ctx layout:
//   +0  buf       +8  per           +16 qcount   +24 mask
//   +32 targets   +40 ntargets      +48 out_flat +56 out_cap_each
//   +64 out_counts +72 out_chunk_offs
// ===============================================================
.align 4
.globl _scan_parallel
_scan_parallel:
    sub     sp,  sp,  #0x60
    stp     x29, x30, [sp, #0x50]
    add     x29, sp,  #0x50

    ldr     x9,  [sp, #0x60]
    ldr     x10, [sp, #0x68]
    ldr     x11, [sp, #0x70]
    ldr     x12, [sp, #0x78]

    sub     x13, x12, #1
    add     x13, x3,  x13
    udiv    x13, x13, x12

    stp     x2,  x13, [sp, #0]
    stp     x3,  x4,  [sp, #16]
    stp     x5,  x6,  [sp, #32]
    stp     x7,  x9,  [sp, #48]
    stp     x10, x11, [sp, #64]

    mov     x16, x0
    mov     x0,  x12
    mov     x2,  sp
    adr     x3,  _scan_parallel_worker
    blr     x16

    ldp     x29, x30, [sp, #0x50]
    add     sp,  sp,  #0x60
    ret

.align 4
_scan_parallel_worker:
    stp     x29, x30, [sp, #-0x20]!
    mov     x29, sp
    stp     x0,  x1,  [sp, #16]

    ldp     x10, x11, [x0, #0]
    ldp     x12, x13, [x0, #16]
    ldp     x14, x15, [x0, #32]
    ldp     x16, x17, [x0, #48]
    ldr     x9,  [x0, #72]

    mul     x2,  x1,  x11
    str     x2,  [x9, x1, lsl #3]

    cmp     x2,  x12
    b.lo    Lworker_run
    ldr     x9,  [x0, #64]
    str     xzr, [x9, x1, lsl #3]
    b       Lworker_done

Lworker_run:
    sub     x3,  x12, x2
    cmp     x3,  x11
    csel    x3,  x3,  x11, lo

    add     x10, x10, x2,  lsl #3
    mul     x4,  x1,  x17
    add     x16, x16, x4,  lsl #2

    mov     x0,  x10
    mov     x1,  x3
    mov     x2,  x13
    mov     x3,  x14
    mov     x4,  x15
    mov     x5,  x16
    mov     x6,  x17
    bl      _scan

    ldp     x9,  x10, [sp, #16]
    ldr     x11, [x9,  #64]
    str     x0,  [x11, x10, lsl #3]

Lworker_done:
    ldp     x29, x30, [sp], #0x20
    ret

// ===============================================================
// _scan1_parallel — same shape as _scan_parallel but for the
// single-target fast path. ctx slot at +32 holds the target value
// instead of a (targets, ntargets) pair.
// ===============================================================
.align 4
.globl _scan1_parallel
_scan1_parallel:
    sub     sp,  sp,  #0x60
    stp     x29, x30, [sp, #0x50]
    add     x29, sp,  #0x50

    ldr     x9,  [sp, #0x60]
    ldr     x10, [sp, #0x68]
    ldr     x11, [sp, #0x70]

    sub     x12, x11, #1
    add     x12, x3,  x12
    udiv    x12, x12, x11

    stp     x2,  x12, [sp, #0]
    stp     x3,  x4,  [sp, #16]
    str     x5,  [sp, #32]
    stp     x6,  x7,  [sp, #48]
    stp     x9,  x10, [sp, #64]

    mov     x16, x0
    mov     x0,  x11
    mov     x2,  sp
    adr     x3,  _scan1_parallel_worker
    blr     x16

    ldp     x29, x30, [sp, #0x50]
    add     sp,  sp,  #0x60
    ret

.align 4
_scan1_parallel_worker:
    stp     x29, x30, [sp, #-0x20]!
    mov     x29, sp
    stp     x0,  x1,  [sp, #16]

    ldp     x10, x11, [x0, #0]
    ldp     x12, x13, [x0, #16]
    ldr     x14, [x0, #32]
    ldp     x15, x16, [x0, #48]
    ldr     x9,  [x0, #72]

    mul     x2,  x1,  x11
    str     x2,  [x9,  x1, lsl #3]

    cmp     x2,  x12
    b.lo    L1worker_run
    ldr     x9,  [x0, #64]
    str     xzr, [x9,  x1, lsl #3]
    b       L1worker_done

L1worker_run:
    sub     x3,  x12, x2
    cmp     x3,  x11
    csel    x3,  x3,  x11, lo

    add     x10, x10, x2,  lsl #3
    mul     x4,  x1,  x16
    add     x15, x15, x4,  lsl #2

    mov     x0,  x10
    mov     x1,  x3
    mov     x2,  x13
    mov     x3,  x14
    mov     x4,  x15
    mov     x5,  x16
    bl      _scan1

    ldp     x9,  x10, [sp, #16]
    ldr     x11, [x9,  #64]
    str     x0,  [x11, x10, lsl #3]

L1worker_done:
    ldp     x29, x30, [sp], #0x20
    ret

// ===============================================================
// _scan — multi-target inner loop.
//
//   x0 = buf       x1 = qcount   x2 = mask
//   x3 = targets   x4 = ntargets x5 = out   x6 = out_cap
//
// Returns total hits seen (may exceed out_cap; out is then truncated).
// Two u64 slots per iteration via NEON; up to 4 targets compared in
// parallel. >4 targets falls back to a scalar inner loop.
// ===============================================================
.align 4
.globl _scan
_scan:
    stp     x29, x30, [sp, #-0x10]!
    mov     x29, sp

    mov     x7,  xzr
    cbz     x1,  Ldone

    dup     v0.2d, x2

    cmp     x4,  #4
    b.gt    Lscalar

    ldr     d2,  [x3]
    cmp     x4,  #1
    b.eq    L1_dups
    ldr     d3,  [x3, #8]
    cmp     x4,  #2
    b.eq    L2_dups
    ldr     d4,  [x3, #16]
    cmp     x4,  #3
    b.eq    L3_dups
    ldr     d5,  [x3, #24]
    b       L4_dups

L1_dups:
    dup     v2.2d, v2.d[0]
    mov     v3.16b, v2.16b
    mov     v4.16b, v2.16b
    mov     v5.16b, v2.16b
    b       Lneon_init
L2_dups:
    dup     v2.2d, v2.d[0]
    dup     v3.2d, v3.d[0]
    mov     v4.16b, v2.16b
    mov     v5.16b, v2.16b
    b       Lneon_init
L3_dups:
    dup     v2.2d, v2.d[0]
    dup     v3.2d, v3.d[0]
    dup     v4.2d, v4.d[0]
    mov     v5.16b, v2.16b
    b       Lneon_init
L4_dups:
    dup     v2.2d, v2.d[0]
    dup     v3.2d, v3.d[0]
    dup     v4.2d, v4.d[0]
    dup     v5.2d, v5.d[0]

Lneon_init:
    mov     x8,  xzr
    and     x9,  x1,  #~1

Lneon_loop:
    cmp     x8,  x9
    b.ge    Ltail

    add     x10, x0,  x8, lsl #3
    ldr     q1,  [x10]
    and     v1.16b, v1.16b, v0.16b

    cmeq    v16.2d, v1.2d, v2.2d
    cmeq    v17.2d, v1.2d, v3.2d
    cmeq    v18.2d, v1.2d, v4.2d
    cmeq    v19.2d, v1.2d, v5.2d
    orr     v16.16b, v16.16b, v17.16b
    orr     v18.16b, v18.16b, v19.16b
    orr     v16.16b, v16.16b, v18.16b

    mov     x11, v16.d[0]
    mov     x12, v16.d[1]
    orr     x13, x11, x12
    cbz     x13, Lneon_advance

    cbz     x11, Lcheck_lane1
    bl      Lrecord_hit_x8
Lcheck_lane1:
    cbz     x12, Lneon_advance
    add     x14, x8,  #1
    mov     x15, x8
    mov     x8,  x14
    bl      Lrecord_hit_x8
    mov     x8,  x15

Lneon_advance:
    add     x8,  x8,  #2
    b       Lneon_loop

Ltail:
    cmp     x8,  x1
    b.ge    Ldone
    add     x10, x0,  x8, lsl #3
    ldr     x11, [x10]
    and     x11, x11, x2

    mov     x12, xzr
Ltail_t_loop:
    cmp     x12, x4
    b.ge    Ldone
    ldr     x13, [x3, x12, lsl #3]
    cmp     x11, x13
    b.ne    Ltail_t_next
    bl      Lrecord_hit_x8
    b       Ldone
Ltail_t_next:
    add     x12, x12, #1
    b       Ltail_t_loop

Lscalar:
    mov     x8,  xzr
Lscalar_loop:
    cmp     x8,  x1
    b.ge    Ldone
    add     x10, x0,  x8, lsl #3
    ldr     x11, [x10]
    and     x11, x11, x2
    mov     x12, xzr
Lscalar_t_loop:
    cmp     x12, x4
    b.ge    Lscalar_next
    ldr     x13, [x3, x12, lsl #3]
    cmp     x11, x13
    b.ne    Lscalar_t_next
    bl      Lrecord_hit_x8
    b       Lscalar_next
Lscalar_t_next:
    add     x12, x12, #1
    b       Lscalar_t_loop
Lscalar_next:
    add     x8,  x8,  #1
    b       Lscalar_loop

Lrecord_hit_x8:
    add     x7,  x7,  #1
    cmp     x7,  x6
    b.hi    Lrecord_skip
    sub     x16, x7,  #1
    str     w8,  [x5, x16, lsl #2]
Lrecord_skip:
    ret

Ldone:
    mov     x0,  x7
    ldp     x29, x30, [sp], #0x10
    ret

// ===============================================================
// _scan1 — single-target fast path.
//
//   x0 = buf  x1 = qcount  x2 = mask
//   x3 = target (pre-masked)  x4 = out  x5 = out_cap
//
// Four u64 slots per iteration. Caller must pre-mask the target.
// ===============================================================
.align 4
.globl _scan1
_scan1:
    stp     x29, x30, [sp, #-0x10]!
    mov     x29, sp

    mov     x6,  xzr
    cbz     x1,  L1done

    dup     v0.2d, x2
    dup     v2.2d, x3

    mov     x8,  xzr
    and     x9,  x1,  #~3

L1loop:
    cmp     x8,  x9
    b.ge    L1tail

    add     x10, x0,  x8,  lsl #3
    ldp     q1,  q3,  [x10]
    and     v1.16b, v1.16b, v0.16b
    and     v3.16b, v3.16b, v0.16b
    cmeq    v1.2d,  v1.2d,  v2.2d
    cmeq    v3.2d,  v3.2d,  v2.2d
    orr     v4.16b, v1.16b, v3.16b

    mov     x11, v4.d[0]
    mov     x12, v4.d[1]
    orr     x13, x11, x12
    cbz     x13, L1advance

    mov     x11, v1.d[0]
    cbz     x11, L1l1
    bl      L1record
L1l1:
    mov     x11, v1.d[1]
    cbz     x11, L1l2
    add     x8,  x8,  #1
    bl      L1record
    sub     x8,  x8,  #1
L1l2:
    mov     x11, v3.d[0]
    cbz     x11, L1l3
    add     x8,  x8,  #2
    bl      L1record
    sub     x8,  x8,  #2
L1l3:
    mov     x11, v3.d[1]
    cbz     x11, L1advance
    add     x8,  x8,  #3
    bl      L1record
    sub     x8,  x8,  #3

L1advance:
    add     x8,  x8,  #4
    b       L1loop

L1tail:
    cmp     x8,  x1
    b.ge    L1done
    add     x10, x0,  x8,  lsl #3
    ldr     x11, [x10]
    and     x11, x11, x2
    cmp     x11, x3
    b.ne    L1tail_next
    bl      L1record
L1tail_next:
    add     x8,  x8,  #1
    b       L1tail

L1record:
    add     x6,  x6,  #1
    cmp     x6,  x5
    b.hi    L1record_skip
    sub     x14, x6,  #1
    str     w8,  [x4, x14, lsl #2]
L1record_skip:
    ret

L1done:
    mov     x0,  x6
    ldp     x29, x30, [sp], #0x10
    ret
