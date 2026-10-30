#ifndef FL_CORE_BI
#define FL_CORE_BI
declare function memcpy cdecl alias "memcpy"(byval destination as any ptr, byval source as const any ptr, byval length as ulongint) as any ptr
declare function memcmp cdecl alias "memcmp"(byval lhs as const any ptr, byval rhs as const any ptr, byval length as ulongint) as long
type decoder_state
    architecture as long
end type
type x86_operands
    mode as long
    group as long
    destination as long
    source as long
    base as long
    index as long
    displacement_offset as long
    displacement_size as long
    displacement as longint
    rip_relative as long
end type
type memory_mapping
    first as longint
    limit as longint
    protection as long
end type
type snapshot_builder
    storage as any ptr
    total as longint
    anchor as longint
    count as long
    failed as long
end type
type windows_mapping
    base as longint
    allocation_base as longint
    allocation_protection as long
    partition_and_padding as long
    size as ulongint
    state as long
    protection as long
    kind as long
    padding as long
end type
type windows_system_info
    architecture_and_reserved as long
    page_size as long
    minimum_address as longint
    maximum_address as longint
    active_processor_mask as longint
    processors as long
    processor_type as long
    allocation_granularity as long
    processor_level as short
    processor_revision as short
end type
type dynamic_symbol_info
    filename as any ptr
    module_base as any ptr
    symbol_name as any ptr
    symbol_address as any ptr
end type
type io_vector
    base as any ptr
    length as ulongint
end type
type elf_program_header
    kind as long
    flags as long
    offset as longint
    address as longint
    physical_address as longint
    file_size as longint
    memory_size as longint
    alignment as longint
end type
type elf_loader_info
    load_bias as longint
    name as any ptr
    headers as any ptr
    header_count as short
end type
type instruction
    address as longint
    target as longint
    immediate as longint
    writes as longint
    size as long
    kind as long
    dst as long
    src as long
    base as long
    index as long
    displacement_offset as long
    displacement_size as long
    relative as long
    unsafe as long
end type
type region
    address as longint
    size as longint
    bytes as any ptr
    executable as long
    reserved as long
end type
type result
    target as longint
    status as long
    candidates as long
    references as long
    reason as long
