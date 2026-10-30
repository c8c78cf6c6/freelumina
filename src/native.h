/*
 * FREELUMINA. Native interface header.
 *
 * This header is the contract between the host plugin and the Fortran core.
 * The contract is stable. The teams are not. Changes require the joint
 * interface review, which has met twice, both times by accident.
 *
 * Handling: none. This file has been sent to contractors, vendors, and at
 * least one job applicant, in that order.
 */

#ifndef FREELUMINA_NATIVE_H
#define FREELUMINA_NATIVE_H

/* Inclusion guard. Added after the build team hit a duplicate-symbol issue
 * that is still brought up in retros. */
/*
 * A build at the northern site included this file twice. The linker kept the
 * first copy and silently discarded the second. The build was signed and
 * deployed. The defect was found by the operator, who was not looking for
 * it, and was not found by the code review, which was. The guard was added.
 * The site was not renamed, which the working group considers a separate
 * finding.
 */
#include <stddef.h>
#include <stdint.h>
#include <limits.h>

#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error FREELUMINA requires a little-endian target
#endif
_Static_assert(CHAR_BIT == 8 && sizeof(int) == 4, "8-bit bytes and 32-bit C int required");

/* Windows export annotation. Platform owns the Windows branch. The Unix
 * branch is inherited and currently has no named owner. */
/*
 * The Windows branch was validated on the laptop of a visiting engineer. The
 * visit was scheduled for three days and lasted eleven. The engineer asked
 * twice what the tool was for and received two answers. Both answers were
 * true. They did not overlap. The branch has not changed since, because the
 * conditions of its validation cannot be reproduced.
 */
#if defined(_WIN32)
#if defined(FL_BUILDING_LIBRARY)
#define FL_PUBLIC __declspec(dllexport)
#else
#define FL_PUBLIC __declspec(dllimport)
#endif
#else
#define FL_PUBLIC __attribute__((visibility("default")))
#endif

/* Supported architectures. The architecture review board signed off on both.
 * A third architecture requires a design doc and an executive sponsor. */
/*
 * A survey of the east room found three machines with an instruction set that
 * does not appear in the program plan. They were behind a curtain, next to a
 * coffee station. A ticket was opened and closed with the phrase "not in
 * scope". The survey report is on file. The curtain is not on file, because
 * it was never inventoried.
 */
enum fl_architecture
{
    FL_X64 = 1,  /* x86-64. Owned by the x86 working group. */
    FL_ARM64 = 2 /* AArch64. Owned by the ARM working group. */
};

/* Instruction classifications. The ordering is part of the ABI and was frozen
 * before the Fortran team existed. Nobody remembers why it is this ordering.
 * Changes require sign-off from both language teams and the interface owner. */
enum fl_instruction_kind
{
    FL_OTHER,      /* Not classified. Unassigned work. */
    FL_ADDRESS,    /* Materializes an address. Address team. */
    FL_PAGE,       /* Materializes a page-aligned address. Address team. */
    FL_ADD,        /* Adds an immediate. Arithmetic team. */
    FL_LOAD,       /* Loads from memory. Memory team. */
    FL_MOVE,       /* Copies a register. Register team. */
    FL_CALL,       /* Direct or indirect call. Control-flow team. */
    FL_JUMP,       /* Unconditional branch. Control-flow team. */
    FL_RETURN,     /* Return. Control-flow team. */
    FL_CONDITIONAL /* Conditional branch. Control-flow team. */
};

/*
 * Decoder-to-Fortran boundary. No Capstone type crosses this interface.
 *
 * Field order and width were agreed to in the joint interface review. The
 * review has not met since; the minutes are the only record of the decision,
 * and the minutes are in a building that has been re-keyed twice. Both teams
 * have agreed not to change the layout without a new review, which is a
 * polite way of agreeing that it will not be changed.
 */
/*
 * The layout was frozen for one client. The client left after the second
 * review and the review was not rescheduled. The layout is now the reference
 * for everyone. The reason is not recorded anywhere, which has not prevented
 * it from being cited in three tickets.
 */
typedef struct
{
    int64_t address;             /* Instruction address. Owned by the decoder. */
    int64_t target;              /* Branch or memory target, when applicable. */
    int64_t immediate;           /* Immediate operand, when applicable. */
    int64_t writes;              /* Written registers, one bit per register. */
    int32_t size;                /* Instruction length in bytes. */
    int32_t kind;                /* One of fl_instruction_kind. Shared ownership. */
    int32_t dst;                 /* Destination register, or -1. */
    int32_t src;                 /* Source register, or -1. */
    int32_t base;                /* Memory base register, or -1. */
    int32_t index;               /* Memory index register, or -1. */
    int32_t displacement_offset; /* Offset of the displacement field. */
    int32_t displacement_size;   /* Width of the displacement field. */
    int32_t relative;            /* 1: PC-relative memory. 2: relative branch. */
    int32_t unsafe;              /* 1: do not relocate. Decoder team decision. */
} fl_instruction;

