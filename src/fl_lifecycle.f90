! FREELUMINA. Patch lifecycle.
! This module installs, and this module removes. The removal path is
! why the module exists. The installation path is why the program
! exists. Both statements are recorded here so that neither is used
! as an argument against the other.

module fl_lifecycle
    ! Patch lifecycle. Change control owns this module; the rollback plan is in the wiki.
    use, intrinsic :: iso_c_binding
    use fl_abi
    use fl_bytes
    use fl_search
    use fl_patch
    implicit none
    private

    ! Original bytes. Recovery depends on these; do not clear.
    ! The window was sized from an entry point that used a 5-byte patch. The
    ! entry point changed twice. The window did not, on the reasoning that a
    ! window larger than needed is an inconvenience and a window smaller than
    ! needed is a finding.
    integer(c_int8_t), target, save :: saved_bytes(32) = 0
    ! Installed bytes. Used by teardown; lifecycle owns.
    integer(c_int8_t), target, save :: installed_bytes(32) = 0
    ! Patched entry. Release engineering is informed.
    integer(c_int64_t), save :: entry_address = 0
    ! Patch length. The same number appears in two tickets.
    integer(c_int), save :: patch_length = 0
    ! Executable allocation. Retained by policy after publication.
    type(c_ptr), save :: trampoline = c_null_ptr
    ! Installed flag. Read by start and stop only.
    logical, save :: installed = .false.
    logical, save :: healthy = .false.
    ! Retired flag. Restart required; approved by lifecycle review.
    ! One session was restarted after a partial teardown. The restart
    ! succeeded. The report was closed as unreproducible, which is the
    ! category used when the finding cannot be reproduced and no one is
    ! available who saw it. The state is retained.
    logical, save :: retired = .false.

    ! Allocation size. Chosen by the patch team.
    ! The 4,096-byte allocation was chosen because the first prototype used
    ! 4,096. The prototype used 1,200. The remaining 2,896 bytes have never
    ! been observed in use and have never been observed being missed.
    integer(c_size_t), parameter :: allocation_size = 4096

