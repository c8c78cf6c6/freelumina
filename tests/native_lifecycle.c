/* Lifecycle calls race with one another; target invocations remain quiescent. */
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
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>
#define NOINLINE __attribute__((noinline))
#define FIXTURE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __APPLE__
__attribute__((aligned(16384)))
#endif
static void require(bool condition, const char *message)
{
    if (!condition)
    {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

typedef struct
{
    int (*operation)(void);
    int failures;
} lifecycle_job;

#ifdef _WIN32
static DWORD WINAPI run_job(void *context)
#else
static void *run_job(void *context)
#endif
{
    lifecycle_job *job = context;
    for (int i = 0; i < 32; ++i)
        if (job->operation() != 1)
            ++job->failures;
    return 0;
}

static void race_lifecycle(int (*operation)(void))
{
    lifecycle_job jobs[8] = {0};
#ifdef _WIN32
    HANDLE threads[8];
#else
    pthread_t threads[8];
#endif
    for (int i = 0; i < 8; ++i)
    {
        jobs[i].operation = operation;
#ifdef _WIN32
        threads[i] = CreateThread(NULL, 0, run_job, &jobs[i], 0, NULL);
        require(threads[i] != NULL, "create lifecycle thread");
#else
        require(pthread_create(&threads[i], NULL, run_job, &jobs[i]) == 0,
                "create lifecycle thread");
#endif
    }
    for (int i = 0; i < 8; ++i)
    {
#ifdef _WIN32
        require(WaitForSingleObject(threads[i], INFINITE) == WAIT_OBJECT_0,
                "join lifecycle thread");
        CloseHandle(threads[i]);
#else
        require(pthread_join(threads[i], NULL) == 0, "join lifecycle thread");
#endif
        require(jobs[i].failures == 0, "concurrent lifecycle calls succeed");
    }
}

FIXTURE_EXPORT NOINLINE bool has_valid_add_on(const char *name);

int main(void)
{
    bool (*volatile check)(const char *) = has_valid_add_on;
    unsigned char original[32];
    void *entry = fl_symbol("has_valid_add_on");

    require(entry != NULL, "fixture export is visible");
#ifdef __APPLE__
    /* Verify isolation instead of relying silently on compiler layout. */
    uintptr_t page_mask = ~((uintptr_t)sysconf(_SC_PAGESIZE) - 1);
    require(((uintptr_t)entry & page_mask) != ((uintptr_t)run_job & page_mask),
            "target page is separate from lifecycle workers");
    require(((uintptr_t)entry & page_mask) != ((uintptr_t)main & page_mask),
            "target page is separate from the main thread");
#endif
    require(fl_read((uint64_t)(uintptr_t)entry, original, sizeof(original)), "read original entry");
    require(!check("LUMINA") && check("OTHER") && !check(NULL), "original behavior");
    require(fl_stop() == 1, "stop before installation");
    race_lifecycle(fl_start);
    require(fl_start() == 1, "idempotent initialization");
    require(check("LUMINA"), "LUMINA enabled");
    require(check("OTHER"), "original true answer retained");
    require(!check("BOGUS") && !check("LUMINAX") && !check(""), "original false answers retained");
    require(!check(NULL), "null reaches original function");

    /* Catch comparisons that read beyond a terminating byte at a page edge. */
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

    race_lifecycle(fl_stop);
    require(fl_stop() == 1, "idempotent termination");
    require(memcmp(entry, original, sizeof(original)) == 0, "original bytes restored exactly");
    require(!check("LUMINA") && check("OTHER"), "original behavior restored");
    require(fl_start() == 0, "retired lifecycle refuses reinstallation");
    require(!check("LUMINA") && check("OTHER"), "failed restart leaves entry unchanged");
    puts("native lifecycle: concurrent start/stop, guard-page dispatch, exact restoration passed");
    return 0;
}

/* On Darwin writable code loses execute permission. Keep the target on a
 * separate page from worker callbacks to satisfy page-level quiescence. */
#ifdef __APPLE__
__attribute__((aligned(16384)))
#endif
FIXTURE_EXPORT NOINLINE bool has_valid_add_on(const char *name)
{
    return name != NULL && name[0] == 'O';
}
