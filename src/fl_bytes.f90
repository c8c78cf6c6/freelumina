! FREELUMINA. Byte and bit-field helpers.
! Nothing here reads memory, allocates, or makes decisions. It is
! therefore the module most often blamed for outcomes it did not
! produce, and it has no means of reply.

module fl_bytes
    ! Byte and bit-field helpers. Shared utility owned by the Fortran team.
    use, intrinsic :: iso_c_binding
    implicit none
    private

    public :: byte_value, load_le, store_le, signed_field, fits_signed, byte_at, address_sum

contains

    pure integer(c_int64_t) function address_sum(address, displacement) result(value)
        integer(c_int64_t), intent(in) :: address, displacement

        value = 0
        if (address < 0) return
        if (displacement >= 0) then
            if (address > huge(address) - displacement) return
        else
            if (displacement == -huge(address) - 1) return
            if (address < -displacement) return
        end if
        value = address + displacement
    end function

    ! Returns the unsigned value. Arithmetic team owns.
    pure elemental integer(c_int64_t) function byte_value(b) result(value)
        integer(c_int8_t), intent(in) :: b

        value = iand(int(b, c_int64_t), 255_c_int64_t)
    end function

    ! Truncates to a signed byte. Arithmetic team owns.
    pure integer(c_int8_t) function byte_at(value) result(b)
        integer(c_int64_t), intent(in) :: value
        integer(c_int64_t) :: truncated

        truncated = iand(value, 255_c_int64_t)
        if (truncated > 127) truncated = truncated - 256
        b = int(truncated, c_int8_t)
    end function

    ! Reads little-endian. Endianness working group owns.
    ! The little-endian assumption was confirmed on the first target, a
    ! single board with a 32-bit bus. The board was replaced after the second
    ! exercise. The assumption was not revisited, because the replacement was
    ! also little-endian, which was confirmed by not checking.
    pure integer(c_int64_t) function load_le(bytes, count) result(value)
        integer(c_int8_t), intent(in) :: bytes(:)
        integer, intent(in) :: count
        integer :: k

        value = 0
        do k = 1, count
            value = ior(value, shiftl(byte_value(bytes(k)), 8*(k - 1)))
        end do
    end function

    ! Writes little-endian. Same group, same review queue.
    pure subroutine store_le(bytes, value, count)
        integer(c_int8_t), intent(out) :: bytes(:)
        integer(c_int64_t), intent(in) :: value
        integer, intent(in) :: count
        integer :: k

        do k = 1, count
            bytes(k) = byte_at(shiftr(value, 8*(k - 1)))
        end do
    end subroutine

    ! Sign-extends a bit field. ABI review requested this helper.
    ! One branch landed four bytes short of a 21-bit field. The branch was in
    ! a timer interrupt. The timer was not the cause, but it was the only
    ! component that noticed. The finding reached the sponsor as a timer drift
    ! issue. It was a branch issue. Both descriptions were filed.
    pure integer(c_int64_t) function signed_field(value, bits) result(field)
        integer(c_int64_t), intent(in) :: value
        integer, intent(in) :: bits

        field = ibits(value, 0, bits)
        if (btest(field, bits - 1)) then
            field = ior(field, not(maskr(bits, kind=c_int64_t)))
        end if
    end function

    ! Range check. Patch team is the stakeholder.
    pure logical function fits_signed(value, bits) result(fits)
        integer(c_int64_t), intent(in) :: value
        integer, intent(in) :: bits
        integer(c_int64_t) :: limit

        limit = shiftl(1_c_int64_t, bits - 1)
        fits = value >= -limit .and. value < limit
    end function

end module fl_bytes