end type
declare function f_address_sum cdecl(byval v_address as longint, byval v_displacement as longint) as longint
declare function f_byte_value cdecl(byval v_b as byte) as longint
declare function f_byte_at cdecl(byval v_value as longint) as byte
declare function f_load_le cdecl(byval v_bytes as byte ptr, byval n_bytes as longint, byval v_count as long) as longint
declare sub f_store_le cdecl(byval v_bytes as byte ptr, byval n_bytes as longint, byval v_value as longint, byval v_count as long)
declare function f_signed_field cdecl(byval v_value as longint, byval v_bits as long) as longint
declare function f_fits_signed cdecl(byval v_value as longint, byval v_bits as long) as long
declare function fl_decoder_open cdecl alias "fl_decoder_open"(byval v_architecture as long) as any ptr
declare sub fl_decoder_close cdecl alias "fl_decoder_close"(byval v_handle as any ptr)
declare function fl_decode cdecl alias "fl_decode"(byval v_handle as any ptr, byval v_memory as any ptr, byval v_length as ulongint, byval v_address as longint, byref v_decoded as instruction) as long
declare sub f_mark_write cdecl(byref v_decoded as instruction, byval v_register as long)
declare function f_consume cdecl(byval v_bytes as byte ptr, byval n_bytes as longint, byref v_position as long, byval v_width as long, byref v_value as longint) as long
declare function f_modrm cdecl(byval v_bytes as byte ptr, byval n_bytes as longint, byref v_position as long, byval v_rex as long, byref v_operands as x86_operands) as long
declare function f_byte_register cdecl(byval v_register as long, byval v_rex as long) as long
declare function f_decode_x86 cdecl(byval v_bytes as byte ptr, byval n_bytes as longint, byref v_decoded as instruction) as long
declare function f_decode_arm64 cdecl(byval v_bytes as byte ptr, byval n_bytes as longint, byref v_decoded as instruction) as long
declare function f_view cdecl(byval v_regions as region ptr, byval n_regions as longint, byval v_address as longint, byval v_length as longint, byval v_executable_only as long) as any ptr
declare function f_pointer_at cdecl(byval v_regions as region ptr, byval n_regions as longint, byval v_address as longint) as longint
declare function f_is_target cdecl(byval v_regions as region ptr, byval n_regions as longint, byval v_address as longint) as long
declare function f_instruction_at cdecl(byval v_decoder as any ptr, byval v_regions as region ptr, byval n_regions as longint, byval v_address as longint, byref v_decoded as instruction) as long
declare function f_resolve cdecl(byval v_decoder as any ptr, byval v_regions as region ptr, byval n_regions as longint, byval v_address as longint) as longint
declare function f_calls_license cdecl(byval v_decoder as any ptr, byval v_regions as region ptr, byval n_regions as longint, byval v_address as longint, byval v_license as longint) as long
declare sub f_collect_calls cdecl(byval v_decoder as any ptr, byval v_regions as region ptr, byval n_regions as longint, byval v_address as longint, byval v_callees as longint ptr, byval n_callees as longint, byref v_count as long, byref v_complete as long)
declare sub fl_analyze cdecl alias "fl_analyze"(byval v_arch as long, byval v_abi as long, byval v_regions as region ptr, byval v_count as long, byval v_exported as longint, byval v_license as longint, byref v_out as result)
declare function fl_plan cdecl alias "fl_plan"(byval v_arch as long, byval v_abi as long, byval v_input as byte ptr, byval v_input_size as ulongint, byval v_address as longint, byval v_trampoline as longint, byval v_output as byte ptr, byref v_code_size as long, byval v_patch as byte ptr, byref v_patch_size as long) as long
declare function fl_flush_code cdecl alias "fl_flush_code"(byval v_memory as any ptr, byval v_length as ulongint) as long
declare function GetModuleHandleA cdecl alias "GetModuleHandleA"(byval v_name as any ptr) as any ptr
declare function GetProcAddress cdecl alias "GetProcAddress"(byval v_handle as any ptr, byval v_name as zstring ptr) as any ptr
declare function GetModuleHandleExA cdecl alias "GetModuleHandleExA"(byval v_flags as long, byval v_address as longint, byref v_handle as any ptr) as long
declare function GetCurrentProcess cdecl alias "GetCurrentProcess"() as any ptr
declare function ReadProcessMemory cdecl alias "ReadProcessMemory"(byval v_handle as any ptr, byval v_address as longint, byval v_output as any ptr, byval v_length as ulongint, byref v_transferred as ulongint) as long
declare function VirtualQuery cdecl alias "VirtualQuery"(byval v_address as longint, byref v_output as windows_mapping, byval v_length as ulongint) as ulongint
declare sub GetSystemInfo cdecl alias "GetSystemInfo"(byref v_output as windows_system_info)
declare function VirtualAlloc cdecl alias "VirtualAlloc"(byval v_address as longint, byval v_length as ulongint, byval v_kind as long, byval v_protection as long) as any ptr
declare function VirtualFree cdecl alias "VirtualFree"(byval v_memory as any ptr, byval v_length as ulongint, byval v_kind as long) as long
declare function VirtualProtect cdecl alias "VirtualProtect"(byval v_address as longint, byval v_length as ulongint, byval v_protection as long, byref v_previous as long) as long
declare function dlsym cdecl alias "dlsym"(byval v_handle as any ptr, byval v_name as zstring ptr) as any ptr
declare function dladdr cdecl alias "dladdr"(byval v_address as longint, byref v_output as dynamic_symbol_info) as long
declare function getpagesize cdecl alias "getpagesize"() as long
declare function mmap cdecl alias "mmap"(byval v_address as longint, byval v_length as ulongint, byval v_protection as long, byval v_flags as long, byval v_descriptor as long, byval v_offset as longint) as any ptr
declare function munmap cdecl alias "munmap"(byval v_memory as any ptr, byval v_length as ulongint) as long
declare function mprotect cdecl alias "mprotect"(byval v_address as longint, byval v_length as ulongint, byval v_protection as long) as long
declare function fl_task_self cdecl alias "fl_task_self"() as long
declare function mach_vm_read_overwrite cdecl alias "mach_vm_read_overwrite"(byval v_task as long, byval v_address as longint, byval v_length as longint, byval v_output as any ptr, byref v_transferred as longint) as long
declare function mach_vm_region cdecl alias "mach_vm_region"(byval v_task as long, byref v_address as longint, byref v_length as longint, byval v_flavor as long, byval v_info as long ptr, byref v_count as long, byref v_object as long) as long
declare function mach_port_deallocate cdecl alias "mach_port_deallocate"(byval v_task as long, byval v_port as long) as long
declare function mach_vm_allocate cdecl alias "mach_vm_allocate"(byval v_task as long, byref v_address as longint, byval v_length as longint, byval v_flags as long) as long
declare function mach_vm_protect cdecl alias "mach_vm_protect"(byval v_task as long, byval v_address as longint, byval v_length as longint, byval v_maximum as long, byval v_protection as long) as long
declare function getpid cdecl alias "getpid"() as long
declare function process_vm_readv cdecl alias "process_vm_readv"(byval v_pid as long, byref v_local as io_vector, byval v_local_count as ulongint, byref v_remote as io_vector, byval v_remote_count as ulongint, byval v_flags as ulongint) as longint
declare function dl_iterate_phdr cdecl alias "dl_iterate_phdr"(byval v_callback as any ptr, byval v_context as any ptr) as long
declare function fl_native_arch cdecl alias "fl_native_arch"() as long
declare function fl_native_abi cdecl alias "fl_native_abi"() as long
declare function fl_symbol cdecl alias "fl_symbol"(byval v_name as zstring ptr) as any ptr
declare function fl_read cdecl alias "fl_read"(byval v_address as longint, byval v_output as any ptr, byval v_length as ulongint) as long
declare function f_query_mapping cdecl(byval v_address as longint, byref v_mapping as memory_mapping) as long
declare function f_readable cdecl(byval v_protection as long) as long
declare function f_executable cdecl(byval v_protection as long) as long
declare sub f_capture_range cdecl(byref v_builder as snapshot_builder, byval v_address as longint, byval v_length as longint, byval v_is_executable as long)
declare function fl_snapshot cdecl alias "fl_snapshot"(byref v_memory as any ptr, byref v_count as long) as long
declare sub fl_snapshot_free cdecl alias "fl_snapshot_free"(byval v_memory as any ptr, byval v_count as long)
declare sub f_capture_pe_image cdecl(byref v_builder as snapshot_builder)
declare sub f_capture_macho_image cdecl(byref v_builder as snapshot_builder)
declare function f_capture_elf_image cdecl(byval v_memory as any ptr, byval v_length as ulongint, byval v_context as any ptr) as long
declare function f_page_size cdecl() as long
declare function fl_allocate_near cdecl alias "fl_allocate_near"(byval v_target as longint, byval v_length as ulongint) as any ptr
declare function fl_seal cdecl alias "fl_seal"(byval v_memory as any ptr, byval v_length as ulongint) as long
declare sub fl_release cdecl alias "fl_release"(byval v_memory as any ptr, byval v_length as ulongint)
declare function f_set_protection cdecl(byval v_address as longint, byval v_length as ulongint, byval v_protection as long, byval v_writable as long) as long
declare function f_restore_protections cdecl() as long
declare function fl_exchange cdecl alias "fl_exchange"(byval v_address as longint, byval v_expected as any ptr, byval v_replacement as any ptr, byval v_length as ulongint) as long
declare function fl_basic_start cdecl alias "fl_basic_start"() as long
declare function fl_basic_stop cdecl alias "fl_basic_stop"() as long
declare sub fl_log cdecl alias "fl_log"(byval message as zstring ptr)
declare function fl_contains(byval values as longint ptr, byval count as longint, byval value as longint) as long
#define fl_min(a,b) iif((a)<(b),(a),(b))
#define fl_max(a,b) iif((a)>(b),(a),(b))
declare function fl_mask(byval bits as long) as ulongint
declare function fl_bits(byval value as ulongint, byval first as long, byval count as long) as longint
declare function fopen cdecl alias "fopen"(byval path as zstring ptr, byval mode as zstring ptr) as any ptr
declare function fgets cdecl alias "fgets"(byval buffer as zstring ptr, byval count as long, byval stream as any ptr) as zstring ptr
declare function fclose cdecl alias "fclose"(byval stream as any ptr) as long
declare function sscanf cdecl alias "sscanf"(byval buffer as zstring ptr, byval format as zstring ptr, ...) as long
#assert sizeof(instruction) = 72
#assert sizeof(region) = 32
#assert sizeof(result) = 24
#assert sizeof(windows_mapping) = 48
#assert sizeof(windows_system_info) = 48
#endif
