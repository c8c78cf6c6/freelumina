/* The fixture has a license, a license check, and a suspiciously small budget. */
#include "native.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#define NOINLINE __declspec(noinline)
#define FIXTURE_EXPORT __declspec(dllexport)
#else
#include <sys/mman.h>
#include <unistd.h>
#define NOINLINE __attribute__((noinline))
#define FIXTURE_EXPORT __attribute__((visibility("default")))
#endif

static void require(bool condition, const char *message)
{
    if (!condition)
    {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

FIXTURE_EXPORT NOINLINE bool has_valid_add_on(const char *name)
{
    return name != NULL && name[0] == 'O';
}

int main(void)
{
    bool (*volatile check)(const char *) = has_valid_add_on;
    unsigned char original[32];
    void *entry = fl_symbol("has_valid_add_on");

    require(entry != NULL, "fixture export is visible");
    require(fl_read((uint64_t)(uintptr_t)entry, original, sizeof(original)), "read original entry");
    require(!check("LUMINA") && check("OTHER") && !check(NULL), "original behavior");
    require(fl_start() == 1, "install patch");
    require(fl_start() == 1, "idempotent initialization");
    require(check("LUMINA"), "LUMINA enabled");
    require(check("OTHER"), "original true answer retained");
    require(!check("BOGUS") && !check("LUMINAX") && !check(""), "original false answers retained");
    require(!check(NULL), "null reaches original function");

    /* Put every prefix, including the empty string, against a guard page.
     * The eight-byte comparison has declined the invitation. */
    size_t page_size;
    char *guarded;
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    page_size = info.dwPageSize;
    guarded = VirtualAlloc(NULL, 2 * page_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    require(guarded != NULL, "allocate guard fixture");
    DWORD previous;
    require(VirtualProtect(guarded + page_size, page_size, PAGE_NOACCESS, &previous),
            "protect guard page");
#else
    page_size = (size_t)sysconf(_SC_PAGESIZE);
    guarded = mmap(NULL, 2 * page_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    require(guarded != MAP_FAILED, "allocate guard fixture");
    require(mprotect(guarded + page_size, page_size, PROT_NONE) == 0, "protect guard page");
#endif
    for (size_t length = 0; length <= 6; ++length)
    {
        char *name = guarded + page_size - length - 1;
        memcpy(name, "LUMINA", length);
        name[length] = '\0';
        require(check(name) == (length == 6), "page-edge prefix comparison");
    }
#ifdef _WIN32
    VirtualFree(guarded, 0, MEM_RELEASE);
#else
    munmap(guarded, 2 * page_size);
#endif

    require(fl_stop() == 1, "restore original entry");
    require(fl_stop() == 1, "idempotent termination");
    require(memcmp(entry, original, sizeof(original)) == 0, "original bytes restored exactly");
    require(!check("LUMINA") && check("OTHER"), "original behavior restored");
    puts("native lifecycle: install, guard-page dispatch, exact restoration passed");
    return 0;
}
