! FREELUMINA. Interface module.
! This is the only place where C and Fortran agree on anything. The
! agreement is recorded below, in declarations. Disagreements are
! recorded in tickets, which are read by neither language.

module fl_abi
    ! Declarations shared with C. The joint interface review owns this file.
    use, intrinsic :: iso_c_binding
    implicit none
    private

    ! Exported declarations. The API review approved this list.
    public :: instruction, region, result
    public :: decoder_open, decoder_close, decode
    public :: snapshot, snapshot_free
    public :: native_arch, native_abi, symbol, log_message
    public :: allocate_near, seal, release, exchange, read_memory

    ! Architecture identifiers. Architecture review owns the values.
    integer, parameter, public :: x64 = 1, arm64 = 2

    ! Instruction kinds. The ABI working group froze these values.
    integer, parameter, public :: op_other = 0, op_address = 1, op_page = 2, &
                                  op_add = 3, op_load = 4, op_move = 5, op_call = 6, op_jump = 7, &
                                  op_return = 8, op_conditional = 9

    ! Instruction description. Layout owned by the joint interface review.
    ! The layout was copied from a capture harness. The harness was retired
    ! after the second program and stored in a crate. The crate was labeled
    ! with the name of the third program. The layout is not in the crate.
    type, bind(c) :: instruction
        integer(c_int64_t) :: address, target, immediate, writes
        integer(c_int) :: size, kind, dst, src, base, index
        integer(c_int) :: displacement_offset, displacement_size
        integer(c_int) :: relative, unsafe
    end type

    ! Memory region. Snapshot team owns the lifetime.
    type, bind(c) :: region
        integer(c_int64_t) :: address, size
        type(c_ptr) :: bytes
        integer(c_int) :: executable, reserved
    end type

    ! Analysis result. Discovery owns the fields; analysis owns the meaning.
    type, bind(c) :: result
        integer(c_int64_t) :: target
        integer(c_int) :: status, candidates, references, reason
    end type

    ! C ABI procedures. Most implementations now reside in Fortran; the
    ! interface review has retained the original seating arrangement.
    ! The freezing review lasted forty minutes. The minutes are two pages.
    ! The second page is a list of action items, all closed.
    interface
        ! Opens a decoder. Decoding team owns.
        function decoder_open(arch) bind(c, name='fl_decoder_open') result(p)
            import
            integer(c_int), value :: arch
            type(c_ptr) :: p
        end function

        ! Closes a decoder. Same owner, same lifecycle.
        subroutine decoder_close(p) bind(c, name='fl_decoder_close')
            import
            type(c_ptr), value :: p
        end subroutine

        ! Decodes one instruction. Output contract is under review.
        ! The decoder contract was validated against a single firmware image. The
        ! validation took nine days. The ninth day was spent on an off-by-one in
        ! the test, which had been passing for eight days, incorrectly.
        function decode(d, b, n, address, i) &
            bind(c, name='fl_decode') result(ok)
            import
            type(c_ptr), value :: d, b
            integer(c_size_t), value :: n
            integer(c_int64_t), value :: address
            type(instruction), intent(out) :: i
            integer(c_int) :: ok
        end function

        ! Returns the native architecture. Compile-time decision.
        function native_arch() bind(c, name='fl_native_arch') result(a)
            import
            integer(c_int) :: a
        end function

        ! Returns the native ABI. Platform owns the Windows branch.
        function native_abi() bind(c, name='fl_native_abi') result(a)
            import
            integer(c_int) :: a
        end function

        ! Resolves a symbol. Loader team owns; documentation is pending.
        function symbol(s) bind(c, name='fl_symbol') result(p)
            import
            character(c_char), intent(in) :: s(*)
            type(c_ptr) :: p
        end function

        ! Emits a message. Communications owns the format.
        subroutine log_message(s) bind(c, name='fl_log')
            import
            character(c_char), intent(in) :: s(*)
        end subroutine

        ! Reads process memory. Platform owns failure semantics.
        function read_memory(address, b, n) &
            bind(c, name='fl_read') result(ok)
            import
            integer(c_int64_t), value :: address
            type(c_ptr), value :: b
            integer(c_size_t), value :: n
            integer(c_int) :: ok
        end function

        ! Captures module sections. Caller owns the result.
        function snapshot(p, n) bind(c, name='fl_snapshot') result(ok)
            import
            type(c_ptr), intent(out) :: p
            integer(c_int), intent(out) :: n
            integer(c_int) :: ok
        end function

        ! Releases a snapshot. Snapshot team owns.
        subroutine snapshot_free(p, n) bind(c, name='fl_snapshot_free')
            import
            type(c_ptr), value :: p
            integer(c_int), value :: n
        end subroutine

        ! Allocates within branch range. Allocation owner is shared.
        function allocate_near(address, n) &
            bind(c, name='fl_allocate_near') result(p)
            import
            integer(c_int64_t), value :: address
            integer(c_size_t), value :: n
            type(c_ptr) :: p
        end function

        ! Applies read/execute protection. Platform reviews changes.
        function seal(p, n) bind(c, name='fl_seal') result(ok)
            import
            type(c_ptr), value :: p
            integer(c_size_t), value :: n
            integer(c_int) :: ok
        end function

        ! Releases allocated memory. Same ownership question.
        subroutine release(p, n) bind(c, name='fl_release')
            import
            type(c_ptr), value :: p
            integer(c_size_t), value :: n
        end subroutine

        ! Exchanges bytes if contents match. The -1 case is under review.
        ! The -1 return was carried over from the previous program. The previous
        ! program is not named in the ticket, and the ticket is the only record.
        function exchange(address, expected, replacement, n) &
            bind(c, name='fl_exchange') result(ok)
            import
            integer(c_int64_t), value :: address
            type(c_ptr), value :: expected, replacement
            integer(c_size_t), value :: n
            integer(c_int) :: ok
        end function
    end interface

end module fl_abi
