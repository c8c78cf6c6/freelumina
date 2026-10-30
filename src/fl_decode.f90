! FREELUMINA. The instruction committee has been brought in-house.
!
! This is a deliberately bounded decoder, not a general disassembler. It
! recognizes the integer, address-materialization, and control-flow forms
! needed by discovery and entry replay. Unsupported encodings return failure.
! No guessed instruction length is ever admitted to a replay plan.
module fl_decoder
    use, intrinsic :: iso_c_binding
    use fl_abi, only: instruction, x64, arm64, op_other, op_address, op_page, &
                      op_add, op_load, op_move, op_call, op_jump, op_return, op_conditional
    use fl_bytes
    implicit none
    private
    public :: open_decoder, close_decoder, decode_instruction

    type, bind(c) :: decoder_state
        integer(c_int) :: architecture
    end type

    type :: x86_operands
        integer :: mode = 0
        integer :: group = 0
        integer :: destination = -1
        integer :: source = -1
        integer :: base = -1
        integer :: index = -1
        integer :: displacement_offset = 0
        integer :: displacement_size = 0
        integer(c_int64_t) :: displacement = 0
        logical :: rip_relative = .false.
    end type

contains

    function open_decoder(architecture) bind(c, name='fl_decoder_open') result(handle)
        integer(c_int), value :: architecture
        type(c_ptr) :: handle
        type(decoder_state), pointer :: state
        integer :: allocation_status

        handle = c_null_ptr
        if (architecture /= x64 .and. architecture /= arm64) return
        allocate (state, stat=allocation_status)
        if (allocation_status /= 0) return
        state%architecture = architecture
        handle = c_loc(state)
    end function

    subroutine close_decoder(handle) bind(c, name='fl_decoder_close')
        type(c_ptr), value :: handle
        type(decoder_state), pointer :: state

        if (.not. c_associated(handle)) return
        call c_f_pointer(handle, state)
        deallocate (state)
    end subroutine

    integer(c_int) function decode_instruction(handle, memory, length, address, decoded) &
        bind(c, name='fl_decode') result(success)
        type(c_ptr), value :: handle, memory
        integer(c_size_t), value :: length
        integer(c_int64_t), value :: address
        type(instruction), intent(out) :: decoded
        type(decoder_state), pointer :: state
        integer(c_int8_t), pointer :: bytes(:)
        integer :: available

        success = 0
        decoded = instruction(address, 0_c_int64_t, 0_c_int64_t, 0_c_int64_t, &
                              0, op_other, -1, -1, -1, -1, 0, 0, 0, 0)
        if (.not. c_associated(handle) .or. .not. c_associated(memory)) return
        if (length <= 0 .or. address < 0 .or. address > huge(address) - 16) return
        available = int(min(length, 15_c_size_t))
        call c_f_pointer(handle, state)
        call c_f_pointer(memory, bytes, [available])
        if (state%architecture == arm64) then
            if (available < 4 .or. mod(address, 4_c_int64_t) /= 0) return
            success = decode_arm64(bytes, decoded)
        else if (state%architecture == x64) then
            success = decode_x86(bytes, decoded)
        end if
    end function

    subroutine mark_write(decoded, register)
        type(instruction), intent(inout) :: decoded
        integer, intent(in) :: register

        if (register >= 0 .and. register < 32) decoded%writes = ibset(decoded%writes, register)
    end subroutine

    ! Consume bytes once, with one bounds check before each field. There is
    ! no "probably another byte" clause in the interface review minutes.
    logical function consume(bytes, position, width, value) result(success)
        integer(c_int8_t), intent(in) :: bytes(:)
        integer, intent(inout) :: position
        integer, intent(in) :: width
        integer(c_int64_t), intent(out) :: value

        success = .false.
        value = 0
        if (width < 1 .or. width > 8) return
        if (position < 1 .or. position > size(bytes) - width + 1) return
        value = load_le(bytes(position:), width)
        position = position + width
        success = .true.
    end function

    logical function modrm(bytes, position, rex, operands) result(success)
        integer(c_int8_t), intent(in) :: bytes(:)
        integer, intent(inout) :: position
        integer, intent(in) :: rex
        type(x86_operands), intent(out) :: operands
        integer(c_int64_t) :: field
        integer :: raw, rm, sib, width

        success = .false.
        operands = x86_operands()
        if (.not. consume(bytes, position, 1, field)) return
        raw = int(field)
        operands%mode = shiftr(raw, 6)
        operands%group = ibits(raw, 3, 3)
        operands%destination = operands%group + 8*ibits(rex, 2, 1)
        rm = iand(raw, 7)
        operands%source = rm + 8*ibits(rex, 0, 1)
        if (operands%mode == 3) then
            success = .true.
            return
        end if

        width = 0
        operands%base = operands%source
        if (rm == 4) then
            if (.not. consume(bytes, position, 1, field)) return
            sib = int(field)
            operands%base = iand(sib, 7) + 8*ibits(rex, 0, 1)
            operands%index = ibits(sib, 3, 3) + 8*ibits(rex, 1, 1)
            if (operands%index == 4) operands%index = -1
            if (operands%mode == 0 .and. iand(sib, 7) == 5) then
                operands%base = -1
                width = 4 ! SIB with no base is absolute, never RIP-relative.
            end if
        else if (operands%mode == 0 .and. rm == 5) then
            operands%base = -1
            operands%rip_relative = .true.
            width = 4
        end if
        if (operands%mode == 1) width = 1
        if (operands%mode == 2) width = 4
        if (width > 0) then
            operands%displacement_offset = position - 1
            operands%displacement_size = width
            if (.not. consume(bytes, position, width, field)) return
            operands%displacement = signed_field(field, 8*width)
        end if
        success = .true.
    end function

    integer function byte_register(register, rex) result(parent)
        integer, intent(in) :: register, rex

        parent = register
        if (rex == 0 .and. register >= 4 .and. register <= 7) parent = register - 4
    end function

    integer(c_int) function decode_x86(bytes, decoded) result(success)
        integer(c_int8_t), intent(in) :: bytes(:)
        type(instruction), intent(inout) :: decoded
        type(x86_operands) :: operands
        integer(c_int64_t) :: field, immediate
        integer :: position, opcode, second, rex, width, immediate_width, branch_width
        integer :: operand_width, register, rm_register
        logical :: operand16, address32, has_modrm, writes_reg, writes_rm, byte_operand
        logical :: prefix_repeat, segment_override

        success = 0
        position = 1
        operands = x86_operands()
        rex = 0
        operand16 = .false.
        address32 = .false.
        prefix_repeat = .false.
        segment_override = .false.
        do
            if (.not. consume(bytes, position, 1, field)) return
            opcode = int(field)
            select case (opcode)
            case (64:79)
                rex = opcode
            case (102)
                operand16 = .true.
                rex = 0
            case (103)
                address32 = .true.
                rex = 0
            case (242, 243)
                prefix_repeat = .true.
                rex = 0
            case (38, 46, 54, 62, 100, 101)
                segment_override = .true.
                rex = 0
            case (240)
                ! LOCKed operations are outside entry replay's contract.
                return
            case default
                exit
            end select
        end do

        operand_width = merge(2, 4, operand16)
        if (btest(rex, 3)) operand_width = 8
        immediate_width = 0
        branch_width = 0
        has_modrm = .false.
        writes_reg = .false.
        writes_rm = .false.
        byte_operand = .false.
        second = -1

        select case (opcode)
        case (0:14, 16:63)
            if (iand(opcode, 7) <= 3) then
                has_modrm = .true.
                byte_operand = .not. btest(opcode, 0)
                if (opcode < 56) then
                    writes_reg = btest(opcode, 1)
                    writes_rm = .not. writes_reg
                end if
            else if (iand(opcode, 7) == 4 .or. iand(opcode, 7) == 5) then
                immediate_width = merge(1, min(operand_width, 4), iand(opcode, 7) == 4)
                if (opcode < 56) call mark_write(decoded, 0)
            else
                return
            end if
        case (80:87)
            call mark_write(decoded, 4)
        case (88:95)
            call mark_write(decoded, 4)
            call mark_write(decoded, opcode - 88 + 8*ibits(rex, 0, 1))
        case (99)
            has_modrm = .true.
            writes_reg = .true.
        case (104, 106)
            immediate_width = merge(1, merge(2, 4, operand16), opcode == 106)
            call mark_write(decoded, 4)
        case (105, 107)
            has_modrm = .true.
            writes_reg = .true.
            immediate_width = merge(1, min(operand_width, 4), opcode == 107)
        case (112:127, 224:227)
            decoded%kind = op_conditional
            branch_width = 1
            if (opcode >= 224) call mark_write(decoded, 1)
        case (128, 129, 131)
            has_modrm = .true.
            writes_rm = .true.
            immediate_width = merge(min(operand_width, 4), 1, opcode == 129)
            byte_operand = opcode == 128
        case (132:143)
            has_modrm = .true.
            byte_operand = opcode == 132 .or. opcode == 134 .or. opcode == 136 .or. opcode == 138
            writes_reg = opcode == 134 .or. opcode == 135 .or. opcode == 138 .or. opcode == 139 .or. opcode == 141
            writes_rm = opcode == 134 .or. opcode == 135 .or. opcode == 136 .or. opcode == 137 .or. &
                        opcode == 140 .or. opcode == 143
            if (opcode == 143) call mark_write(decoded, 4)
        case (144)
            ! NOP, or PAUSE with F3. Both have the same register transfer.
        case (145:151)
            call mark_write(decoded, 0)
            call mark_write(decoded, opcode - 144 + 8*ibits(rex, 0, 1))
        case (152, 159)
            call mark_write(decoded, 0)
        case (153)
            call mark_write(decoded, 2)
        case (156, 157)
            call mark_write(decoded, 4)
        case (158, 245, 248:253)
            ! Flag-only operations do not materialize an argument address.
        case (160:163)
            immediate_width = merge(4, 8, address32)
            if (opcode <= 161) call mark_write(decoded, 0)
        case (164:167, 170:175)
            decoded%writes = maskr(16, kind=c_int64_t)
        case (168, 169)
            immediate_width = merge(1, min(operand_width, 4), opcode == 168)
        case (176:183)
            immediate_width = 1
            call mark_write(decoded, byte_register(opcode - 176 + 8*ibits(rex, 0, 1), rex))
        case (184:191)
            immediate_width = operand_width
            decoded%dst = opcode - 184 + 8*ibits(rex, 0, 1)
            call mark_write(decoded, decoded%dst)
        case (192, 193)
            has_modrm = .true.
            writes_rm = .true.
            byte_operand = opcode == 192
            immediate_width = 1
        case (194, 195)
            decoded%kind = op_return
            if (opcode == 194) immediate_width = 2
        case (198, 199)
            has_modrm = .true.
            writes_rm = .true.
            byte_operand = opcode == 198
            immediate_width = merge(1, min(operand_width, 4), byte_operand)
        case (200)
            immediate_width = 3
            decoded%unsafe = 1
        case (201)
            call mark_write(decoded, 4)
            call mark_write(decoded, 5)
        case (204, 205, 241, 244)
            decoded%unsafe = 1
            if (opcode == 205) immediate_width = 1
        case (208:211)
            has_modrm = .true.
            writes_rm = .true.
            byte_operand = .not. btest(opcode, 0)
        case (215)
            call mark_write(decoded, 0)
        case (232, 233, 235)
            decoded%kind = merge(op_call, op_jump, opcode == 232)
            branch_width = merge(1, 4, opcode == 235)
        case (246, 247, 254, 255)
            has_modrm = .true.
            byte_operand = opcode == 246 .or. opcode == 254
        case (15)
            if (.not. consume(bytes, position, 1, field)) return
            second = int(field)
            select case (second)
            case (5, 7, 11, 48, 50, 52, 53)
                decoded%unsafe = 1
            case (30, 31)
                has_modrm = .true.
            case (49, 51)
                call mark_write(decoded, 0)
                call mark_write(decoded, 2)
            case (64:79, 175, 182, 183, 188, 189, 190, 191)
                has_modrm = .true.
                writes_reg = .true.
            case (128:143)
                decoded%kind = op_conditional
                branch_width = 4
            case (144:159)
                has_modrm = .true.
                writes_rm = .true.
                byte_operand = .true.
            case (162)
                decoded%writes = 15
            case (163, 171, 179, 187)
                has_modrm = .true.
                writes_rm = second /= 163
            case (164, 165, 172, 173)
                has_modrm = .true.
                writes_rm = .true.
                if (second == 164 .or. second == 172) immediate_width = 1
            case (176, 177, 192, 193)
                has_modrm = .true.
                writes_reg = second >= 192
                writes_rm = .true.
                byte_operand = .not. btest(second, 0)
                call mark_write(decoded, 0)
            case (186)
                has_modrm = .true.
                writes_rm = .true.
                immediate_width = 1
            case (200:207)
                call mark_write(decoded, second - 200 + 8*ibits(rex, 0, 1))
            case (16:23, 40:47, 80:118, 124:127, 194:198, 208:254)
                ! Supported two-byte SIMD forms. Vector values remain unknown;
                ! the handful of GPR-producing forms invalidate that GPR.
                has_modrm = .true.
                if (second == 44 .or. second == 45 .or. second == 80 .or. second == 197 .or. &
                    second == 215) writes_reg = .true.
                if (second == 126) writes_rm = .true.
                if ((second >= 112 .and. second <= 115) .or. second == 194 .or. &
                    (second >= 196 .and. second <= 198)) immediate_width = 1
                ! EMMS has no ModR/M byte. Its neighbors do.
            case (119)
                has_modrm = .false.
            case default
                return ! VEX, EVEX, three-byte maps, and system forms are outside this decoder.
            end select
        case default
            return
        end select

        if (has_modrm) then
            if (.not. modrm(bytes, position, rex, operands)) return
            register = operands%destination
            rm_register = operands%source
            if (byte_operand) then
                register = byte_register(register, rex)
                rm_register = byte_register(rm_register, rex)
            end if

            if (opcode == 128 .or. opcode == 129 .or. opcode == 131) then
                if (operands%group == 7) writes_rm = .false.
            end if
            if (opcode == 198 .or. opcode == 199 .or. opcode == 143) then
                if (operands%group /= 0) return
            end if
            if (opcode == 141 .and. operands%mode == 3) return
            if (opcode == 246 .or. opcode == 247) then
                select case (operands%group)
                case (0)
                    immediate_width = merge(1, min(operand_width, 4), byte_operand)
                case (1)
                    return
                case (2, 3)
                    writes_rm = .true.
                case (4:7)
                    call mark_write(decoded, 0)
                    call mark_write(decoded, 2)
                end select
            end if
            if (opcode == 254) then
                if (operands%group > 1) return
                writes_rm = .true.
            end if
            if (opcode == 255) then
                select case (operands%group)
                case (0, 1)
                    writes_rm = .true.
                case (2, 4)
                    decoded%kind = merge(op_call, op_jump, operands%group == 2)
                    if (operands%mode == 3) decoded%src = operands%source
                case (6)
                    call mark_write(decoded, 4)
                case default
                    return
                end select
            end if
            if (writes_reg) call mark_write(decoded, register)
            if (writes_rm .and. operands%mode == 3) call mark_write(decoded, rm_register)

            decoded%displacement_offset = operands%displacement_offset
            decoded%displacement_size = operands%displacement_size
            if (operands%rip_relative) decoded%relative = 1

            if (opcode == 141 .and. operand_width == 8 .and. .not. segment_override) then
                decoded%dst = register
                if (operands%rip_relative) then
                    decoded%kind = op_address
                else if (operands%base >= 0 .and. operands%index < 0 .and. .not. address32) then
                    decoded%kind = op_add
                    decoded%src = operands%base
                    decoded%immediate = operands%displacement
                end if
            else if (opcode == 137 .or. opcode == 139) then
                if (operand_width == 8 .and. .not. segment_override) then
                    if (operands%mode == 3) then
                        decoded%kind = op_move
                        decoded%dst = merge(register, rm_register, opcode == 139)
                        decoded%src = merge(rm_register, register, opcode == 139)
                    else if (opcode == 139 .and. operands%index < 0 .and. .not. address32) then
                        decoded%kind = op_load
                        decoded%dst = register
                        decoded%base = operands%base
                        decoded%index = operands%index
                        decoded%immediate = operands%displacement
                    end if
                end if
            end if
            if (opcode == 15 .and. second == 30) then
                ! Only F3 0F 1E FA (ENDBR64) is supported in this opcode slot.
                if (.not. prefix_repeat .or. operands%mode /= 3 .or. &
                    operands%group /= 7 .or. operands%source /= 2) return
            end if
        end if

        if (branch_width > 0) then
            decoded%displacement_offset = position - 1
            decoded%displacement_size = branch_width
            if (.not. consume(bytes, position, branch_width, field)) return
            decoded%relative = 2
            decoded%target = address_sum(decoded%address + position - 1, signed_field(field, 8*branch_width))
            ! CALL next; POP observes its original PC and is not a replayable call.
            if (decoded%kind == op_call .and. field == 0) decoded%unsafe = 1
        else if (immediate_width > 0) then
            if (.not. consume(bytes, position, immediate_width, immediate)) return
            if (opcode >= 184 .and. opcode <= 191 .and. operand_width >= 4) then
                decoded%kind = op_address
                decoded%target = immediate
            end if
        end if

        width = position - 1
        if (width > 15) return
        decoded%size = width
        if (operands%rip_relative .and. has_modrm) then
            decoded%target = address_sum(decoded%address + width, operands%displacement)
            if (address32) then
                ! Address-size override selects EIP-relative arithmetic. The
                ! low-32-bit wrap is useful to discovery but not admitted to
                ! the ordinary RIP-relative relocation path.
                decoded%target = iand(decoded%target, int(z'FFFFFFFF', c_int64_t))
                decoded%unsafe = 1
            end if
        end if
        success = 1
    end function

    integer(c_int) function decode_arm64(bytes, decoded) result(success)
        integer(c_int8_t), intent(in) :: bytes(:)
        type(instruction), intent(inout) :: decoded
        integer(c_int64_t) :: word, immediate, category
        integer :: destination, source, second, mode, element_size
        logical :: load, vector

        success = 0
        word = load_le(bytes, 4)
        destination = int(ibits(word, 0, 5))
        source = int(ibits(word, 5, 5))
        second = int(ibits(word, 16, 5))
        decoded%size = 4

        if (iand(word, int(z'7C000000', c_int64_t)) == int(z'14000000', c_int64_t)) then
            decoded%kind = merge(op_call, op_jump, btest(word, 31))
            decoded%target = address_sum(decoded%address, 4*signed_field(ibits(word, 0, 26), 26))
            decoded%relative = 2
        else if (iand(word, int(z'FF000010', c_int64_t)) == int(z'54000000', c_int64_t)) then
            decoded%kind = op_conditional
            decoded%target = address_sum(decoded%address, 4*signed_field(ibits(word, 5, 19), 19))
            decoded%relative = 2
        else if (iand(word, int(z'7E000000', c_int64_t)) == int(z'34000000', c_int64_t)) then
            decoded%kind = op_conditional
            decoded%target = address_sum(decoded%address, 4*signed_field(ibits(word, 5, 19), 19))
            decoded%relative = 2
        else if (iand(word, int(z'7E000000', c_int64_t)) == int(z'36000000', c_int64_t)) then
            decoded%kind = op_conditional
            decoded%target = address_sum(decoded%address, 4*signed_field(ibits(word, 5, 14), 14))
            decoded%relative = 2
        else if (iand(word, int(z'FFFFFC1F', c_int64_t)) == int(z'D61F0000', c_int64_t)) then
            decoded%kind = op_jump
            decoded%src = source
        else if (iand(word, int(z'FFFFFC1F', c_int64_t)) == int(z'D63F0000', c_int64_t)) then
            decoded%kind = op_call
            decoded%src = source
        else if (iand(word, int(z'FFFFFC1F', c_int64_t)) == int(z'D65F0000', c_int64_t)) then
            decoded%kind = op_return
        else if (iand(word, int(z'1F000000', c_int64_t)) == int(z'10000000', c_int64_t)) then
            immediate = signed_field(ior(shiftl(ibits(word, 5, 19), 2), ibits(word, 29, 2)), 21)
            decoded%dst = destination
            decoded%relative = 1
            if (btest(word, 31)) then
                decoded%kind = op_page
                decoded%target = address_sum(iand(decoded%address, not(4095_c_int64_t)), 4096*immediate)
            else
                decoded%kind = op_address
                decoded%target = address_sum(decoded%address, immediate)
            end if
            call mark_write(decoded, destination)
        else if (iand(word, int(z'1F000000', c_int64_t)) == int(z'11000000', c_int64_t)) then
            immediate = ibits(word, 10, 12)
            if (btest(word, 22)) immediate = shiftl(immediate, 12)
            if (btest(word, 31) .and. .not. btest(word, 30) .and. .not. btest(word, 29)) then
                decoded%kind = op_add
                decoded%dst = destination
                decoded%src = source
                decoded%immediate = immediate
            end if
            if (destination /= 31 .or. .not. btest(word, 29)) call mark_write(decoded, destination)
        else if (iand(word, int(z'3B000000', c_int64_t)) == int(z'18000000', c_int64_t)) then
            decoded%relative = 1
            decoded%target = address_sum(decoded%address, 4*signed_field(ibits(word, 5, 19), 19))
            vector = btest(word, 26)
            if (.not. vector .and. ibits(word, 30, 2) /= 3) call mark_write(decoded, destination)
            if (.not. vector .and. ibits(word, 30, 2) == 1) then
                decoded%kind = op_load
                decoded%dst = destination
            end if
        else if (iand(word, int(z'3A000000', c_int64_t)) == int(z'28000000', c_int64_t)) then
            ! Pair loads/stores; writeback changes the base even for SIMD pairs.
            mode = int(ibits(word, 23, 2))
            if (mode == 1 .or. mode == 3) call mark_write(decoded, source)
            if (btest(word, 22) .and. .not. btest(word, 26)) then
                call mark_write(decoded, destination)
                call mark_write(decoded, int(ibits(word, 10, 5)))
            end if
        else if (iand(word, int(z'3B000000', c_int64_t)) == int(z'39000000', c_int64_t) .or. &
                 iand(word, int(z'3B000000', c_int64_t)) == int(z'38000000', c_int64_t)) then
            load = ibits(word, 22, 2) /= 0
            vector = btest(word, 26)
            element_size = int(ibits(word, 30, 2))
            mode = 0
            if (.not. btest(word, 24)) mode = int(ibits(word, 10, 2))
            if (mode == 1 .or. mode == 3) call mark_write(decoded, source)
            if (load .and. .not. vector) call mark_write(decoded, destination)
            if (load .and. .not. vector .and. element_size == 3 .and. &
                (btest(word, 24) .or. mode == 0) .and. .not. btest(word, 23)) then
                decoded%kind = op_load
                decoded%dst = destination
                decoded%base = source
                if (btest(word, 24)) then
                    decoded%immediate = shiftl(ibits(word, 10, 12), 3)
                else
                    decoded%immediate = signed_field(ibits(word, 12, 9), 9)
                end if
            end if
        else if (iand(word, int(z'FFFFF01F', c_int64_t)) == int(z'D503201F', c_int64_t)) then
            ! HINT includes NOP, BTI, and PAC/AUT hints. Replay keeps SP/LR;
            ! authentication is never synthesized or stripped by this decoder.
            call mark_write(decoded, 30)
        else
            category = iand(word, int(z'1F000000', c_int64_t))
            select case (category)
            case (int(z'0A000000', c_int64_t), int(z'0B000000', c_int64_t), &
                  int(z'12000000', c_int64_t), int(z'13000000', c_int64_t), &
                  int(z'1A000000', c_int64_t), int(z'1B000000', c_int64_t))
                ! Integer data processing. No PC-relative fields in these classes.
                if (destination /= 31) call mark_write(decoded, destination)
                if (iand(word, int(z'FFE0FFE0', c_int64_t)) == int(z'AA0003E0', c_int64_t)) then
                    decoded%kind = op_move
                    decoded%dst = destination
                    decoded%src = second
                end if
            case default
                return
            end select
        end if
        success = 1
    end function

end module fl_decoder
