/* FREELUMINA. The remaining C has been asked to justify its headcount. */
#include "native.h"
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#elif defined(__APPLE__)
#include <mach/mach.h>
#include <libkern/OSCacheControl.h>
uint32_t fl_task_self(void)
{
    /* mach_task_self is a macro over a loader-owned global, not a C function. */
    return mach_task_self();
}
#endif

void fl_log(const char *message)
{
    typedef void (*logger_function)(const char *, ...);
    logger_function logger = NULL;
    void *symbol = fl_symbol("msg");
    _Static_assert(sizeof(logger) == sizeof(symbol),
                   "native function-pointer representation required");
    memcpy(&logger, &symbol, sizeof(logger));
    if (logger)
    {
        logger("freelumina %s\n", message);
    }
    else
    {
        fprintf(stderr, "freelumina %s\n", message);
    }
}

int fl_flush_code(void *memory, size_t size)
{
#ifdef _WIN32
    return FlushInstructionCache(GetCurrentProcess(), memory, size) != 0;
#elif defined(__APPLE__)
    sys_icache_invalidate(memory, size);
    return 1;
#else
    __builtin___clear_cache((char *)memory, (char *)memory + size);
    return 1;
#endif
}