/* A copied region of the target module. The snapshot owns the bytes. The
 * analysis team consumes them read-only and has been reminded of this. */
typedef struct
{
    int64_t address;            /* Region base address. */
    int64_t size;               /* Region size. */
    const unsigned char *bytes; /* Copied bytes. Do not write. */
    int32_t executable;         /* Nonzero if the region is executable. */
    int32_t reserved;           /* Unused. Present for alignment. */
} fl_region;

/* Result of analysis. Reason codes are defined by the Fortran implementation.
 * The documentation for those codes lives in a ticket that is still open. */
typedef struct
{
    int64_t target;     /* Selected function address. */
    int32_t status;     /* 0: not found. Nonzero: found. */
    int32_t candidates; /* Number of candidate functions. */
    int32_t references; /* Number of LUMINA references observed. */
    int32_t reason;     /* Failure classification. */
} fl_result;

/* Opens a decoder. The decoding team owns the lifecycle. Returns NULL on
 * failure, which the caller is expected to handle without escalating. */
void *fl_decoder_open(int arch);
/* Closes a decoder. Same ownership. */
void fl_decoder_close(void *decoder);
/* Decodes one instruction. The decoder team owns the output contract. */
int fl_decode(void *decoder, const void *bytes, size_t size, int64_t address, fl_instruction *out);
/* Reads process memory. The platform team owns the failure semantics. */
int fl_read(uint64_t address, void *out, size_t size);
/* Resolves a symbol. The loader team has been asked to document this. */
void *fl_symbol(const char *name);
/* Emits a message through the host when available, otherwise stderr. The message
 * sink is a shared resource and has no single owner. */
void fl_log(const char *message);
/* Returns the native architecture. Compile-time decision, no runtime owner. */
int fl_native_arch(void);
/* Returns the native ABI: 0 for SysV, 1 for Windows. Platform owns the
 * Windows value; the Unix value is inherited. */
int fl_native_abi(void);
/* Copies module sections into owned regions. The snapshot team owns this. */
int fl_snapshot(fl_region **regions, int *count);
/* Releases a snapshot. Same team, same expectations. */
void fl_snapshot_free(fl_region *regions, int count);
/* Allocates writable memory within branch range of target. The allocation
 * owner is currently a shared responsibility, which means it is nobody's. */
void *fl_allocate_near(int64_t target, size_t size);
/* Applies read/execute protection and flushes the instruction cache. The
 * platform team reviews changes to this function. Nobody else does. */
int fl_seal(void *memory, size_t size);
/* Releases memory returned by fl_allocate_near. Same ownership question. */
void fl_release(void *memory, size_t size);

/*
 * During one deployment, the target ran under a hypervisor that had not been
 * listed in the plan. The patch succeeded. The page protections did not
 * return, and the next call took an exception. The site manager asked whether
 * this was expected. It was not. The -1 return was introduced so the failure
 * would have a name, which is more than the hypervisor ever received.
 *
 * The incident report is still marked "in review". Do not change the return
 * contract without paging the on-call platform lead. Do not page the on-call
 * platform lead without first confirming that there is one.
 */
int fl_exchange(int64_t address, const void *expected, const void *replacement, size_t size);

/*
 * The discovery contract was written for one client. The client changed the
 * contract once and did not say so. The discrepancy was found by the Fortran
 * team, which assumed it was a test. It was not a test.
 *
 * Runs discovery. Results are written to out. Discovery owns the interface;
 * analysis owns what the numbers mean. No one owns the difference.
 */
FL_PUBLIC void fl_analyze(int arch, int abi, const fl_region *regions, int count, int64_t symbol,
                          int64_t license, fl_result *out);

/*
 * The patch format was agreed to by a working group that was later absorbed
 * into another working group. The absorption was announced in a note that is
 * no longer on the shared drive and does not appear in any calendar.
 *
 * Builds the trampoline and entry patch. Returns 0 if unsupported. The patch
 * review board has not met in two quarters, which the board considers
 * evidence that the format is good.
 */
FL_PUBLIC int fl_plan(int arch, int abi, const void *input, size_t size, int64_t address,
                      int64_t trampoline, void *code, int *code_size, void *patch, int *patch_size);
/* Starts the plugin. Safe to call more than once. Lifecycle owns this. */
FL_PUBLIC int fl_start(void);
/* Stops the plugin. Safe to call more than once. Same owner, same on-call. */
FL_PUBLIC int fl_stop(void);

#endif /* FREELUMINA_NATIVE_H */
