! FREELUMINA. Direct operating-system bindings.
!
! The platform team has been replaced with declarations. The declarations
! attend every build and have not yet requested a reorganization.
module fl_platform
    use, intrinsic :: iso_c_binding
    use fl_abi, only: region, x64, arm64
    use fl_bytes
    implicit none
    private
    public :: platform_architecture, platform_abi, resolve_symbol, read_process_memory
    public :: capture_snapshot, free_snapshot, allocate_nearby, seal_allocation
    public :: release_allocation, exchange_bytes

    integer, parameter :: region_limit = 4096
    integer(c_int64_t), parameter :: snapshot_limit = 536870912_c_int64_t
    integer(c_int), parameter :: protection_read = 1, protection_write = 2, protection_execute = 4

    type :: memory_mapping
        integer(c_intptr_t) :: first = 0, limit = 0
        integer(c_int) :: protection = 0
    end type

    ! Keep the exact original protections until every restoration succeeds.
    ! A failed OS call does not get to erase the rollback plan.
    type(memory_mapping), save :: recovery_mappings(2)
    integer(c_intptr_t), save :: recovery_pages(2) = 0
    integer(c_size_t), save :: recovery_page_size = 0
    integer, save :: recovery_count = 0

    type, bind(c) :: snapshot_builder
        type(c_ptr) :: storage
        integer(c_int64_t) :: total, anchor
        integer(c_int) :: count, failed
    end type

#ifdef FL_OS_WINDOWS
    type, bind(c) :: windows_mapping
        integer(c_intptr_t) :: base, allocation_base
        integer(c_int) :: allocation_protection, partition_and_padding
        integer(c_size_t) :: size
        integer(c_int) :: state, protection, kind, padding
    end type

    type, bind(c) :: windows_system_info
        integer(c_int) :: architecture_and_reserved, page_size
        integer(c_intptr_t) :: minimum_address, maximum_address, active_processor_mask
        integer(c_int) :: processors, processor_type, allocation_granularity
        integer(c_int16_t) :: processor_level, processor_revision
    end type
#else
    type, bind(c) :: dynamic_symbol_info
        type(c_ptr) :: filename, module_base, symbol_name, symbol_address
    end type
#ifndef FL_OS_MACOS
    type, bind(c) :: io_vector
        type(c_ptr) :: base
        integer(c_size_t) :: length
    end type
    type, bind(c) :: elf_program_header
        integer(c_int32_t) :: kind, flags
        integer(c_int64_t) :: offset, address, physical_address, file_size, memory_size, alignment
    end type
    type, bind(c) :: elf_loader_info
        integer(c_intptr_t) :: load_bias
        type(c_ptr) :: name, headers
        integer(c_int16_t) :: header_count
    end type
#endif
#endif

    interface
        function flush_code(memory, length) bind(c, name='fl_flush_code') result(success)
            import
            type(c_ptr), value :: memory
            integer(c_size_t), value :: length
            integer(c_int) :: success
        end function
