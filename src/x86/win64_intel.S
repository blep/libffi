#define LIBFFI_ASM
#include <fficonfig.h>
#include <ffi.h>
#include <ffi_cfi.h>
#include "asmnames.h"

#if defined(HAVE_AS_CFI_PSEUDO_OP)
        .cfi_sections   .debug_frame
#endif

#ifdef X86_WIN64
#define SEH(...) __VA_ARGS__
#define arg0	rcx
#define arg1	rdx
#define arg2	r8
#define arg3	r9
#else
#define SEH(...)
#define arg0	rdi
#define arg1	rsi
#define arg2	rdx
#define arg3	rcx
#endif

/* This macro allows the safe creation of jump tables without an
   actual table.  The entry points into the table are all 8 bytes.
   The use of ORG asserts that we're at the correct location.  */
/* ??? The clang assembler doesn't handle .org with symbolic expressions.  */
#if defined(__clang__) || defined(__APPLE__) || (defined (__sun__) && defined(__svr4__))
# define E(BASE, X)	ALIGN 8
#else
# define E(BASE, X)	ALIGN 8; ORG BASE + X * 8
#endif

	.CODE
	extern PLT(C(abort)):near
	extern C(ffi_closure_win64_inner):near

/* ffi_call_win64 (void *stack, struct win64_call_frame *frame, void *r10)

   Bit o trickiness here -- FRAME is the base of the stack frame
   for this function.  This has been allocated by ffi_call.  We also
   deallocate some of the stack that has been alloca'd.  */

	ALIGN	8
	PUBLIC	C(ffi_call_win64)

	; SEH(.safesh ffi_call_win64)
