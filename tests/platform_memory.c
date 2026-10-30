/* The page protections return from this meeting in the state they arrived. */
#include "native.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#elif defined(__APPLE__)
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <sys/mman.h>
#include <unistd.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif

static void require(bool condition, const char *message)
{
    if (!condition)
    {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static unsigned protection_at(void *memory)
{
#ifdef _WIN32
    MEMORY_BASIC_INFORMATION info;
    require(VirtualQuery(memory, &info, sizeof(info)) != 0, "query Windows protection");
    return info.Protect;
#elif defined(__APPLE__)
    mach_vm_address_t address = (mach_vm_address_t)memory;
    mach_vm_size_t size;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t status =
        mach_vm_region(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64,
                       (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), object);
    require(status == KERN_SUCCESS, "query Mach protection");
    return (unsigned)info.protection;
#else
    FILE *maps = fopen("/proc/self/maps", "r");
    char line[1024], permissions[5];
    unsigned long first, limit;
    require(maps != NULL, "open Linux mappings");
    while (fgets(line, sizeof(line), maps))
    {
        if (sscanf(line, "%lx-%lx %4s", &first, &limit, permissions) == 3 &&
            (uintptr_t)memory >= first && (uintptr_t)memory < limit)
        {
            fclose(maps);
            return (permissions[0] == 'r' ? 1u : 0u) | (permissions[1] == 'w' ? 2u : 0u) |
                   (permissions[2] == 'x' ? 4u : 0u);
        }
    }
    fclose(maps);
    require(false, "mapping exists");
    return 0;
#endif
}

int main(void)
{
    size_t page_size;
    unsigned char *memory;
#ifdef _WIN32
    SYSTEM_INFO system;
    DWORD previous;
    GetSystemInfo(&system);
    page_size = system.dwPageSize;
    memory = VirtualAlloc(NULL, 2 * page_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    require(memory != NULL, "allocate fixture");
    memset(memory, 0xAA, 2 * page_size);
    require(VirtualProtect(memory, page_size, PAGE_EXECUTE_READ, &previous), "first page RX");
    require(VirtualProtect(memory + page_size, page_size, PAGE_EXECUTE_READWRITE, &previous),
            "second page RWX");
#else
    page_size = (size_t)sysconf(_SC_PAGESIZE);
    memory = mmap(NULL, 2 * page_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    require(memory != MAP_FAILED, "allocate fixture");
    memset(memory, 0xAA, 2 * page_size);
    require(mprotect(memory, page_size, PROT_READ | PROT_EXEC) == 0, "first page RX");
#ifdef __APPLE__
    /* Apple Silicon rejects RWX here. Exercise the page boundary with RX;
     * Linux and Windows additionally exercise distinct original protections. */
    require(mprotect(memory + page_size, page_size, PROT_READ | PROT_EXEC) == 0, "second page RX");
#else
    require(mprotect(memory + page_size, page_size, PROT_READ | PROT_WRITE | PROT_EXEC) == 0,
            "second page RWX");
#endif
#endif
    unsigned first_protection = protection_at(memory);
    unsigned second_protection = protection_at(memory + page_size);
    unsigned char original[8], replacement[8], wrong[8] = {0}, observed[8];
    memset(original, 0xAA, sizeof(original));
    memset(replacement, 0xBB, sizeof(replacement));
    int64_t address = (int64_t)(uintptr_t)(memory + page_size - 4);
    require(fl_exchange(address, wrong, replacement, 8) == 0, "foreign bytes are not overwritten");
    require(fl_exchange(address, original, replacement, 8) == 1, "exchange spanning two mappings");
    require(fl_read((uint64_t)address, observed, 8) && memcmp(observed, replacement, 8) == 0,
            "replacement readback");
    require(protection_at(memory) == first_protection, "first page protection restored exactly");
    require(protection_at(memory + page_size) == second_protection,
            "second page protection restored exactly");
    require(fl_exchange(address, replacement, original, 8) == 1, "restore bytes");
    require(!fl_read(UINT64_MAX - 3, observed, 8), "overflow read rejected");
#ifdef _WIN32
    require(VirtualProtect(memory + page_size, page_size, PAGE_NOACCESS, &previous),
            "guard fixture");
#else
    require(mprotect(memory + page_size, page_size, PROT_NONE) == 0, "guard fixture");
#endif
    require(!fl_read((uint64_t)address, observed, 8), "unreadable range rejected");
    require(fl_exchange(address, original, replacement, 8) == 0, "unreadable range not patched");
#ifdef _WIN32
    VirtualFree(memory, 0, MEM_RELEASE);
#else
    munmap(memory, 2 * page_size);
#endif
    puts("platform memory: page boundaries, exact protections, ownership, guard rejection passed");
    return 0;
}