#ifdef FL_OS_WINDOWS
        function get_module_handle(name) bind(c, name='GetModuleHandleA') result(handle)
            import
            type(c_ptr), value :: name
            type(c_ptr) :: handle
        end function
        function get_proc_address(handle, name) bind(c, name='GetProcAddress') result(pointer)
            import
            type(c_ptr), value :: handle
            character(c_char), intent(in) :: name(*)
            type(c_ptr) :: pointer
        end function
        function get_module_for_address(flags, address, handle) bind(c, name='GetModuleHandleExA') result(success)
            import
            integer(c_int), value :: flags
            integer(c_intptr_t), value :: address
            type(c_ptr), intent(out) :: handle
            integer(c_int) :: success
        end function
        function get_current_process() bind(c, name='GetCurrentProcess') result(handle)
            import
            type(c_ptr) :: handle
        end function
        function windows_read(handle, address, output, length, transferred) &
            bind(c, name='ReadProcessMemory') result(success)
            import
            type(c_ptr), value :: handle, output
            integer(c_intptr_t), value :: address
            integer(c_size_t), value :: length
            integer(c_size_t), intent(out) :: transferred
            integer(c_int) :: success
        end function
        function virtual_query(address, output, length) bind(c, name='VirtualQuery') result(transferred)
            import
            integer(c_intptr_t), value :: address
            type(windows_mapping), intent(out) :: output
            integer(c_size_t), value :: length
            integer(c_size_t) :: transferred
        end function
        subroutine get_system_info(output) bind(c, name='GetSystemInfo')
            import
            type(windows_system_info), intent(out) :: output
        end subroutine
        function virtual_allocate(address, length, kind, protection) bind(c, name='VirtualAlloc') result(pointer)
            import
            integer(c_intptr_t), value :: address
            integer(c_size_t), value :: length
            integer(c_int), value :: kind, protection
            type(c_ptr) :: pointer
        end function
        function virtual_release(memory, length, kind) bind(c, name='VirtualFree') result(success)
            import
            type(c_ptr), value :: memory
            integer(c_size_t), value :: length
            integer(c_int), value :: kind
            integer(c_int) :: success
        end function
        function virtual_protect(address, length, protection, previous) bind(c, name='VirtualProtect') result(success)
            import
            integer(c_intptr_t), value :: address
            integer(c_size_t), value :: length
            integer(c_int), value :: protection
            integer(c_int), intent(out) :: previous
            integer(c_int) :: success
        end function
#else
        function dynamic_symbol(handle, name) bind(c, name='dlsym') result(pointer)
            import
            type(c_ptr), value :: handle
            character(c_char), intent(in) :: name(*)
            type(c_ptr) :: pointer
        end function
        function symbol_info(address, output) bind(c, name='dladdr') result(success)
            import
            integer(c_intptr_t), value :: address
            type(dynamic_symbol_info), intent(out) :: output
            integer(c_int) :: success
        end function
        function get_page_size() bind(c, name='getpagesize') result(length)
            import
            integer(c_int) :: length
        end function
        function memory_map(address, length, protection, flags, descriptor, offset) bind(c, name='mmap') result(pointer)
            import
            integer(c_intptr_t), value :: address
            integer(c_size_t), value :: length
            integer(c_int), value :: protection, flags, descriptor
            integer(c_int64_t), value :: offset
            type(c_ptr) :: pointer
        end function
        function memory_unmap(memory, length) bind(c, name='munmap') result(status)
            import
            type(c_ptr), value :: memory
            integer(c_size_t), value :: length
            integer(c_int) :: status
        end function
        function memory_protect(address, length, protection) bind(c, name='mprotect') result(status)
            import
            integer(c_intptr_t), value :: address
            integer(c_size_t), value :: length
            integer(c_int), value :: protection
            integer(c_int) :: status
        end function
#ifdef FL_OS_MACOS
        function task_self() bind(c, name='fl_task_self') result(port)
            import
            integer(c_int) :: port
        end function
        function mach_read(task, address, length, output, transferred) bind(c, name='mach_vm_read_overwrite') result(status)
            import
            integer(c_int), value :: task
            integer(c_int64_t), value :: address, length
            type(c_ptr), value :: output
            integer(c_int64_t), intent(out) :: transferred
            integer(c_int) :: status
        end function
        function mach_region(task, address, length, flavor, info, count, object) bind(c, name='mach_vm_region') result(status)
            import
            integer(c_int), value :: task, flavor
            integer(c_int64_t), intent(inout) :: address
            integer(c_int64_t), intent(out) :: length
            integer(c_int), intent(out) :: info(*)
            integer(c_int), intent(inout) :: count
            integer(c_int), intent(out) :: object
            integer(c_int) :: status
        end function
        function mach_port_release(task, port) bind(c, name='mach_port_deallocate') result(status)
            import
            integer(c_int), value :: task, port
            integer(c_int) :: status
        end function
        function mach_allocate(task, address, length, flags) bind(c, name='mach_vm_allocate') result(status)
            import
            integer(c_int), value :: task, flags
            integer(c_int64_t), intent(inout) :: address
            integer(c_int64_t), value :: length
            integer(c_int) :: status
        end function
        function mach_protect(task, address, length, maximum, protection) bind(c, name='mach_vm_protect') result(status)
            import
            integer(c_int), value :: task, maximum, protection
            integer(c_int64_t), value :: address, length
            integer(c_int) :: status
        end function