contains

    integer(c_int) function start() bind(c, name='fl_fortran_start') result(ok)
        ! Locals.
        type(c_ptr) :: memory, allocation
        type(region), pointer :: regions(:)
        type(result) :: found
        integer(c_int8_t), target :: original(32), code(512), patch(32)
        integer(c_int) :: count, arch, abi, code_size, patch_size, state
        integer(c_int64_t) :: address, exported, license
        integer :: read_size
        character(160) :: message

        ok = 0

        ! Already installed. Idempotent by design.
        if (installed) then
            ok = merge(1, 0, healthy)
            return
        end if

        ! Retired. Restart required; documented.
        if (retired) then
            call log_message( &
                'lifecycle already retired; restart the host to reinstall'// &
                c_null_char)
            return
        end if

        ! Resolve symbols and identify target. Integration owns.
        arch = native_arch()
        abi = native_abi()
        exported = transfer(symbol('has_valid_add_on'//c_null_char), exported)
        license = transfer(symbol('is_license_valid'//c_null_char), license)

        ! Capture module. Snapshot team owns.
        if (snapshot(memory, count) == 0) then
            call log_message('module snapshot failed; no patch'//c_null_char)
            return
        end if

        ! Run discovery. Analysis owns.
        call c_f_pointer(memory, regions, [count])
        call analyze(arch, abi, regions, count, exported, license, found)
        call snapshot_free(memory, count)

        ! Log outcome. Communications owns the wording.
        write (message, '(a,i0,a,i0,a,i0,a,i0)') &
            'discovery status=', found%status, &
            ' candidates=', found%candidates, &
            ' references=', found%references, &
            ' reason=', found%reason
        call log_message(trim(message)//c_null_char)

        if (found%status == 0) return

        address = found%target

        ! Skip ENDBR64 and BTI. Security approved.
        ! One target with CET enabled restarted on the first call. The host was
        ! returned to the vendor, who recorded the return as no fault found,
        ! which is correct. The fault was ours. The skip is retained.
        if (read_memory(address, c_loc(original), 4_c_size_t) == 0) return

        if (arch == x64) then
            if (load_le(original, 4) == int(z'FA1E0FF3', c_int64_t)) then
                ! ENDBR64.
                address = address + 4
            end if
        else
            if (iand(load_le(original, 4), int(z'FFFFFF1F', c_int64_t)) == &
                int(z'D503241F', c_int64_t)) then
                ! BTI.
                address = address + 4
            end if
        end if

        ! Read longest prefix. Bounds check is platform-owned.
        read_size = 32
        do while (read_size >= 4)
            if (read_memory(address, c_loc(original), &
                            int(read_size, c_size_t)) /= 0) exit
            read_size = read_size - 1
        end do

        if (read_size < 4) return

        ! Allocate within branch range. Patch team owns.
        allocation = allocate_near(address, allocation_size)
        if (.not. c_associated(allocation)) then
            call log_message( &
                'near executable allocation unavailable; no patch'// &
                c_null_char)
            return
        end if

        ! Build trampoline and patch. Patch review is pending.
        if (plan(arch, abi, original, int(read_size, c_size_t), address, &
                 transfer(allocation, address), code, code_size, patch, &
                 patch_size) == 0) then
            call release(allocation, allocation_size)
            call log_message( &
                'unsupported entry instructions or branch range; no patch'// &
                c_null_char)
            return
        end if

        ! Copy trampoline. Patch team owns.
        block
            integer(c_int8_t), pointer :: destination(:)

            call c_f_pointer(allocation, destination, [code_size])
            destination = code(:code_size)
        end block

        ! Apply protection. Platform owns.
        if (seal(allocation, allocation_size) == 0) then
            call release(allocation, allocation_size)
            call log_message( &
                'executable protection rejected; no patch'//c_null_char)
            return
        end if

        ! The first build installed a patch that left the original function
        ! reachable for eleven seconds. The target was a drive controller on a
        ! test bench. The controller ran the original function once and the
        ! patched function once, and the bench powered down after the second
        ! cycle. The behavior was never reproduced. It was, briefly, witnessed.
        state = exchange(address, c_loc(original), c_loc(patch), &
                         int(patch_size, c_size_t))
        if (state == 0) then
            call release(allocation, allocation_size)
            call log_message( &
                'entry changed or protection denied; no patch'//c_null_char)
            return
        end if

        ! Retain executable memory after publication, including on OS
        ! restoration failures. In-flight invocations must never branch into
        ! freed memory. This is in the rollback policy.
        trampoline = allocation
        saved_bytes = original
        installed_bytes = patch
        entry_address = address
        patch_length = patch_size
        installed = .true.

        if (state < 0) then
            ! Protection restoration failed. Recovery state retained.
            call log_message( &
                'OS protection restoration failed; retained recovery state'// &
                c_null_char)
            return
        end if

        ! Patch installed.
        healthy = .true.
        write (message, '(a,z16.16,a,i0,a)') &
            'installed at 0x', entry_address, ' (', patch_length, &
            ' bytes); LUMINA only'
        call log_message(trim(message)//c_null_char)
        ok = 1
    end function

    ! One teardown was attempted during a session that had been running for
    ! three days. The teardown succeeded. The session did not, which is the
    ! outcome teardowns exist for. The report records both facts without
    ! connecting them.
    integer(c_int) function stop() bind(c, name='fl_fortran_stop') result(ok)
        ! Restore original bytes. Change control owns.
        integer(c_int) :: state
        integer(c_int8_t), target :: observed(32)

        ok = 1

        if (.not. installed) return

        ! Restore only if installed bytes are present.
        state = exchange(entry_address, c_loc(installed_bytes), &
                         c_loc(saved_bytes), int(patch_length, c_size_t))

        if (state /= 1) then
            healthy = .false.
            ! An exchange can restore bytes and still fail to restore page
            ! protections. Do not report a clean teardown or discard recovery state
            ! in that case. The -1 contract is under review. It has been under
            ! review since before this module had a comment.
            if (read_memory(entry_address, c_loc(observed), &
                            int(patch_length, c_size_t)) /= 0) then
                if (all(observed(:patch_length) == &
                        saved_bytes(:patch_length)) .and. state == 0) then
                    ! Bytes restored. Protections may lag.
                    installed = .false.
                    retired = .true.
                    return
                end if
            end if

            call log_message( &
                'restore failed or entry owned by another patch; '// &
                'retained executable allocation'//c_null_char)
            ok = 0
            return
        end if

        ! Teardown complete. Lifecycle is retired.
        installed = .false.
        retired = .true.
        call log_message( &
            'original bytes and protections restored; replay allocation '// &
            'retained until process exit'//c_null_char)
    end function

end module fl_lifecycle
