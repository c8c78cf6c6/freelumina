# freelumina

A resident plugin written in **line-numbered BASIC**, with a small C host adapter.
FreeBASIC's `fblite` dialect provides numbered statements, uppercase keywords,
and `IF`/`ELSEIF` control flow. Native pointers, 64-bit arithmetic, structures,
and C calling conventions provide the host integration.

## Behavior and operating contract

The plugin finds one licensing predicate in the host and changes its answer for
the exact, null-terminated `LUMINA` argument. Other arguments replay the original
entry instructions. Discovery uses exported symbols or a bounded scan of copied
module regions and corroborated call edges. Ambiguous candidates, unsupported
instructions and out-of-range branches are rejected.

Shutdown restores original bytes and exact page protections. Published replay
allocations remain mapped until process exit to protect in-flight calls. A
successful shutdown retires installation; restarting requires a new process.

**All affected code pages must be quiescent during startup and shutdown.** On
macOS, making code writable temporarily removes its execute permission. This
also affects unrelated functions sharing those pages. The lifecycle mutex
serializes `fl_start` and `fl_stop`; it does not suspend host threads. Direct
memory-mutation calls must be externally serialized with lifecycle operations.

The plugin must remain loaded for the host session. Arbitrary live hot-patching,
unloading while calls are active, and unwinding exceptions through a replay
buffer are outside the supported contract.

## Build

Requires CMake 3.24+, a C11 compiler and FreeBASIC 1.10.1 or newer with a matching
native runtime. Testing and packaging require Python 3.9+. The build generates C from BASIC in the build directory, then
compiles and links it with the native C toolchain.

```sh
make                         # Release library
make test                    # Debug build and tests
make release                 # Release build, tests and verified ZIP package
```

The default parallelism is two jobs; override with `JOBS=4`. Pass `FBC` if the
compiler is outside `PATH` and the local toolchain directory:

```sh
make release FBC=/absolute/path/to/fbc
```

Or configure directly:

```sh
cmake -S . -B build/release -DCMAKE_BUILD_TYPE=Release \
  -DFBC_EXECUTABLE=/absolute/path/to/fbc -DBUILD_TESTING=ON
cmake --build build/release --parallel 2
ctest --test-dir build/release --output-on-failure
python3 tools/package_release.py build/release
```

The library is `freelumina.dylib`, `freelumina.so` or `freelumina.dll`.
`FREEBASIC_RUNTIME` can override the matching static runtime path when it is not
in the compiler's reported library directory.

Release, RelWithDebInfo and MinSizeRel builds enable link-time optimization when
the C compiler and linker pass CMake's IPO probe. Unavailable IPO produces a
warning and falls back to normal compilation. Debug builds and test fixture
targets retain their normal optimization settings. To disable LTO explicitly:

```sh
make CMAKE_ARGS=-DFL_LTO=OFF
```

The profile retains `-fwrapv` and `-fno-strict-aliasing` for the generated C.
It does not enable CPU-specific instructions or fast-math. Measurements and
validation boundaries are described in [cmake/README.md](cmake/README.md).

### Local compiler

No Docker is used. If needed, bootstrap a compiler locally:

```sh
tools/bootstrap_freebasic.sh
make release
```

The script downloads and verifies a pinned source archive, builds without
system-wide installation and places the usable compiler/runtime in
`build/toolchain/native`. It reuses that compiler on subsequent runs. `JOBS`
controls bootstrap parallelism too.

Linux prerequisites: GCC, Make, curl, xz, ncurses development headers and libffi
development headers. On macOS, install GNU GCC and CMake (`brew install gcc cmake`).
The bootstrap uses GNU GCC for the pre-generated compiler's computed-goto code;
set `CC` to the desired GNU GCC executable if necessary.

On macOS, the portable Linux bootstrap C sources are built against the Darwin
runtime. That first-stage compiler reports a Linux host; CMake explicitly selects
the Darwin target for plugin code generation. This path is tested on macOS ARM64;
it is not an official FreeBASIC macOS binary distribution.

Windows x64 builds use an MSYS2 UCRT64 shell with GCC, CMake, Make, curl and xz.
Windows ARM64 is unavailable in the pinned runtime and is rejected by CMake.