#else
        function process_id() bind(c, name='getpid') result(pid)
            import
            integer(c_int) :: pid
        end function
        function process_read(pid, local, local_count, remote, remote_count, flags) &
            bind(c, name='process_vm_readv') result(transferred)
            import
            integer(c_int), value :: pid
            type(io_vector), intent(in) :: local, remote
            integer(c_size_t), value :: local_count, remote_count, flags
            integer(c_intptr_t) :: transferred
        end function
        function iterate_elf(callback, context) bind(c, name='dl_iterate_phdr') result(status)
            import
            type(c_funptr), value :: callback
            type(c_ptr), value :: context
            integer(c_int) :: status
        end function
#endif
#endif
    end interface

contains

    integer(c_int) function platform_architecture() bind(c, name='fl_native_arch') result(architecture)
#if defined(FL_ARCH_ARM64)
        architecture = arm64
#elif defined(FL_ARCH_X64)
        architecture = x64
#else
#error Unsupported architecture
#endif
    end function

    integer(c_int) function platform_abi() bind(c, name='fl_native_abi') result(abi)
#ifdef FL_OS_WINDOWS
        abi = 1
#else
        abi = 0
#endif
    end function

    function resolve_symbol(name) bind(c, name='fl_symbol') result(pointer)
        character(c_char), intent(in) :: name(*)
        type(c_ptr) :: pointer
#ifdef FL_OS_WINDOWS
        type(c_ptr) :: module
        character(c_char), target :: lib_name(8), lib32_name(10)
        lib_name = [character(c_char) :: 'i', 'd', 'a', '.', 'd', 'l', 'l', c_null_char]
        lib32_name = [character(c_char) :: 'i', 'd', 'a', '3', '2', '.', 'd', 'l', 'l', c_null_char]
        module = get_module_handle(c_loc(lib_name))
        pointer = c_null_ptr
        if (c_associated(module)) pointer = get_proc_address(module, name)
        if (c_associated(pointer)) return
        module = get_module_handle(c_loc(lib32_name))
        if (c_associated(module)) pointer = get_proc_address(module, name)
        if (c_associated(pointer)) return
        module = get_module_handle(c_null_ptr)
        if (c_associated(module)) pointer = get_proc_address(module, name)
#elif defined(FL_OS_MACOS)
        pointer = dynamic_symbol(transfer(-2_c_intptr_t, c_null_ptr), name)
#else
        pointer = dynamic_symbol(c_null_ptr, name)
#endif
    end function

    integer(c_int) function read_process_memory(address, output, length) bind(c, name='fl_read') result(success)
        integer(c_int64_t), value :: address
        type(c_ptr), value :: output
        integer(c_size_t), value :: length
#if defined(FL_OS_WINDOWS) || defined(FL_OS_MACOS)
        integer(c_int64_t) :: transferred
        integer(c_int) :: status
#else
        type(io_vector) :: local, remote
        integer(c_intptr_t) :: transferred
#endif
        success = 0
        if (address <= 0 .or. length <= 0 .or. .not. c_associated(output)) return
        if (address > huge(address) - length) return
#ifdef FL_OS_WINDOWS
        status = windows_read(get_current_process(), address, output, length, transferred)
        if (status /= 0 .and. transferred == length) success = 1
#elif defined(FL_OS_MACOS)
        status = mach_read(task_self(), address, length, output, transferred)
        if (status == 0 .and. transferred == length) success = 1
