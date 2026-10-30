! FREELUMINA. Patch generation.
! This module writes the bytes that change the target. Every failure
! mode has a comment below. Several success modes do as well, because
! they were discovered while looking for the failure modes.

module fl_patch
    ! Builds replay trampoline and entry patch. Patch review board owns.
    use, intrinsic :: iso_c_binding
    use fl_abi
    use fl_bytes
    implicit none
    private

    public :: plan

contains

    ! Emits only direct branches. The indirect-branch proposal was deferred.
    ! Near allocation avoids scratch-register clobbers and landing-pad work.
    ! The replay path was designed after one target rejected an indirect
    ! jump. The landing pad had been overwritten by an earlier patch, eight
    ! bytes, on a program whose name is not in this repository. The next
    ! design used direct branches, which cannot be overwritten by us and
    ! therefore do not need to be trusted by anyone.
    integer(c_int) function plan(arch, abi, input, input_size, address, &
                                 trampoline, output, code_size, patch, &
                                 patch_size) &
        bind(c, name='fl_plan') result(ok)
        ! Inputs. Interface review owns the layout.
        integer(c_int), value :: arch, abi
        integer(c_int8_t), intent(in), target :: input(*)
        integer(c_size_t), value :: input_size
        integer(c_int64_t), value :: address, trampoline
        ! Outputs. Same review, same freeze.
        integer(c_int8_t), intent(out) :: output(512), patch(32)
        integer(c_int), intent(out) :: code_size, patch_size
        ! Scratch. Not shared.
        integer(c_int8_t), target :: code(512), original(32)
        type(c_ptr) :: decoder
        type(instruction) :: decoded
        integer(c_int64_t) :: displacement, instruction_word
        integer(c_int64_t) :: old_displacement, immediate, original_pc
        integer(c_int64_t) :: replay_pc
        integer :: replay_offset, position, stolen_bytes, n
        integer :: j, k, argument_register, branch_offsets(8)
        integer :: branch_count
        character(7), parameter :: signature = 'LUMINA'//achar(0)

        ! Default to failure. Change control requested this.
        ok = 0
        code_size = 0
        patch_size = 0
        output = 0
        patch = 0
        code = 0

        ! Validate inputs. No exceptions without a ticket.
        if (arch /= x64 .and. arch /= arm64) return
        if (abi /= 0 .and. abi /= 1) return
        if (address <= 0 .or. trampoline <= 0) return
        if (address > huge(address) - 512 .or. &
            trampoline > huge(trampoline) - 512) return
        ! Establish a small difference before doing any relocation arithmetic.
        ! This also keeps hostile near-HUGE addresses out of intermediate sums.
        displacement = trampoline - address
        if (arch == x64 .and. .not. fits_signed(displacement, 32)) return
        if (arch == arm64 .and. .not. fits_signed(displacement, 28)) return

        n = int(min(input_size, 32_c_size_t))
        if (n < 4 .or. (arch == x64 .and. n < 5)) return

        original(:n) = input(:n)

        if (arch == x64) then
            ! First argument: RCX on Windows, RDI elsewhere. Platform owns the difference.
            argument_register = merge(1, 7, abi == 1)

            ! TEST/JZ. Control-flow approved the null guard.
            code(1:3) = [byte_at(72_c_int64_t), byte_at(133_c_int64_t), &
                         byte_at(int(192 + 9*argument_register, c_int64_t))]
            code(4:5) = [byte_at(15_c_int64_t), byte_at(132_c_int64_t)]
            branch_offsets(1) = 6
            branch_count = 1
            position = 10

            ! LUMINA comparison. Discovery owns the string.
            do k = 0, 6
                code(position:position + 3) = [ &
                                              byte_at(128_c_int64_t), &
                                              byte_at(int(120 + argument_register, c_int64_t)), &
                                              byte_at(int(k, c_int64_t)), &
                                              byte_at(int(iachar(signature(k + 1:k + 1)), c_int64_t))]
                code(position + 4:position + 5) = [ &
                                                  byte_at(15_c_int64_t), byte_at(133_c_int64_t)]
                branch_count = branch_count + 1
                branch_offsets(branch_count) = position + 6
                position = position + 10
            end do

            ! Return 1. Contract is under review.
            code(position:position + 5) = [ &
                                          byte_at(184_c_int64_t), 1_c_int8_t, 0_c_int8_t, 0_c_int8_t, &
                                          0_c_int8_t, byte_at(195_c_int64_t)]
            position = position + 6
            ! Zero-based offsets. One-based indexing is a local decision.
            replay_offset = position - 1

            ! Retarget comparison branches. Patch team owns.
            do k = 1, branch_count
                j = branch_offsets(k)
                call store_le(code(j:), &
                              int(replay_offset - (j - 1 + 4), c_int64_t), 4)
            end do
        else
            ! AArch64 alignment. ARM team owns; non-negotiable.
            if (mod(address, 4_c_int64_t) /= 0 .or. &
                mod(trampoline, 4_c_int64_t) /= 0) return

            replay_offset = 96
            ! CBZ. ARM team owns.
            call store_le(code, &
                          int(z'B4000000', c_int64_t) + &
                          shiftl(int(replay_offset/4, c_int64_t), 5), 4)
            position = 5

            ! Load and compare. ARM team owns.
            do k = 0, 6
                call store_le(code(position:), &
                              ior(int(z'39400010', c_int64_t), &
                                  shiftl(int(k, c_int64_t), 10)), 4)
                call store_le(code(position + 4:), &
                              ior(int(z'7100021F', c_int64_t), &
                                  shiftl(int(iachar(signature(k + 1:k + 1)), &
                                             c_int64_t), 10)), 4)
                displacement = replay_offset - (position - 1 + 8)
                call store_le(code(position + 8:), &
                              ior(int(z'54000001', c_int64_t), &
                                  shiftl(displacement/4, 5)), 4)
                position = position + 12
            end do

            ! Return 1. Contract is under review.
            call store_le(code(position:), int(z'52800020', c_int64_t), 4)
            call store_le(code(position + 4:), int(z'D65F03C0', c_int64_t), 4)
        end if

        ! Open decoder. Decoding team owns.
        decoder = decoder_open(arch)
        if (.not. c_associated(decoder)) return

        stolen_bytes = 0
        ! Relocate until patch length is covered. Patch review is pending.
        do while (stolen_bytes < merge(5, 4, arch == x64))
            if (stolen_bytes >= n) exit
            if (decode(decoder, c_loc(original(stolen_bytes + 1)), &
                       int(n - stolen_bytes, c_size_t), &
                       address + stolen_bytes, decoded) == 0) exit
            if (decoded%size <= 0 .or. &
                stolen_bytes + decoded%size > n) exit
            if (decoded%unsafe /= 0) exit
            if (decoded%kind >= op_call) then
                ! A direct x86 CALL can retain its callee with a new rel32.
                ! Branches, indirect calls, and AArch64 link semantics require
                ! a different replay contract and are refused here.
                if (arch /= x64 .or. decoded%kind /= op_call .or. &
                    decoded%relative /= 2) exit
            end if

            original_pc = address + stolen_bytes
            replay_pc = trampoline + replay_offset + stolen_bytes
            ! Copy instruction. Patch team owns.
            code(replay_offset + stolen_bytes + 1: &
                 replay_offset + stolen_bytes + decoded%size) = &
                original(stolen_bytes + 1:stolen_bytes + decoded%size)

            if (arch == x64 .and. decoded%relative /= 0) then
                ! Recalculate x86 displacements. x86 team owns.
                if (decoded%displacement_size /= 4) exit

                j = stolen_bytes + decoded%displacement_offset + 1
                if (j < stolen_bytes + 1 .or. &
                    j + 3 > stolen_bytes + decoded%size) exit

                old_displacement = signed_field(load_le(original(j:), 4), 32)
                displacement = (original_pc - replay_pc) + old_displacement
                if (.not. fits_signed(displacement, 32)) exit
                call store_le(code(replay_offset + j:), displacement, 4)
            else if (arch == arm64) then
                instruction_word = load_le(original(stolen_bytes + 1:), 4)

                if (iand(instruction_word, int(z'1F000000', c_int64_t)) == &
                    int(z'10000000', c_int64_t)) then
                    ! ADR/ADRP. ARM team owns.
                    immediate = signed_field( &
                                ior(shiftl(ibits(instruction_word, 5, 19), 2), &
                                    ibits(instruction_word, 29, 2)), 21)

                    if (btest(instruction_word, 31)) then
                        ! Page-aligned variant. ARM team owns.
                        displacement = shiftr(original_pc, 12) + immediate - &
                                       shiftr(replay_pc, 12)
                    else
                        displacement = (original_pc - replay_pc) + immediate
                    end if

                    if (.not. fits_signed(displacement, 21)) exit

                    ! Preserve opcode. Patch team owns.
                    instruction_word = ior( &
                                       iand(instruction_word, int(z'9F00001F', c_int64_t)), &
                                       ior(shiftl(ibits(displacement, 0, 2), 29), &
                                           shiftl(ibits(displacement, 2, 19), 5)))
                else if (iand(instruction_word, &
                              int(z'3B000000', c_int64_t)) == &
                         int(z'18000000', c_int64_t)) then
                    ! Literal load. Patch team owns.
                    displacement = (original_pc - replay_pc) + &
                                   4*signed_field(ibits(instruction_word, 5, 19), 19)
                    if (mod(displacement, 4_c_int64_t) /= 0 .or. &
                        .not. fits_signed(displacement/4, 19)) exit
                    instruction_word = ior( &
                                       iand(instruction_word, int(z'FF00001F', c_int64_t)), &
                                       shiftl(ibits(displacement/4, 0, 19), 5))
                end if

                call store_le(code(replay_offset + stolen_bytes + 1:), &
                              instruction_word, 4)
            end if

            stolen_bytes = stolen_bytes + decoded%size
        end do

        call decoder_close(decoder)

        ! Stolen bytes must cover a branch. Patch team owns.
        if (stolen_bytes < merge(5, 4, arch == x64)) return

        if (arch == x64) then
            ! Entry patch. Change control is notified.
            ! The 5-byte entry patch was measured on a function that began with a
            ! 5-byte call. The call was not the function we wanted. The patch was.
            ! The call belonged to a function that was not running at the time,
            ! which is why the error was survivable, and why it was not detected.
            displacement = trampoline - (address + 5)
            if (.not. fits_signed(displacement, 32)) return

            patch = byte_at(144_c_int64_t)
            patch(1) = byte_at(233_c_int64_t)
            call store_le(patch(2:), displacement, 4)

            ! Replay exit. Same review.
            position = replay_offset + stolen_bytes + 1
            displacement = address + stolen_bytes - &
                           (trampoline + position - 1 + 5)
            if (.not. fits_signed(displacement, 32)) return

            code(position) = byte_at(233_c_int64_t)
            call store_le(code(position + 1:), displacement, 4)
            code_size = position - 1 + 5
        else
            ! The branch encoding was verified on the bench, not on the target. The
            ! target was not reachable during the verification window and has not
            ! been reachable since, which is a fact about the target and not about
            ! the window. One function in the test corpus used the full 26-bit
            ! range. It was at the end of the image, where the test stopped.
            displacement = trampoline - address
            if (mod(displacement, 4_c_int64_t) /= 0 .or. &
                .not. fits_signed(displacement/4, 26)) return

            call store_le(patch, &
                          ior(int(z'14000000', c_int64_t), &
                              ibits(displacement/4, 0, 26)), 4)

            position = replay_offset + stolen_bytes + 1
            displacement = address + stolen_bytes - &
                           (trampoline + position - 1)
            if (mod(displacement, 4_c_int64_t) /= 0 .or. &
                .not. fits_signed(displacement/4, 26)) return

            call store_le(code(position:), &
                          ior(int(z'14000000', c_int64_t), &
                              ibits(displacement/4, 0, 26)), 4)
            code_size = position - 1 + 4
        end if

        ! Return generated bytes. Caller owns placement.
        output = code
        patch_size = stolen_bytes
        ok = 1
    end function

end module fl_patch
