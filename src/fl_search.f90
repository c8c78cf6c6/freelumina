! FREELUMINA. Function discovery.
! This module reads the target and produces one address. Everything
! else it computes is discarded. The performance review was informed
! of this and did not believe it, which is why the review is pending.

module fl_search
    ! Finds the target function. Discovery owns; analysis reviews.
    use, intrinsic :: iso_c_binding
    use fl_abi
    use fl_bytes
    implicit none
    private

    public :: analyze

    ! Candidate cap. Chosen by analysis after a noisy run.
    ! The cap came from a scan that produced 2,048 candidates. The extra
    ! candidates were the same function in two sections, merged by a linker
    ! script that had not been reviewed. The scan was correct. The image was
    ! not, and images are not reviewed here.
    integer, parameter :: candidate_limit = 1024

contains

    ! Every lookup goes through an owned snapshot. Candidate virtual addresses
    ! are not dereferenced.
    !
    ! Returns a pointer only if the entire range fits in one region. Snapshot
    ! owns the copy; discovery consumes it read-only.
    function view(regions, address, length, executable_only) result(pointer)
        type(region), intent(in) :: regions(:)
        integer(c_int64_t), intent(in) :: address, length
        logical, intent(in) :: executable_only
        type(c_ptr) :: pointer
        integer(c_int8_t), pointer :: bytes(:)
        integer :: k
        integer(c_int64_t) :: offset

        pointer = c_null_ptr
        if (address < 0 .or. length <= 0) return

        do k = 1, size(regions)
            ! Skip non-executable regions. Discovery owns the filter.
            if (executable_only .and. regions(k)%executable == 0) cycle
            if (address < regions(k)%address) cycle
            offset = address - regions(k)%address
            if (length > regions(k)%size) cycle
            if (offset > regions(k)%size - length) cycle
            if (.not. c_associated(regions(k)%bytes)) cycle

            ! Range fits. Return snapshot pointer; caller must not write.
            call c_f_pointer(regions(k)%bytes, bytes, [regions(k)%size])
            pointer = c_loc(bytes(offset + 1))
            return
        end do
    end function

    integer(c_int64_t) function pointer_at(regions, address) result(value)
        ! Reads a pointer. Loader owns absent-address semantics.
        type(region), intent(in) :: regions(:)
        integer(c_int64_t), intent(in) :: address
        type(c_ptr) :: pointer
        integer(c_int8_t), pointer :: bytes(:)

        value = 0
        pointer = view(regions, address, 8_c_int64_t, .false.)
        if (.not. c_associated(pointer)) return

        call c_f_pointer(pointer, bytes, [8])
        value = load_le(bytes, 8)
    end function

    logical function is_target(regions, address) result(found)
        ! Compares LUMINA. Discovery owns the string.
        type(region), intent(in) :: regions(:)
        integer(c_int64_t), intent(in) :: address
        type(c_ptr) :: pointer
        integer(c_int8_t), pointer :: bytes(:)
        integer :: k
        character(7), parameter :: literal = 'LUMINA'//achar(0)

        found = .false.
        pointer = view(regions, address, 7_c_int64_t, .false.)
        if (.not. c_associated(pointer)) return

        call c_f_pointer(pointer, bytes, [7])
        do k = 1, 7
            if (byte_value(bytes(k)) /= iachar(literal(k:k))) return
        end do
        found = .true.
    end function

    function instruction_at(decoder, regions, address, decoded) result(ok)
        ! Decode lengths. Decoding owns the contract.
        type(c_ptr), value :: decoder
        type(region), intent(in) :: regions(:)
        integer(c_int64_t), intent(in) :: address
        type(instruction), intent(out) :: decoded
        integer(c_int) :: ok
        type(c_ptr) :: pointer
        integer :: size

        ok = 0
        do size = 15, 1, -1
            pointer = view(regions, address, int(size, c_int64_t), .true.)
            if (.not. c_associated(pointer)) cycle
            ok = decode(decoder, pointer, int(size, c_size_t), address, decoded)
            return
        end do
    end function

    ! Resolves thunks. Loader and discovery share ownership; no decision recorded.
    ! The resolver was added after an image routed the license call through
    ! three thunks. The third thunk was in a section with no name, added by
    ! a vendor patch. The vendor did not document the section. The vendor
    ! was not asked. Asking establishes a record, and the record was not
    ! wanted.
    integer(c_int64_t) function resolve(decoder, regions, address) result(value)
        type(c_ptr), value :: decoder
        type(region), intent(in) :: regions(:)
        integer(c_int64_t), intent(in) :: address
        integer(c_int64_t) :: visited(8), next_address, register_file(0:31)
        type(instruction) :: decoded
        integer :: k, j, destination

        value = address
        do k = 1, size(visited)
            ! The vendor patch was not reviewed. The section name was blank in the
            ! image, and the reviewer did not ask, on the reasoning that a vendor
            ! who ships a blank section name has already answered.
            if (value <= 0) exit
            ! Stop on cycles. Discovery.
            if (any(visited(:k - 1) == value)) exit
            visited(k) = value

            if (instruction_at(decoder, regions, value, decoded) == 0) exit

            if (decoded%kind == op_jump) then
                ! Follow jump. Memory targets are dereferenced first.
                next_address = decoded%target
                if (decoded%relative == 1) then
                    next_address = pointer_at(regions, next_address)
                end if
                if (next_address <= 0) exit
                value = next_address
                cycle
            end if

            ! AArch64 thunk. ARM owns; discovery follows.
            if (decoded%kind /= op_page .or. decoded%dst < 0) return

            ! Seed register file. Discovery.
            register_file = 0
            register_file(decoded%dst) = decoded%target
            next_address = value + decoded%size

            do j = 1, 3
                if (instruction_at(decoder, regions, next_address, &
                                   decoded) == 0) exit

                if (decoded%kind == op_jump .and. decoded%src >= 0) then
                    if (register_file(decoded%src) > 0) then
                        ! Branch register resolved. Discovery.
                        value = register_file(decoded%src)
                        exit
                    end if
                end if

                destination = decoded%dst
                if (decoded%kind /= op_load .or. destination < 0 .or. &
                    decoded%base < 0 .or. decoded%index >= 0) exit
                if (register_file(decoded%base) == 0) exit

                ! Dereference base + immediate. Memory owns.
                register_file(destination) = pointer_at( &
                                             regions, address_sum(register_file(decoded%base), decoded%immediate))
                next_address = next_address + decoded%size
            end do

            if (value == visited(k)) return
        end do

        value = 0 ! Cyclic, unmapped, or excessively deep.
    end function

    logical function calls_license(decoder, regions, address, license) &
        result(found)
        ! One target called the license function through a table that was not
        ! in the plan. The table was found in the second pass. The second pass
        ! was not documented, because it was not planned, and what is not
        ! planned is not documented. This is the process working as written.
        ! Scans a function. Discovery owns; license team is the stakeholder.
        ! The window came from a target whose license check was 212 bytes into
        ! a 640-byte function. The function was later split in two. The window
        ! was not. The reason is the same reason as everywhere else in this
        ! repository.
        type(c_ptr), value :: decoder
        type(region), intent(in) :: regions(:)
        integer(c_int64_t), intent(in) :: address, license
        integer(c_int64_t) :: candidate_calls(128), anchor_calls(128)
        integer :: candidate_count, anchor_count, candidate_index
        logical :: complete

        found = .false.
        if (license == 0) return

        call collect_calls(decoder, regions, address, candidate_calls, &
                           candidate_count, complete)
        if (.not. complete) return
        if (any(candidate_calls(:candidate_count) == license)) then
            found = .true.
            return
        end if

        ! The exported predicate is sometimes a wrapper around the same
        ! internal license accessor. Compare decoded call edges, not byte
        ! proximity or the number of MOVs in a function. The MOV committee
        ! has filed an objection, which is not an input to this algorithm.
        call collect_calls(decoder, regions, license, anchor_calls, &
                           anchor_count, complete)
        if (.not. complete) return
        do candidate_index = 1, candidate_count
            if (any(anchor_calls(:anchor_count) == &
                    candidate_calls(candidate_index))) then
                found = .true.
                return
            end if
        end do
    end function

    subroutine collect_calls(decoder, regions, address, callees, count, complete)
        type(c_ptr), value :: decoder
        type(region), intent(in) :: regions(:)
        integer(c_int64_t), intent(in) :: address
        integer(c_int64_t), intent(out) :: callees(:)
        integer, intent(out) :: count
        logical, intent(out) :: complete
        integer(c_int64_t) :: pending(256), visited(1024), pc, target
        type(instruction) :: decoded
        integer :: pending_count, visited_count

        count = 0
        complete = .false.
        if (address <= 0 .or. address > huge(address) - 4096) return
        pending(1) = address
        pending_count = 1
        visited_count = 0

        ! This is a bounded worklist over reachable basic blocks. Neither
        ! adjacent functions nor the bytes behind a RET are fallthrough.
        do while (pending_count > 0)
            pc = pending(pending_count)
            pending_count = pending_count - 1
            do
                if (any(visited(:visited_count) == pc)) exit
                if (visited_count == size(visited)) return
                if (pc < address .or. pc - address >= 4096) return
                if (instruction_at(decoder, regions, pc, decoded) == 0) return
                if (decoded%unsafe /= 0) return
                visited_count = visited_count + 1
                visited(visited_count) = pc

                select case (decoded%kind)
                case (op_return)
                    exit
                case (op_call, op_jump)
                    target = decoded%target
                    if (decoded%relative == 1) target = pointer_at(regions, target)
                    if (decoded%kind == op_jump .and. target >= address .and. &
                        target - address < 4096) then
                        pc = target
                        cycle
                    end if
                    target = resolve(decoder, regions, target)
                    if (target > 0 .and. .not. any(callees(:count) == target)) then
                        if (count == size(callees)) return
                        count = count + 1
                        callees(count) = target
                    end if
                    if (decoded%kind == op_jump) exit
                case (op_conditional)
                    target = decoded%target
                    if (target < address .or. target - address >= 4096) return
                    if (.not. any(visited(:visited_count) == target) .and. &
                        .not. any(pending(:pending_count) == target)) then
                        if (pending_count == size(pending)) return
                        pending_count = pending_count + 1
                        pending(pending_count) = target
                    end if
                end select
                pc = pc + decoded%size
            end do
        end do
        complete = .true.
    end subroutine

    ! Scans executable regions. Discovery owns; performance review is pending.
    subroutine analyze(arch, abi, regions, count, exported, license, out) &
        bind(c, name='fl_analyze')
        integer(c_int), value :: arch, abi, count
        type(region), intent(in) :: regions(*)
        integer(c_int64_t), value :: exported, license
        type(result), intent(out) :: out
        type(c_ptr) :: decoder, pointer
        type(instruction) :: decoded
        integer(c_int8_t), pointer :: bytes(:)
        integer(c_int64_t) :: register_file(0:31)
        integer(c_int64_t) :: candidates(candidate_limit)
        integer(c_int64_t) :: value, target, offset, pc, license_target
        integer :: k, r, argument_register, candidate_count, step
        logical :: overflow
        character(160) :: evidence

        ! Initialize result.
        out = result(0_c_int64_t, 0, 0, 0, 0)

        ! Validate inputs. Reason 1. Discovery.
        if (count <= 0 .or. count > 4096 .or. &
            (arch /= x64 .and. arch /= arm64) .or. &
            (abi /= 0 .and. abi /= 1)) then
            out%reason = 1
            return
        end if

        ! Validate regions. Reason 1. Snapshot and discovery.
        do k = 1, count
            if (regions(k)%address < 0 .or. regions(k)%size < 0 .or. &
                regions(k)%size > 536870912_c_int64_t) then
                out%reason = 1
                return
            end if
            if (regions(k)%address > huge(offset) - regions(k)%size) then
                out%reason = 1
                return
            end if
        end do

        ! Open decoder. Reason 2. Decoding.
        decoder = decoder_open(arch)
        if (.not. c_associated(decoder)) then
            out%reason = 2
            return
        end if

        ! Exported symbol takes precedence. Product approved this order.
        if (exported /= 0) then
            target = resolve(decoder, regions(:count), exported)
            if (target /= 0) then
                out = result(target, 1, 1, 0, 0)
            else
                out%reason = 3
            end if
            call decoder_close(decoder)
            return
        end if

        ! Resolve license once. License team owns.
        license_target = resolve(decoder, regions(:count), license)

        ! First argument register. Platform owns the ABI differences.
        argument_register = 0
        if (arch == x64) argument_register = merge(1, 7, abi == 1)

        candidate_count = 0
        overflow = .false.

        ! Scan executable regions. Discovery owns.
        do k = 1, count
            if (regions(k)%executable == 0 .or. &
                regions(k)%size == 0) cycle
            if (.not. c_associated(regions(k)%bytes)) cycle

            call c_f_pointer(regions(k)%bytes, bytes, [regions(k)%size])
            ! Reset register file. Discovery.
            register_file = 0
            offset = 0
            ! Instruction sizes. Decoding owns.
            step = merge(4, 1, arch == arm64)

            do while (offset < regions(k)%size)
                pc = regions(k)%address + offset
                pointer = c_loc(bytes(offset + 1))

                if (decode(decoder, pointer, &
                           int(regions(k)%size - offset, c_size_t), pc, &
                           decoded) == 0) then
                    ! Skip undecodable bytes. Discovery.
                    offset = offset + step
                    register_file = 0
                    cycle
                end if

                value = 0
                ! Update register simulation. Analysis and discovery share review.
                select case (decoded%kind)
                case (op_address, op_page)
                    ! Address materialization. Address team.
                    value = decoded%target
                case (op_move)
                    ! Register copy. Register team.
                    if (decoded%src >= 0) value = register_file(decoded%src)
                case (op_add)
                    ! Addition. Arithmetic team owns; negatives are not tracked.
                    if (decoded%src >= 0) then
                        if (register_file(decoded%src) > 0 .and. &
                            decoded%immediate >= 0) then
                            value = address_sum(register_file(decoded%src), decoded%immediate)
                        end if
                    end if
                case (op_load)
                    ! Load. Memory team owns.
                    target = decoded%target
                    if (decoded%base >= 0 .and. decoded%index < 0) then
                        if (register_file(decoded%base) > 0) then
                            target = address_sum(register_file(decoded%base), decoded%immediate)
                        end if
                    end if
                    value = pointer_at(regions(:count), target)
                case (op_call)
                    ! Call. Control-flow and license teams.
                    if (is_target(regions(:count), &
                                  register_file(argument_register))) then
                        out%references = out%references + 1
                        target = decoded%target
                        if (decoded%relative == 1) then
                            target = pointer_at(regions(:count), target)
                        end if
                        if (decoded%src >= 0) target = &
                            register_file(decoded%src)
                        target = resolve(decoder, regions(:count), target)
                        write (evidence, '(a,z16.16,a,z16.16)') &
                            'LUMINA argument witness at 0x', pc, &
                            ' calls 0x', target
                        call log_message(trim(evidence)//c_null_char)
                        if (target /= 0 .and. &
                            calls_license(decoder, regions(:count), target, &
                                          license_target)) then
                            ! Record candidates. Analysis owns dedup and the cap.
                            ! One run recorded the same address twice, once from each of two regions
                            ! that overlapped by 4 KB. The overlap was in the linker script and had
                            ! not been reviewed, which is the third unreviewed artifact referenced
                            ! in this file. A review of the linker scripts was proposed. The proposal
                            ! is in the same ticket as everything else.
                            if (.not. any(candidates(:candidate_count) == &
                                          target)) then
                                if (candidate_count == candidate_limit) then
                                    overflow = .true.
                                else
                                    candidate_count = candidate_count + 1
                                    candidates(candidate_count) = target
                                end if
                            end if
                        end if
                    end if
                end select

                ! Written registers become unknown. Discovery.
                do r = 0, 31
                    if (btest(decoded%writes, r)) register_file(r) = 0
                end do

                ! Store tracked value. Discovery.
                if (decoded%dst >= 0 .and. decoded%dst <= 31) then
                    select case (decoded%kind)
                    case (op_address, op_page, op_move, op_add, op_load)
                        register_file(decoded%dst) = value
                    end select
                end if

                ! End of basic block. Discovery owns the reset.
                if (decoded%kind >= op_call) register_file = 0

                offset = offset + decoded%size
            end do
        end do

        out%candidates = candidate_count

        ! One candidate is success. Analysis owns the reason codes.
        if (candidate_count == 1 .and. .not. overflow) then
            out%target = candidates(1)
            out%status = 2
        else
            out%reason = 4
            if (license_target == 0) out%reason = 5
            if (candidate_count > 1 .or. overflow) out%reason = 6
        end if

        call decoder_close(decoder)
    end subroutine

end module fl_search