#else
        local = io_vector(output, length)
        remote = io_vector(transfer(address, c_null_ptr), length)
        transferred = process_read(process_id(), local, 1_c_size_t, remote, 1_c_size_t, 0_c_size_t)
        if (transferred == length) success = 1
#endif
    end function

    logical function query_mapping(address, mapping) result(found)
        integer(c_intptr_t), intent(in) :: address
        type(memory_mapping), intent(out) :: mapping
#ifdef FL_OS_WINDOWS
        type(windows_mapping) :: info
        integer(c_size_t) :: transferred
#elif defined(FL_OS_MACOS)
        integer(c_int64_t) :: first, length
        integer(c_int) :: info(16), count, object, status, ignored
#else
        integer :: unit, status, hyphen, separator
        integer(c_intptr_t) :: first, limit
        character(4096) :: line
        character(4) :: permissions
#endif
        found = .false.
        mapping = memory_mapping()
        if (address <= 0) return
#ifdef FL_OS_WINDOWS
        transferred = virtual_query(address, info, c_sizeof(info))
        if (transferred /= c_sizeof(info) .or. info%state /= int(z'1000', c_int)) return
        if (iand(info%protection, int(z'101', c_int)) /= 0) return ! Guard/no-access.
        if (info%base > huge(address) - info%size) return
        mapping = memory_mapping(info%base, info%base + info%size, info%protection)
#elif defined(FL_OS_MACOS)
        first = address
        count = size(info)
        object = 0
        status = mach_region(task_self(), first, length, 9_c_int, info, count, object)
        if (object /= 0) ignored = mach_port_release(task_self(), object)
        if (status /= 0 .or. first > address .or. length <= 0) return
        if (first > huge(address) - length) return
        mapping = memory_mapping(first, first + length, info(1))
#else
        open (newunit=unit, file='/proc/self/maps', status='old', action='read', iostat=status)
        if (status /= 0) return
        do
            read (unit, '(a)', iostat=status) line
            if (status /= 0) exit
            hyphen = index(line, '-')
            separator = index(line, ' ')
            if (hyphen <= 1 .or. separator <= hyphen + 1) cycle
            read (line(:hyphen - 1), '(z16)', iostat=status) first
            if (status /= 0) cycle
            read (line(hyphen + 1:separator - 1), '(z16)', iostat=status) limit
            if (status /= 0) cycle
            if (address < first .or. address >= limit) cycle
            permissions = adjustl(line(separator:))
            mapping = memory_mapping(first, limit, 0)
            if (permissions(1:1) == 'r') mapping%protection = ibset(mapping%protection, 0)
            if (permissions(2:2) == 'w') mapping%protection = ibset(mapping%protection, 1)
            if (permissions(3:3) == 'x') mapping%protection = ibset(mapping%protection, 2)
            found = .true.
            exit
        end do
        close (unit)
        return
#endif
        found = .true.
    end function

    logical function readable(protection) result(allowed)
        integer(c_int), intent(in) :: protection
#ifdef FL_OS_WINDOWS
        select case (iand(protection, 255))
        case (2, 4, 8, 32, 64, 128)
            allowed = .true.
        case default
            allowed = .false.
        end select
#else
        allowed = btest(protection, 0)
#endif
    end function

    logical function executable(protection) result(allowed)
        integer(c_int), intent(in) :: protection
#ifdef FL_OS_WINDOWS
        allowed = iand(protection, 240) /= 0
#else
        allowed = btest(protection, 2)
