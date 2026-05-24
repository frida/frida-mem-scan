// Self-contained, relocation-free scanner blob (x86_64).
//
// Mirrors scan_arm64.S: same four entry points, same ctx layout, same
// dispatch_apply_f-as-argument convention. SSE4.1 baseline (pcmpeqq +
// movmskpd).

.intel_syntax noprefix
.text

// ===============================================================
// _scan_parallel
//
//   rdi = dispatch_apply_f
//   rsi = queue
//   rdx = buf
//   rcx = qcount
//   r8  = mask
//   r9  = targets
//   [rbp+16] = ntargets
//   [rbp+24] = out_flat
//   [rbp+32] = out_cap_each
//   [rbp+40] = out_counts
//   [rbp+48] = out_chunk_offs
//   [rbp+56] = nthreads
//
// 96-byte frame: ctx at [rsp+0..+79], spare/save at [rsp+80..+95].
// ctx layout matches arm64.
// ===============================================================
.globl _scan_parallel
.p2align 4
_scan_parallel:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 96

    mov     qword ptr [rsp+0],  rdx
    mov     qword ptr [rsp+16], rcx
    mov     qword ptr [rsp+24], r8
    mov     qword ptr [rsp+32], r9

    mov     rax, [rbp+16]
    mov     [rsp+40], rax
    mov     rax, [rbp+24]
    mov     [rsp+48], rax
    mov     rax, [rbp+32]
    mov     [rsp+56], rax
    mov     rax, [rbp+40]
    mov     [rsp+64], rax
    mov     rax, [rbp+48]
    mov     [rsp+72], rax

    mov     rax, rcx
    mov     r10, [rbp+56]
    add     rax, r10
    dec     rax
    xor     edx, edx
    div     r10
    mov     [rsp+8], rax

    mov     [rsp+88], rdi

    mov     rdi, r10
    mov     rdx, rsp
    lea     rcx, [rip + _scan_parallel_worker]
    call    qword ptr [rsp+88]

    add     rsp, 96
    pop     rbp
    ret

.p2align 4
_scan_parallel_worker:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48

    mov     [rbp-8],  rdi
    mov     [rbp-16], rsi

    mov     r10, [rdi+8]
    mov     r11, [rdi+16]

    mov     rax, rsi
    imul    rax, r10

    mov     rcx, [rdi+72]
    mov     [rcx + rsi*8], rax

    cmp     rax, r11
    jb      Lpworker_run
    mov     rcx, [rdi+64]
    mov     qword ptr [rcx + rsi*8], 0
    jmp     Lpworker_done

Lpworker_run:
    sub     r11, rax
    cmp     r11, r10
    cmovae  r11, r10

    mov     rdx, [rdi+56]
    mov     rcx, rsi
    imul    rcx, rdx
    shl     rcx, 2
    add     rcx, [rdi+48]
    mov     [rsp+0], rdx

    mov     r9, rcx
    mov     r8, [rdi+40]
    mov     rdx, [rdi+24]
    mov     rcx, [rdi+32]
    mov     rsi, r11
    mov     r10, [rdi+0]
    lea     rdi, [r10 + rax*8]

    call    _scan

    mov     rcx, [rbp-8]
    mov     rsi, [rbp-16]
    mov     r11, [rcx+64]
    mov     [r11 + rsi*8], rax

Lpworker_done:
    add     rsp, 48
    pop     rbp
    ret

// ===============================================================
// _scan1_parallel — ctx slot at +32 holds target value instead of
// (targets, ntargets).
// ===============================================================
.globl _scan1_parallel
.p2align 4
_scan1_parallel:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 96

    mov     qword ptr [rsp+0],  rdx
    mov     qword ptr [rsp+16], rcx
    mov     qword ptr [rsp+24], r8
    mov     qword ptr [rsp+32], r9

    mov     rax, [rbp+16]
    mov     [rsp+48], rax
    mov     rax, [rbp+24]
    mov     [rsp+56], rax
    mov     rax, [rbp+32]
    mov     [rsp+64], rax
    mov     rax, [rbp+40]
    mov     [rsp+72], rax

    mov     rax, rcx
    mov     r10, [rbp+48]
    add     rax, r10
    dec     rax
    xor     edx, edx
    div     r10
    mov     [rsp+8], rax

    mov     [rsp+88], rdi

    mov     rdi, r10
    mov     rdx, rsp
    lea     rcx, [rip + _scan1_parallel_worker]
    call    qword ptr [rsp+88]

    add     rsp, 96
    pop     rbp
    ret

