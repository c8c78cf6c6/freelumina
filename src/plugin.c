#include "native.h"

#ifdef _WIN32
#include <windows.h>
static SRWLOCK lifecycle_lock = SRWLOCK_INIT;
#define LOCK() AcquireSRWLockExclusive(&lifecycle_lock)
#define UNLOCK() ReleaseSRWLockExclusive(&lifecycle_lock)
#else
#include <pthread.h>
static pthread_mutex_t lifecycle_lock = PTHREAD_MUTEX_INITIALIZER;
#define LOCK() pthread_mutex_lock(&lifecycle_lock)
#define UNLOCK() pthread_mutex_unlock(&lifecycle_lock)
#endif

/* Host callers must quiesce affected code pages before start/stop. This lock
 * serializes lifecycle state; it does not suspend other host threads. */
extern int fl_basic_start(void);
extern int fl_basic_stop(void);

int fl_start(void)
{
    LOCK();
    int result = fl_basic_start();
    UNLOCK();
    return result;
}

int fl_stop(void)
{
    LOCK();
    int result = fl_basic_stop();
    UNLOCK();
    return result;
}

#ifndef FL_INTERFACE_VERSION
#define FL_INTERFACE_VERSION 900
#endif

typedef struct
{
    int32_t version;
    int32_t flags;
    void *(*init)(void);
    void (*term)(void);
    int (*run)(size_t);
    const char *comment;
    const char *help;
    const char *name;
    const char *hotkey;
} plugin_descriptor;

_Static_assert(sizeof(void *) == 8, "64-bit target required");
_Static_assert(sizeof(plugin_descriptor) == 64, "Plugin ABI mismatch");

static void *initialize(void)
{
    fl_start();
    /* PLUGIN_KEEP: published replay memory and code must remain resident. */
    return (void *)(uintptr_t)2;
}

static void terminate(void) { fl_stop(); }

FL_PUBLIC plugin_descriptor PLUGIN = {
    FL_INTERFACE_VERSION,
    0x80 | 0x10, /* Fixed and hidden resident plugin. */
    initialize,
    terminate,
    NULL,
    "Numbered BASIC runtime plugin",
    NULL,
    "Freelumina",
    NULL
};