#endif
    end function

    subroutine capture_range(builder, address, length, is_executable)
        type(snapshot_builder), intent(inout) :: builder
        integer(c_intptr_t), intent(in) :: address, length
        logical, intent(in) :: is_executable
        type(memory_mapping) :: mapping
        type(region), pointer :: regions(:)
        integer(c_int8_t), pointer :: copy(:)
        integer(c_intptr_t) :: cursor, limit, chunk_size
        integer :: status

        if (builder%failed /= 0) return
        builder%failed = 1
        if (address <= 0 .or. length <= 0 .or. address > huge(address) - length) return
        call c_f_pointer(builder%storage, regions, [region_limit])
        cursor = address
        limit = address + length
        do while (cursor < limit)
            if (.not. query_mapping(cursor, mapping)) return
            if (.not. readable(mapping%protection)) return
            if (is_executable .and. .not. executable(mapping%protection)) return
            chunk_size = min(mapping%limit, limit) - cursor
            if (chunk_size <= 0 .or. builder%count == region_limit) return
            if (chunk_size > snapshot_limit - builder%total) return
            allocate (copy(chunk_size), stat=status)
            if (status /= 0) return
            if (read_process_memory(cursor, c_loc(copy), chunk_size) == 0) then
                deallocate (copy)
                return
            end if
            builder%count = builder%count + 1
            regions(builder%count) = region(cursor, chunk_size, c_loc(copy), merge(1, 0, is_executable), 0)
            nullify (copy) ! Ownership transferred to the snapshot.
            builder%total = builder%total + chunk_size
            cursor = cursor + chunk_size
        end do
        builder%failed = 0
    end subroutine

    integer(c_int) function capture_snapshot(memory, count) bind(c, name='fl_snapshot') result(success)
        type(c_ptr), intent(out) :: memory
        integer(c_int), intent(out) :: count
        type(snapshot_builder), target :: builder
        type(region), pointer :: regions(:)
        integer :: allocation_status
#ifdef FL_OS_LINUX
        integer(c_int) :: ignored