C(ffi_call_win64) proc SEH(frame)
; Input parameters:
; RCX: stack   (macro arg0), alloca of cif->bytes + sizeof(struct win64_call_frame) + rsize
; RDX: frame   (macro arg1)
; R8:  closure (macro arg2), null on standard function call
; struct win64_call_frame:
;   UINT64 rbp;		/* 0 */
;   UINT64 retaddr;	/* 8 */
;   UINT64 fn;		/* 16 */
;   UINT64 flags;	/* 24 */
;   UINT64 rvalue;	/* 32 */

	cfi_startproc
	/* Set up the local stack frame and install it in rbp/rsp.  */
	mov	RAX, [RSP] 
	mov [arg1], RBP         ; frame->rbp = RBP
	mov [arg1 + 8], RAX     ; frame->retaddr = [RSP]
	mov	 RBP, arg1          ; RBP = frame
	cfi_def_cfa(rbp, 16)
	cfi_rel_offset(rbp, 0)
	SEH(.pushreg rbp)
	SEH(.setframe rbp, 0)
	SEH(.endprolog)
	mov	RSP, arg0           ; RSP = stack (RCX)

	mov	R10, arg2           ; R10 = closure (R8)

	/* Load all slots into both general and xmm registers.  */
	mov	RCX, [RSP]                      ; RCX = stack[0]   (param #0 of called function)
	movsd XMM0, qword ptr [RSP]         ; XMM0 = stack[0]  (param #0 of called function)
	mov	RDX, [RSP + 8]                  ; RDX = stack[1]   (param #1 of called function)
	movsd XMM1, qword ptr [RSP + 8]     ; XMM1 = stack[1]  (param #1 of called function)
	mov R8, [RSP + 16]                  ; R8 = stack[2]    (param #2 of called function)
	movsd	XMM2, qword ptr [RSP + 16]  ; XMM2 = stack[2]  (param #2 of called function)
	mov	R9, [RSP + 24]                  ; R9 = stack[0]    (param #3 of called function)
	movsd	XMM3, qword ptr [RSP + 24]  ; XMM3 = stack[0]  (param #3 of called function)

	CALL qword ptr [RBP + 16]           ; (*(frame->fn))(...)

	mov	 ECX, [RBP + 24]                ; ECX = frame->flags
	mov	R8, [RBP + 32]                  ; R8 = frame->rvalue
	LEA	R10, ffi_call_win64_tab         ; R10 = ffi_call_win64_tab
	CMP	ECX, FFI_TYPE_SMALL_STRUCT_4B   ; if frame->flags > FFI_TYPE_SMALL_STRUCT_4B
	LEA	R10, [R10 + RCX*8]              ; R10 = ffi_call_win64_tab + frame->flags * 8
	JA	L99                             ; jump to L99 if frame->flags > FFI_TYPE_SMALL_STRUCT_4B
                                        ; jump to the code for handling the specific return type
                                        ; Each return type is handled in <= 8 bytes of assembly
	JMP	R10                             ; jmp *%r10

/* Below, we're space constrained most of the time.  Thus we eschew the
   modern "mov, pop, ret" sequence (5 bytes) for "leave, ret" (2 bytes).  */
epilogue macro
	LEAVE
	cfi_remember_state
	cfi_def_cfa(rsp, 8)
	cfi_restore(rbp)
	RET
	cfi_restore_state
endm

	ALIGN 8
ffi_call_win64_tab LABEL NEAR
E(0b, FFI_TYPE_VOID)
	epilogue
E(0b, FFI_TYPE_INT)
    mov dword ptr [r8], eax     
	epilogue
E(0b, FFI_TYPE_FLOAT)
	movss dword ptr [r8], xmm0 
	epilogue
E(0b, FFI_TYPE_DOUBLE)
	movsd qword ptr[r8], xmm0
	epilogue
E(0b, FFI_TYPE_LONGDOUBLE)
	call	PLT(C(abort))
E(0b, FFI_TYPE_UINT8)
	mov byte ptr [r8], al 
	epilogue
E(0b, FFI_TYPE_SINT8)
	mov byte ptr [r8], al 
	epilogue
E(0b, FFI_TYPE_UINT16)
	mov word ptr [r8], ax 
	epilogue
E(0b, FFI_TYPE_SINT16)
	mov word ptr [r8], ax 
	epilogue
E(0b, FFI_TYPE_UINT32)
    mov dword ptr [r8], eax     
	epilogue
E(0b, FFI_TYPE_SINT32)
    mov dword ptr [r8], eax     
	epilogue
E(0b, FFI_TYPE_UINT64)
	mov qword ptr [r8], rax 
	epilogue
E(0b, FFI_TYPE_SINT64)
	mov qword ptr [r8], rax
	epilogue
E(0b, FFI_TYPE_STRUCT)
	epilogue
E(0b, FFI_TYPE_POINTER)
	mov qword ptr [r8], rax 
	epilogue
E(0b, FFI_TYPE_COMPLEX)
	call	PLT(C(abort))
E(0b, FFI_TYPE_SMALL_STRUCT_1B)
	mov byte ptr [r8], al 
	epilogue
E(0b, FFI_TYPE_SMALL_STRUCT_2B)
	mov word ptr [r8], ax 
	epilogue
E(0b, FFI_TYPE_SMALL_STRUCT_4B)
	mov dword ptr [r8], eax 
	epilogue

	align	8
L99 LABEL near
	call	PLT(C(abort))

	epilogue

	cfi_endproc
	C(ffi_call_win64) endp


/* 32 bytes of outgoing register stack space, 8 bytes of alignment,
   16 bytes of result, 32 bytes of xmm registers.  */
#define ffi_clo_FS	(32+8+16+32)
#define ffi_clo_OFF_R	(32+8)
#define ffi_clo_OFF_X	(32+8+16)

	align	8
	PUBLIC	C(ffi_go_closure_win64)

C(ffi_go_closure_win64) proc
	cfi_startproc
	/* Save all integer arguments into the incoming reg stack space.  */
	mov qword ptr [rsp + 8], rcx; movq	%rcx, 8(%rsp)
	mov qword ptr [rsp + 16], rdx; movq	%rdx, 16(%rsp)
	mov qword ptr [rsp + 24], r8; movq	%r8, 24(%rsp)
	mov qword ptr [rsp + 32], r9 ;movq	%r9, 32(%rsp)

	mov rcx, qword ptr [r10 + 8]; movq	8(%r10), %rcx			/* load cif */
	mov rdx, qword ptr [r10 + 16];  movq	16(%r10), %rdx			/* load fun */
	mov r8, r10 ; movq	%r10, %r8			/* closure is user_data */
	jmp	ffi_closure_win64_2
	cfi_endproc
	C(ffi_go_closure_win64) endp

	align	8
	
PUBLIC C(ffi_closure_win64)
C(ffi_closure_win64) PROC FRAME
	cfi_startproc
	/* Save all integer arguments into the incoming reg stack space.  */
	mov qword ptr [rsp + 8], rcx; movq	%rcx, 8(%rsp)
	mov qword ptr [rsp + 16], rdx;	movq	%rdx, 16(%rsp)
	mov qword ptr [rsp + 24], r8; 	movq	%r8, 24(%rsp)
	mov qword ptr [rsp + 32], r9;	movq	%r9, 32(%rsp)

	mov rcx, qword ptr [FFI_TRAMPOLINE_SIZE + r10]	;movq	FFI_TRAMPOLINE_SIZE(%r10), %rcx		/* load cif */
	mov rdx, qword ptr [FFI_TRAMPOLINE_SIZE + 8 + r10] ;	movq	FFI_TRAMPOLINE_SIZE+8(%r10), %rdx	/* load fun */
	mov r8, qword ptr [FFI_TRAMPOLINE_SIZE+16+r10] ;movq	FFI_TRAMPOLINE_SIZE+16(%r10), %r8	/* load user_data */
ffi_closure_win64_2 LABEL near
	sub rsp, ffi_clo_FS ;subq	$ffi_clo_FS, %rsp
	cfi_adjust_cfa_offset(ffi_clo_FS)
	SEH(.allocstack ffi_clo_FS)
	SEH(.endprolog)

	/* Save all sse arguments into the stack frame.  */
	movsd qword ptr [ffi_clo_OFF_X + rsp], xmm0	; movsd	%xmm0, ffi_clo_OFF_X(%rsp)
	movsd qword ptr [ffi_clo_OFF_X+8+rsp], xmm1 ; movsd	%xmm1, ffi_clo_OFF_X+8(%rsp)
	movsd qword ptr [ffi_clo_OFF_X+16+rsp], xmm2 ; movsd %xmm2, ffi_clo_OFF_X+16(%rsp)
	movsd qword ptr [ffi_clo_OFF_X+24+rsp], xmm3 ; movsd %xmm3, ffi_clo_OFF_X+24(%rsp)

	lea	r9, [ffi_clo_OFF_R + rsp] ; leaq	ffi_clo_OFF_R(%rsp), %r9
	call C(ffi_closure_win64_inner)

	/* Load the result into both possible result registers.  */
	
	mov rax, qword ptr [ffi_clo_OFF_R + rsp] ;movq    ffi_clo_OFF_R(%rsp), %rax
	movsd xmm0, qword ptr [rsp + ffi_clo_OFF_R] ;movsd   ffi_clo_OFF_R(%rsp), %xmm0

	add rsp, ffi_clo_FS ;addq	$ffi_clo_FS, %rsp
	cfi_adjust_cfa_offset(-ffi_clo_FS)
	ret

	cfi_endproc
	C(ffi_closure_win64) endp

#if defined __ELF__ && defined __linux__
	.section	.note.GNU-stack,"",@progbits
#endif
_text ends
end