.p2align 4
_scan1_parallel_worker:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48

    mov     [rbp-8],  rdi
    mov     [rbp-16], rsi

    mov     r10, [rdi+8]
    mov     r11, [rdi+16]

    mov     rax, rsi
    imul    rax, r10

    mov     rcx, [rdi+72]
    mov     [rcx + rsi*8], rax

    cmp     rax, r11
    jb      L1pworker_run
    mov     rcx, [rdi+64]
    mov     qword ptr [rcx + rsi*8], 0
    jmp     L1pworker_done

L1pworker_run:
    sub     r11, rax
    cmp     r11, r10
    cmovae  r11, r10

    mov     rdx, [rdi+56]
    mov     rcx, rsi
    imul    rcx, rdx
    shl     rcx, 2
    add     rcx, [rdi+48]

    mov     r8, rcx                    // out_i → 5th arg
    mov     r9, rdx                    // out_cap_each → 6th arg
    mov     rcx, [rdi+32]              // target → 4th arg
    mov     rdx, [rdi+24]              // mask → 3rd arg
    mov     rsi, r11                   // n → 2nd arg
    mov     r10, [rdi+0]
    lea     rdi, [r10 + rax*8]         // buf+off*8 → 1st arg

    call    _scan1

    mov     rcx, [rbp-8]
    mov     rsi, [rbp-16]
    mov     r11, [rcx+64]
    mov     [r11 + rsi*8], rax

L1pworker_done:
    add     rsp, 48
    pop     rbp
    ret

// ===============================================================
// _scan — multi-target inner loop.
//
//   rdi = buf  rsi = qcount  rdx = mask
//   rcx = targets  r8 = ntargets  r9 = out
//   [rbp+16] = out_cap
// ===============================================================
.globl _scan
.p2align 4
_scan:
    push    rbp
    mov     rbp, rsp
    push    rbx                         // hit count (callee-saved)
    push    r12                         // targets ptr (callee-saved)

    xor     ebx, ebx
    test    rsi, rsi
    jz      Lscan_done

    mov     r11, [rbp+16]               // out_cap
    mov     r12, rcx                    // targets

    movq    xmm0, rdx
    punpcklqdq xmm0, xmm0

    cmp     r8, 4
    ja      Lscan_scalar

    movq    xmm2, [rcx]
    punpcklqdq xmm2, xmm2
    cmp     r8, 1
    je      Lscan_t1
    movq    xmm3, [rcx+8]
    punpcklqdq xmm3, xmm3
    cmp     r8, 2
    je      Lscan_t2
    movq    xmm4, [rcx+16]
    punpcklqdq xmm4, xmm4
    cmp     r8, 3
    je      Lscan_t3
    movq    xmm5, [rcx+24]
    punpcklqdq xmm5, xmm5
    jmp     Lscan_neon_init

Lscan_t1:
    movdqa  xmm3, xmm2
    movdqa  xmm4, xmm2
    movdqa  xmm5, xmm2
    jmp     Lscan_neon_init
Lscan_t2:
    movdqa  xmm4, xmm2
    movdqa  xmm5, xmm2
    jmp     Lscan_neon_init
Lscan_t3:
    movdqa  xmm5, xmm2

Lscan_neon_init:
    xor     r10, r10
    mov     rax, rsi
    and     rax, -2                     // qcount rounded down to 2

Lscan_neon_loop:
    cmp     r10, rax
    jae     Lscan_tail

    movdqu  xmm1, [rdi + r10*8]
    pand    xmm1, xmm0

    movdqa  xmm6, xmm1
    pcmpeqq xmm6, xmm2
    movdqa  xmm7, xmm1
    pcmpeqq xmm7, xmm3
    por     xmm6, xmm7
    movdqa  xmm7, xmm1
    pcmpeqq xmm7, xmm4
    por     xmm6, xmm7
    movdqa  xmm7, xmm1
    pcmpeqq xmm7, xmm5
    por     xmm6, xmm7

    movmskpd ecx, xmm6
    test    cl, cl
    jz      Lscan_neon_advance

    test    cl, 1
    jz      Lscan_l1
    call    Lscan_record
