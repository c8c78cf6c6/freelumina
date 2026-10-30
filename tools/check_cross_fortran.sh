#!/bin/sh
# Compile-only ABI coverage. No link or execution claim is made by this script.
set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root=${1:?Usage: check_cross_fortran.sh OUTPUT_DIRECTORY}
compiler=${FC:-flang-new-19}
mkdir -p "$output_root"
output_root=$(CDPATH= cd -- "$output_root" && pwd)

for target in x86_64-pc-windows-gnu aarch64-pc-windows-gnu \
              x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu \
              x86_64-apple-darwin aarch64-apple-darwin; do
    case "$target" in
        *windows*) os_definition=FL_OS_WINDOWS ;;
        *linux*) os_definition=FL_OS_LINUX ;;
        *darwin*) os_definition=FL_OS_MACOS ;;
    esac
    case "$target" in
        aarch64*) architecture_definition=FL_ARCH_ARM64 ;;
        x86_64*) architecture_definition=FL_ARCH_X64 ;;
    esac
    mkdir -p "$output_root/$target"
    (
        cd "$output_root/$target"
        for source in fl_abi.f90 fl_bytes.f90 fl_decode.f90 fl_search.f90 \
                      fl_patch.f90 fl_platform.F90 fl_lifecycle.f90; do
            "$compiler" --target="$target" -cpp -D"$os_definition" \
                -D"$architecture_definition" -c "$source_root/src/$source"
        done
    )
    printf '%s: Fortran objects compiled\n' "$target"
done