The native CI matrix in [.github/workflows/build.yml](.github/workflows/build.yml)
contains five targets:

| Operating system | x86-64 | AArch64 |
| --- | --- | --- |
| Linux | Yes | Yes |
| macOS | Yes | Yes |
| Windows | Yes | Unsupported |

## Verification and release artifacts

Local macOS ARM64 Debug and Release verification covers:

- Public export, dependency and loadability checks.
- Semantic discovery and instruction-relocation fixtures.
- Independent x86-64 and AArch64 execution fixtures with Unicorn.
- Concurrent lifecycle calls, guarded strings, retirement and exact restoration.
- Memory page boundaries, protection restoration and conflicting ownership.

The cross-platform CI workflow runs native builds and verification on its listed
runners. Its presence does not certify an unexecuted CI run. Other platforms need
their native CI results before release; local syntax checks alone are insufficient.

For emulator tests:

```sh
python3 -m venv build/test-env
build/test-env/bin/python -m pip install -r tests/requirements.txt
cmake -S . -B build/release -DCMAKE_BUILD_TYPE=Release \
  -DFL_EMULATION_TESTS=ON -DBUILD_TESTING=ON \
  -DPython3_EXECUTABLE="$PWD/build/test-env/bin/python"
make release
```

Tagged CI releases retain the plugin-manager ZIP and tar.gz packaging flow,
including `ida-plugin.json`, installation instructions, documentation and runtime
license notices. Windows releases contain ZIP packages only.

`make release` packages only after rerunning the Release tests. Each ZIP includes
the library, documentation, runtime license notices, and a manifest containing
source hashes, the binary hash, target architecture, compiler version and runtime
dependencies. A SHA-256 sidecar accompanies the ZIP under `dist/`.

Only the 19 names in `src/exports.txt` are exported. BASIC implementation helpers
and the statically linked BASIC runtime remain private. Artifact validation
rejects unexpected exports and non-system dynamic dependencies.

## Source and editing

- `src/basic/freelumina.bas`: compilation entry point.
- `src/basic/core.bi`: shared ABI layouts and procedure declarations.
- `src/basic/fl_bytes.bas`, `fl_decode.bas`: byte arithmetic and bounded decoders.
- `src/basic/fl_search.bas`, `fl_patch.bas`: discovery and replay generation.
- `src/basic/fl_platform.bas`, `fl_lifecycle.bas`: OS bindings and lifecycle.
- `src/plugin.c`, `src/native_shims.c`: host descriptor, locking, logging and cache flush.

Run `python3 tools/renumber_basic.py` after editing BASIC statements. Numeric
`GOTO` destinations are preserved. Compiler directives and shared header
declarations remain unnumbered.

## Install

```sh
make install FBC=/absolute/path/to/fbc
```

This installs to the host's per-user plugin directory. Override the destination
with `PLUGINS=/your/plugin/directory`. Restart the host after installing; the
plugin registers as a hidden resident plugin and reports through the host console.
Installation does not constitute validation against a particular host release.

## Figure 1

```
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠠⠄⠍⠉⠂⡀⠀⠀⠀⠀⠀⡀⠂⠂⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠁⠀⠀⠀⠀⠀⠀⠀⠂⠀⠀⠠⠁⠀⠉⠁⠁⠒⠁⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⡅⠀⠀⠀⠀⠀⠀⠀⠀⠁⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡃⢐⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡠⠁⢰⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢐⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡂⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠂⠀⠀⠈⢆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠄⡀⡀⡀⢀⠀⣀⠄⠊⠀⠀⠀⠀⠀⠀⠉⡇⠂⠂⠂⠐⠀⠂⠈⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡂⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠡⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢐⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠠⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠨⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡂⠈⠁⠁⠁⠁⠄⠁⠂⠂⠠⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢆⠀⠀⠀⠀⠆⠀⠀⠀⡨⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠣⡀⠀⠀⠅⠀⠀⡠⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠁⠁⡃⠁⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
```

Figure 1 is the program insignia. Like the check it replaces, it is larger
than it needs to be, difficult to look away from, and standing in exactly
one place, reminding you what you paid for.