Lscan_l1:
    test    cl, 2
    jz      Lscan_neon_advance
    inc     r10
    call    Lscan_record
    dec     r10

Lscan_neon_advance:
    add     r10, 2
    jmp     Lscan_neon_loop

Lscan_tail:
    cmp     r10, rsi
    jae     Lscan_done
    mov     rax, [rdi + r10*8]
    and     rax, rdx
    xor     ecx, ecx
Lscan_tail_loop:
    cmp     rcx, r8
    jae     Lscan_done
    cmp     rax, [r12 + rcx*8]
    jne     Lscan_tail_next
    call    Lscan_record
    jmp     Lscan_done
Lscan_tail_next:
    inc     rcx
    jmp     Lscan_tail_loop

Lscan_scalar:
    xor     r10, r10
Lscan_scalar_loop:
    cmp     r10, rsi
    jae     Lscan_done
    mov     rax, [rdi + r10*8]
    and     rax, rdx
    xor     ecx, ecx
Lscan_scalar_t_loop:
    cmp     rcx, r8
    jae     Lscan_scalar_next
    cmp     rax, [r12 + rcx*8]
    jne     Lscan_scalar_t_next
    call    Lscan_record
    jmp     Lscan_scalar_next
Lscan_scalar_t_next:
    inc     rcx
    jmp     Lscan_scalar_t_loop
Lscan_scalar_next:
    inc     r10
    jmp     Lscan_scalar_loop

// Record helper: pre-increment store keeps rax/rcx/r10 intact.
Lscan_record:
    cmp     rbx, r11
    jae     Lscan_record_full
    mov     [r9 + rbx*4], r10d
Lscan_record_full:
    inc     rbx
    ret

Lscan_done:
    mov     rax, rbx
    pop     r12
    pop     rbx
    pop     rbp
    ret

// ===============================================================
// _scan1 — single-target fast path; 4 u64 slots per iteration.
//
//   rdi = buf  rsi = qcount  rdx = mask
//   rcx = target  r8 = out  r9 = out_cap
// ===============================================================
.globl _scan1
.p2align 4
_scan1:
    push    rbp
    mov     rbp, rsp
    push    rbx                         // hit count
    push    r12                         // target value

    xor     ebx, ebx
    test    rsi, rsi
    jz      L1done

    mov     r12, rcx                    // target

    movq    xmm0, rdx
    punpcklqdq xmm0, xmm0
    movq    xmm2, rcx
    punpcklqdq xmm2, xmm2

    xor     r10, r10
    mov     r11, rsi
    and     r11, -4                     // qcount rounded down to 4

L1loop:
    cmp     r10, r11
    jae     L1tail

    movdqu  xmm1, [rdi + r10*8]
    movdqu  xmm3, [rdi + r10*8 + 16]
    pand    xmm1, xmm0
    pand    xmm3, xmm0
    pcmpeqq xmm1, xmm2
    pcmpeqq xmm3, xmm2

    movdqa  xmm4, xmm1
    por     xmm4, xmm3
    movmskpd eax, xmm4
    test    eax, eax
    jz      L1advance

    movmskpd eax, xmm1
    test    al, 1
    jz      L1l1
    call    L1record
L1l1:
    test    al, 2
    jz      L1l2
    inc     r10
    call    L1record
    dec     r10
L1l2:
    movmskpd eax, xmm3
    test    al, 1
    jz      L1l3
    add     r10, 2
    call    L1record
    sub     r10, 2
L1l3:
    test    al, 2
    jz      L1advance
    add     r10, 3
    call    L1record
    sub     r10, 3

L1advance:
    add     r10, 4
    jmp     L1loop

L1tail:
    cmp     r10, rsi
    jae     L1done
    mov     rax, [rdi + r10*8]
    and     rax, rdx
    cmp     rax, r12
    jne     L1tail_next
    call    L1record
L1tail_next:
    inc     r10
    jmp     L1tail

L1record:
    cmp     rbx, r9
    jae     L1record_full
    mov     [r8 + rbx*4], r10d
L1record_full:
    inc     rbx
    ret

L1done:
    mov     rax, rbx
    pop     r12
    pop     rbx
    pop     rbp
    ret
