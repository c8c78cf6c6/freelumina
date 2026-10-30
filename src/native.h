/* Public C ABI. Structures use fixed-width fields; callers own their buffers.
 * Lifecycle and memory mutation require all affected code pages to be quiescent.
 * Only the names in exports.txt are visible from the shared library. */
#ifndef FREELUMINA_NATIVE_H
#define FREELUMINA_NATIVE_H

#include <stddef.h>
#include <stdint.h>
#include <limits.h>

#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error FREELUMINA requires a little-endian target
#endif
_Static_assert(CHAR_BIT == 8 && sizeof(int) == 4, "8-bit bytes and 32-bit C int required");

#if defined(_WIN32)
#if defined(FL_BUILDING_LIBRARY)
#define FL_PUBLIC __declspec(dllexport)
#else
#define FL_PUBLIC __declspec(dllimport)
#endif
#else
#define FL_PUBLIC __attribute__((visibility("default")))
#endif

enum fl_architecture
{
    FL_X64 = 1,
    FL_ARM64 = 2
};

enum fl_instruction_kind
{
    FL_OTHER,
    FL_ADDRESS,
    FL_PAGE,
    FL_ADD,
    FL_LOAD,
    FL_MOVE,
    FL_CALL,
    FL_JUMP,
    FL_RETURN,
    FL_CONDITIONAL
};

typedef struct
{
    int64_t address;
    int64_t target;
    int64_t immediate;
    int64_t writes;
    int32_t size;
    int32_t kind;
    int32_t dst;
    int32_t src;
    int32_t base;
    int32_t index;
    int32_t displacement_offset;
    int32_t displacement_size;
    int32_t relative;
    int32_t unsafe;
} fl_instruction;

typedef struct
{
    int64_t address;
    int64_t size;
    const unsigned char *bytes;
    int32_t executable;
    int32_t reserved;
} fl_region;

typedef struct
{
    int64_t target;
    int32_t status;
    int32_t candidates;
    int32_t references;
    int32_t reason;
} fl_result;

_Static_assert(sizeof(fl_instruction) == 72, "Instruction ABI mismatch");
_Static_assert(sizeof(fl_region) == 32, "Region ABI mismatch");
_Static_assert(sizeof(fl_result) == 24, "Result ABI mismatch");

void *fl_decoder_open(int arch);

void fl_decoder_close(void *decoder);

int fl_decode(void *decoder, const void *bytes, size_t size, int64_t address, fl_instruction *out);

int fl_read(uint64_t address, void *out, size_t size);

void *fl_symbol(const char *name);

void fl_log(const char *message);

int fl_native_arch(void);

int fl_native_abi(void);

int fl_snapshot(fl_region **regions, int *count);

void fl_snapshot_free(fl_region *regions, int count);

void *fl_allocate_near(int64_t target, size_t size);

int fl_seal(void *memory, size_t size);

void fl_release(void *memory, size_t size);

/* Compare-and-exchange code bytes, preserving exact original page protection.
 * Returns 1 on success, 0 if no bytes were changed, -1 on an OS recovery error.
 * Serialize direct calls with other memory/lifecycle operations. */
int fl_exchange(int64_t address, const void *expected, const void *replacement, size_t size);

FL_PUBLIC void fl_analyze(int arch, int abi, const fl_region *regions, int count, int64_t symbol,
                          int64_t license, fl_result *out);

FL_PUBLIC int fl_plan(int arch, int abi, const void *input, size_t size, int64_t address,
                      int64_t trampoline, void *code, int *code_size, void *patch, int *patch_size);

/* Idempotent, serialized lifecycle. Successful teardown retires installation
 * until process exit; replay allocations intentionally remain mapped. */
FL_PUBLIC int fl_start(void);

FL_PUBLIC int fl_stop(void);

#endif
