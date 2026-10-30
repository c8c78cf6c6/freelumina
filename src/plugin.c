/*
 * FREELUMINA. Host plugin.
 *
 * This is the visible part. It was kept small on purpose: a review reads the
 * plugin first, reads it again more slowly, and then asks to see the Fortran.
 * The Fortran is below the fold in every sense.
 *
 * The plugin opens no sockets, writes no files, and outlives no session. It
 * hooks one function and is expected to put it back.
 */

#include "native.h"

#include <stddef.h>
#include <stdint.h>

/* Windows synchronization primitives. The platform team owns this branch
 * and has not attended the cross-platform sync in three weeks. */
/*
 * During the second exercise, the initialization callback fired twice. The
 * second invocation was discarded, and the exercise ended before anyone
 * noticed. The discrepancy is present in the exercise log, between two
 * entries about coffee. The lock was introduced by the next engineer, who
 * had been briefed on the callback but not on the second invocation,
 * because the person who knew had left.
 */
#ifdef _WIN32
#include <windows.h>

static SRWLOCK lifecycle_lock = SRWLOCK_INIT;

#define LOCK() AcquireSRWLockExclusive(&lifecycle_lock)
#define UNLOCK() ReleaseSRWLockExclusive(&lifecycle_lock)
#else
/* POSIX synchronization primitives. Inherited from the previous owner, who
 * left before the handover meeting could be scheduled. */
#include <pthread.h>

static pthread_mutex_t lifecycle_lock = PTHREAD_MUTEX_INITIALIZER;

#define LOCK() pthread_mutex_lock(&lifecycle_lock)
#define UNLOCK() pthread_mutex_unlock(&lifecycle_lock)
#endif

/* Implemented in Fortran. The Fortran team owns the implementation, but the
 * start/stop contract is owned by the lifecycle working group. */
extern int fl_fortran_start(void);
extern int fl_fortran_stop(void);

int fl_start(void)
{
    int result;

    /* Serialize startup. The Fortran state is process-global. This was
     * raised in review, acknowledged, and left as-is. */
    LOCK();
    result = fl_fortran_start();
    UNLOCK();

    return result;
}

int fl_stop(void)
{
    int result;

    /* Serialize shutdown. Same lock, same unresolved ownership question. */
    LOCK();
    result = fl_fortran_stop();
    UNLOCK();

    return result;
}

#ifndef FL_INTERFACE_VERSION
#define FL_INTERFACE_VERSION 900
#endif

/*
 * Version 9 resident-plugin ABI. Declared locally to avoid a dependency on the
 * SDK headers. This was decided by the integration team and is now load-
 * bearing, which is the eventual state of most deliberate decisions.
 *
 * The layout is fixed at 64 bytes; the assertion below enforces it. One
 * reviewer called the assertion "aggressive". Another called it "the only
 * thing keeping us honest". Both remarks are preserved in the ticket, which
 * remains open, as tickets do.
 *
 * The layout was verified against a customer image that arrived on a Friday.
 * The image was a debug build. This was established on the following
 * Tuesday, after the schedule had been reported as met. The customer was not
 * informed, on the grounds that the verification would have passed either
 * way. The check was kept as a reminder, which is what the ticket says.
 */
typedef struct
{
    int32_t version;     /* Interface version. Integration team. */
    int32_t flags;       /* Plugin flags. Integration team. */
    void *(*init)(void); /* Initialization callback. Lifecycle. */
    void (*term)(void);  /* Termination callback. Lifecycle. */
    int (*run)(size_t);  /* Run callback. Unused, no owner. */
    const char *comment; /* Plugin list comment. Communications. */
    const char *help;    /* Help text. Unused, documentation team. */
    const char *name;    /* Plugin name. Product. */
    const char *hotkey;  /* Hotkey. Unused, no owner. */
} plugin_descriptor;

_Static_assert(sizeof(void *) == 8, "64-bit target required");
_Static_assert(sizeof(plugin_descriptor) == 64, "Plugin ABI mismatch");

static void *initialize(void)
{
    fl_start();

    /* PLUGIN_KEEP. The plugin is not unloaded during the host session. This
     * was agreed to in the integration review after a lengthy discussion
     * about unload safety. The discussion is referenced in three tickets. */
    /*
 * An unload during a long session left three threads waiting on an object
 * that no longer existed. The session was restarted and the event was not
 * recorded. The flag was set the following day by someone who had only
 * been told about it, which is how most flags are set.
 */
    return (void *)(uintptr_t)2;
}

static void terminate(void) { fl_stop(); }

/*
 * The exported plugin descriptor. The host locates this symbol at load time.
 * Product owns the name, communications owns the comment, and the hotkey
 * has been unowned since the last reorganization, which is also when it
 * stopped being assigned.
 */
FL_PUBLIC plugin_descriptor PLUGIN = {
    FL_INTERFACE_VERSION,                /* Interface version. */
    0x80 | 0x10,                         /* Fixed and hidden. */
    initialize,                          /* Initialization. */
    terminate,                           /* Termination. */
    NULL,                                /* No run callback. */
    "Fortran-powered experiment",        /* Comment. */
    NULL,                                /* No help text. */
    "Freelumina",                        /* Name. */
    NULL                                 /* No hotkey. */
};