#endif

        success = 0
        memory = c_null_ptr
        count = 0
        builder = snapshot_builder(c_null_ptr, 0_c_int64_t, 0_c_int64_t, 0, 0)
        builder%anchor = transfer(resolve_symbol('has_valid_add_on'//c_null_char), builder%anchor)
        if (builder%anchor == 0) builder%anchor = transfer(resolve_symbol('is_license_valid'//c_null_char), builder%anchor)
        if (builder%anchor == 0) builder%anchor = transfer(resolve_symbol('get_license_manager'//c_null_char), builder%anchor)
        if (builder%anchor == 0) builder%anchor = transfer(resolve_symbol('msg'//c_null_char), builder%anchor)
        if (builder%anchor <= 0) return
        allocate (regions(region_limit), stat=allocation_status)
        if (allocation_status /= 0) return
        builder%storage = c_loc(regions)
#ifdef FL_OS_WINDOWS
        call capture_pe_image(builder)
#elif defined(FL_OS_MACOS)
        call capture_macho_image(builder)
#else
        ignored = iterate_elf(c_funloc(capture_elf_image), c_loc(builder))
#endif
        if (builder%failed /= 0 .or. builder%count == 0) then
            call free_snapshot(builder%storage, builder%count)
            return
        end if
        memory = builder%storage
        count = builder%count
        success = 1
    end function

    subroutine free_snapshot(memory, count) bind(c, name='fl_snapshot_free')
        type(c_ptr), value :: memory
        integer(c_int), value :: count
        type(region), pointer :: regions(:)
        integer(c_int8_t), pointer :: bytes(:)
        integer :: index

        if (.not. c_associated(memory)) return
        call c_f_pointer(memory, regions, [region_limit])
        do index = 1, count
            call c_f_pointer(regions(index)%bytes, bytes, [regions(index)%size])
            deallocate (bytes)
        end do
        deallocate (regions)
    end subroutine

#ifdef FL_OS_WINDOWS
    subroutine capture_pe_image(builder)
        type(snapshot_builder), intent(inout) :: builder
        type(c_ptr) :: module
        integer(c_int8_t), target :: dos(64), nt(88), section(40)
        integer(c_int64_t) :: base, pe_offset, image_size, section_address, section_size, flags
        integer :: sections, optional_size, index

        builder%failed = 1
        if (get_module_for_address(6_c_int, builder%anchor, module) == 0) return
        base = transfer(module, base)
        if (read_process_memory(base, c_loc(dos), 64_c_size_t) == 0) return
        if (load_le(dos, 2) /= int(z'5A4D', c_int64_t)) return
        pe_offset = load_le(dos(61:), 4)
        if (pe_offset > 1048576) return
        if (read_process_memory(base + pe_offset, c_loc(nt), 88_c_size_t) == 0) return
        if (load_le(nt, 4) /= int(z'4550', c_int64_t) .or. load_le(nt(25:), 2) /= 523) return
        sections = int(load_le(nt(7:), 2))
        optional_size = int(load_le(nt(21:), 2))
        image_size = load_le(nt(81:), 4)
        if (sections > 96 .or. optional_size < 64) return
        builder%failed = 0
        do index = 0, sections - 1
            section_address = base + pe_offset + 24 + optional_size + 40*index
            if (read_process_memory(section_address, c_loc(section), 40_c_size_t) == 0) exit
            section_address = load_le(section(13:), 4)
            section_size = load_le(section(9:), 4)
            flags = load_le(section(37:), 4)
            if (section_address > image_size .or. section_size > image_size - section_address) exit
            if (btest(flags, 30) .and. section_size > 0) then
                call capture_range(builder, base + section_address, section_size, btest(flags, 29))
                if (builder%failed /= 0) return
            end if
        end do
        if (index /= sections) builder%failed = 1
    end subroutine
#elif defined(FL_OS_MACOS)
    subroutine capture_macho_image(builder)
        type(snapshot_builder), intent(inout) :: builder
        type(dynamic_symbol_info) :: info
        integer(c_int8_t), target :: header(32)
        integer(c_int8_t), allocatable, target :: commands(:)
        integer(c_int64_t) :: base, command_size, offset, size, slide, address, length, flags
        integer :: command_count, index, pass, allocation_status
        logical :: found

        builder%failed = 1
        if (symbol_info(builder%anchor, info) == 0) return
        base = transfer(info%module_base, base)
        if (read_process_memory(base, c_loc(header), 32_c_size_t) == 0) return
        if (load_le(header, 4) /= int(z'FEEDFACF', c_int64_t)) return
        command_count = int(load_le(header(17:), 4))
        command_size = load_le(header(21:), 4)
        if (command_size < 8 .or. command_size > 16777216 .or. command_count > command_size/8) return
        allocate (commands(command_size), stat=allocation_status)
        if (allocation_status /= 0) return
        if (read_process_memory(base + 32, c_loc(commands), command_size) == 0) return
        slide = 0
        found = .false.
        do pass = 0, 1
            offset = 0
            do index = 1, command_count
                if (offset > command_size - 8) return
                size = load_le(commands(offset + 5:), 4)
                if (size < 8 .or. size > command_size - offset) return
                if (load_le(commands(offset + 1:), 4) == 25 .and. size >= 72) then
                    if (pass == 0 .and. load_le(commands(offset + 9:), 8) == int(z'0000545845545F5F', c_int64_t)) then
                        slide = base - load_le(commands(offset + 25:), 8)
                        found = .true.
                    end if
                    if (pass == 1) then
                        if (.not. found) return
                        address = load_le(commands(offset + 25:), 8) + slide
                        length = load_le(commands(offset + 49:), 8)
                        flags = load_le(commands(offset + 61:), 4)
                        if (btest(flags, 0) .and. length > 0) then
                            builder%failed = 0
                            call capture_range(builder, address, length, btest(flags, 2))
                            if (builder%failed /= 0) return
                            builder%failed = 1
                        end if
                    end if
                end if
                offset = offset + size
            end do
        end do
        if (found) builder%failed = 0
    end subroutine
#else
    integer(c_int) function capture_elf_image(memory, length, context) bind(c) result(stop)
        type(c_ptr), value :: memory, context
        integer(c_size_t), value :: length
        type(elf_loader_info), pointer :: info
        type(elf_program_header), pointer :: headers(:)
        type(snapshot_builder), pointer :: builder
        integer(c_int64_t) :: address
        integer :: index, count
        logical :: found

        stop = 0
        if (length < 26) return
        call c_f_pointer(memory, info)
        call c_f_pointer(context, builder)
        count = iand(int(info%header_count), 65535)
        call c_f_pointer(info%headers, headers, [count])
        found = .false.
        do index = 1, count
            if (headers(index)%kind /= 1) cycle
            address = info%load_bias + headers(index)%address
            if (builder%anchor >= address .and. builder%anchor - address < headers(index)%memory_size) found = .true.
        end do
        if (.not. found) return
        stop = 1
        do index = 1, count
            if (headers(index)%kind /= 1 .or. .not. btest(headers(index)%flags, 2)) cycle
            if (headers(index)%file_size == 0) cycle
            call capture_range(builder, info%load_bias + headers(index)%address, &
                               headers(index)%file_size, btest(headers(index)%flags, 0))
            if (builder%failed /= 0) return
        end do
    end function
#endif

    integer(c_size_t) function page_size() result(length)
#ifdef FL_OS_WINDOWS
        type(windows_system_info) :: info
        call get_system_info(info)
        length = int(info%page_size, c_size_t)
#else
        length = int(get_page_size(), c_size_t)
#endif
    end function

    function allocate_nearby(target, length) bind(c, name='fl_allocate_near') result(memory)
        integer(c_int64_t), value :: target
        integer(c_size_t), value :: length
        type(c_ptr) :: memory
        integer(c_int64_t) :: reach, step, aligned, delta, hint, allocated
        integer :: direction
#ifdef FL_OS_WINDOWS
        type(windows_system_info) :: info
#endif
        memory = c_null_ptr
        if (target <= 0 .or. length <= 0 .or. length > 1048576) return
        reach = merge(int(z'07000000', c_int64_t), int(z'70000000', c_int64_t), platform_architecture() == arm64)
        step = max(65536_c_int64_t, page_size())
#ifdef FL_OS_WINDOWS
        call get_system_info(info)
        step = max(step, int(info%allocation_granularity, c_int64_t))
#endif
        aligned = iand(target, not(step - 1))
        do delta = step, reach - step, step
            do direction = -1, 1, 2
                if (direction < 0 .and. aligned <= delta) cycle
                if (direction > 0 .and. aligned > huge(target) - delta) cycle
                hint = aligned + direction*delta
#ifdef FL_OS_WINDOWS
                memory = virtual_allocate(hint, length, int(z'3000', c_int), 4_c_int)
#elif defined(FL_OS_MACOS)
                allocated = hint
                if (mach_allocate(task_self(), allocated, length, 0_c_int) == 0) then
                    memory = transfer(allocated, c_null_ptr)
                else
                    memory = c_null_ptr
                end if
#else
                memory = memory_map(hint, length, 3_c_int, 34_c_int, -1_c_int, 0_c_int64_t)
                if (transfer(memory, hint) == -1) memory = c_null_ptr
#endif
                if (.not. c_associated(memory)) cycle
                allocated = transfer(memory, allocated)
                if (allocated > 0 .and. abs(allocated - target) < reach) return
                call release_allocation(memory, length)
                memory = c_null_ptr
            end do
        end do
    end function

    integer(c_int) function seal_allocation(memory, length) bind(c, name='fl_seal') result(success)
        type(c_ptr), value :: memory
        integer(c_size_t), value :: length
        integer(c_intptr_t) :: address
        integer(c_int) :: status
#ifdef FL_OS_WINDOWS
        integer(c_int) :: previous
#endif
        success = 0
        address = transfer(memory, address)
#ifdef FL_OS_WINDOWS
        status = virtual_protect(address, length, 32_c_int, previous)
        if (status /= 0) success = 1
#else
        status = memory_protect(address, length, 5_c_int)
        if (status == 0) success = 1
#endif
        if (success /= 0) success = flush_code(memory, length)
    end function

    subroutine release_allocation(memory, length) bind(c, name='fl_release')
        type(c_ptr), value :: memory
        integer(c_size_t), value :: length
        integer(c_int) :: ignored
#ifdef FL_OS_WINDOWS
        ignored = virtual_release(memory, 0_c_size_t, int(z'8000', c_int))
#else
        ignored = memory_unmap(memory, length)
#endif
    end subroutine

    logical function set_protection(address, length, protection, writable) result(success)
        integer(c_intptr_t), intent(in) :: address
        integer(c_size_t), intent(in) :: length
        integer(c_int), intent(in) :: protection
        logical, intent(in) :: writable
        integer(c_int) :: desired, status
#ifdef FL_OS_WINDOWS
        integer(c_int) :: previous
        desired = merge(64_c_int, protection, writable)
        status = virtual_protect(address, length, desired, previous)
        success = status /= 0
#elif defined(FL_OS_MACOS)
        desired = merge(19_c_int, protection, writable) ! READ|WRITE|COPY; execute restored after writing.
        status = mach_protect(task_self(), address, length, 0_c_int, desired)
        success = status == 0
#else
        desired = merge(7_c_int, protection, writable)
        status = memory_protect(address, length, desired)
        success = status == 0
#endif
    end function

    logical function restore_protections() result(restored)
        integer :: index

        restored = .true.
        do index = recovery_count, 1, -1
            if (.not. set_protection(recovery_pages(index), recovery_page_size, &
                                     recovery_mappings(index)%protection, .false.)) restored = .false.
        end do
        if (restored) recovery_count = 0
    end function

    integer(c_int) function exchange_bytes(address, expected, replacement, length) bind(c, name='fl_exchange') result(status)
        integer(c_int64_t), value :: address
        type(c_ptr), value :: expected, replacement
        integer(c_size_t), value :: length
        integer(c_int8_t), target :: original(64)
        integer(c_int8_t), pointer :: expected_bytes(:), replacement_bytes(:), destination(:)
        type(memory_mapping) :: mappings(2)
        integer(c_intptr_t) :: pages(2)
        integer(c_size_t) :: granularity
        integer :: count, index, changed
        logical :: identical

        status = 0
        if (.not. restore_protections()) then
            status = -1
            return
        end if
        granularity = page_size()
        if (granularity <= 0 .or. length <= 0 .or. length > size(original)) return
        if (address <= 0 .or. address > huge(address) - length) return
        if (.not. c_associated(expected) .or. .not. c_associated(replacement)) return
        pages(1) = iand(address, not(granularity - 1))
        pages(2) = iand(address + length - 1, not(granularity - 1))
        count = merge(1, 2, pages(1) == pages(2))
        do index = 1, count
            if (.not. query_mapping(pages(index), mappings(index))) return
            if (.not. readable(mappings(index)%protection) .or. &
                .not. executable(mappings(index)%protection)) return
        end do
        if (read_process_memory(address, c_loc(original), length) == 0) return
        call c_f_pointer(expected, expected_bytes, [length])
        call c_f_pointer(replacement, replacement_bytes, [length])
        if (any(original(:length) /= expected_bytes)) return

        changed = 0
        do index = 1, count
            if (.not. set_protection(pages(index), granularity, mappings(index)%protection, .true.)) exit
            changed = changed + 1
        end do
        if (changed == count) then
            ! The lifecycle caller supplies quiescence. The mutex serializes
            ! us, not the host's worker threads; the distinction is load-bearing.
            call c_f_pointer(transfer(address, c_null_ptr), destination, [length])
            identical = all(destination == expected_bytes)
            if (identical) then
                destination = replacement_bytes
                status = merge(1, -1, flush_code(c_loc(destination), length) /= 0)
            end if
        end if
        recovery_mappings = mappings
        recovery_pages = pages
        recovery_page_size = granularity
        recovery_count = changed
        if (.not. restore_protections()) status = -1
    end function

end module fl_platform
