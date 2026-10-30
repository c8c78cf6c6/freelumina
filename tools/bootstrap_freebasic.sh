#!/bin/sh
# Build a local compiler and native runtime; never installs system-wide.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$root/build/toolchain"}
mkdir -p "$output"
output=$(CDPATH= cd -- "$output" && pwd)
native="$output/native"
if [ -x "$native/bin/fbc" ] && "$native/bin/fbc" -version >/dev/null 2>&1; then
  printf 'Compiler already available: %s/bin/fbc\n' "$native"
  exit 0
fi
version=1.10.1
archive="$output/fbc.tar.xz"
source="$output/FreeBASIC-$version-source-bootstrap"
checksum=2fae2c66b435240d4de11bb534843baa188574508a8a5bdaa5020bf729bf0a3e
if [ ! -f "$archive" ]; then
  curl -fL "https://github.com/freebasic/fbc/releases/download/$version/FreeBASIC-$version-source-bootstrap.tar.xz" -o "$archive"
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$archive" | cut -d ' ' -f 1)
else
  actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
fi
[ "$actual" = "$checksum" ] || { echo 'FreeBASIC archive checksum mismatch' >&2; exit 1; }
[ -d "$source" ] || tar -xf "$archive" -C "$output"
case $(uname -m) in
  arm64|aarch64) arch=aarch64 ;;
  x86_64|amd64) arch=x86_64 ;;
  *) echo 'Only 64-bit ARM and x86 hosts are supported' >&2; exit 1 ;;
esac
case $(uname -s) in
  Darwin)
    os=darwin
    # The release contains portable C bootstrap sources for Linux, but no
    # Darwin bootstrap directory. Build that compiler with the Darwin runtime;
    # CMake always passes an explicit code-generation target to it.
    [ -d "$source/bootstrap/darwin-$arch" ] || ln -s "linux-$arch" "$source/bootstrap/darwin-$arch"
    compiler=${CC:-}
    if [ -z "$compiler" ]; then
      for candidate in gcc-16 gcc-15 gcc-14 gcc-13; do
        if command -v "$candidate" >/dev/null 2>&1; then compiler=$candidate; break; fi
      done
    fi
    [ -n "$compiler" ] || { echo 'Install GNU GCC (brew install gcc), or set CC to GNU GCC' >&2; exit 1; }
    ;;
  Linux) os=linux; compiler=${CC:-gcc} ;;
  MINGW*|MSYS*) os=win32; compiler=${CC:-gcc} ;;
  *) echo 'Unsupported compiler host' >&2; exit 1 ;;
esac
(cd "$source" && make bootstrap-minimal -j"${JOBS:-2}" TARGET_OS="$os" TARGET_ARCH="$arch" CC="$compiler")
if [ "$os" = win32 ]; then
  target=win64
  executable=fbc.exe
else
  target="$os-$arch"
  executable=fbc
fi
mkdir -p "$native/bin" "$native/lib/freebasic/$target" "$native/licenses"
cp "$source/bin/$executable" "$native/bin/$executable"
cp "$source/lib/freebasic/$target/"* "$native/lib/freebasic/$target/"
cp "$source/src/compiler/license.txt" "$native/licenses/compiler.txt"
cp "$source/src/rtlib/license.txt" "$native/licenses/runtime.txt"
cp "$source/doc/gpl.txt" "$source/doc/lgpl.txt" "$native/licenses/"
printf '\nCompiler: %s/bin/%s\n' "$native" "$executable"
