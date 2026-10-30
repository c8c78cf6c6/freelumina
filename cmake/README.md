# BASIC build optimization

The BASIC compiler emits one C translation unit. CMake's C compiler owns its
optimization and linking; FreeBASIC's `-O` option only selects the downstream
compiler optimization level and adds no optimization to this `-r` generation
step in the pinned compiler. CMake already supplies `-O3` for GNU/Clang Release
builds. Adding another `-O3` to the generator does not change that build.

`FL_LTO=ON` probes the selected C compiler/linker using `CheckIPOSupported` and
enables IPO only for the `freelumina` target in Release, RelWithDebInfo and
MinSizeRel. CMake selects the compiler's LTO flags. Debug and the native test
fixture targets are excluded. Unsupported IPO emits a warning and uses normal
compilation. `-DFL_LTO=OFF` disables this feature without changing global flags.

Keep `-fwrapv` and `-fno-strict-aliasing`: the generated C uses integer and
pointer representations inherited from BASIC. The export allowlist, section
garbage collection and platform linker settings remain active. The runtime
archive contains ordinary objects; LTO does not re-optimize that runtime.

## Local measurements

On an Apple M4 Max running macOS AArch64 with AppleClang 21.0.0 and FreeBASIC
1.10.1, a native C harness
called the public decoder and replay planner directly. Each sample ran
4,000,000 decoder calls per architecture and 400,000 planner calls per
architecture, cycling through eight fixed instruction forms. Results below
are medians of nine runs per profile, interleaved in deterministic shuffled
order. Time is process CPU time per call, measured with C `clock()`; it includes
the harness loop. The binaries produced identical aggregate checksums.
Percentage reduction is `100 * (baseline - LTO) / baseline`. With the local
1 microsecond clock tick, a two-tick endpoint uncertainty contributes at most
0.0005 ns per decoder call or 0.005 ns per planner call. The observed run
ranges below include substantially larger execution variation.

| Metric | Release baseline | LTO | Observed reduction |
| --- | ---: | ---: | ---: |
| x86-64 decode | 12.341 ns | 10.302 ns | 16.5% |
| AArch64 decode | 3.585 ns | 3.341 ns | 6.8% |
| x86-64 replay plan | 309.478 ns | 305.673 ns | 1.2% |
| AArch64 replay plan | 305.683 ns | 302.827 ns | 0.9% |
| Library size | 87,264 bytes | 87,376 bytes | -0.13% |

The baseline/LTO ranges were 12.189-12.565/10.024-10.688 ns for x86-64
decode and 3.435-3.741/3.263-3.381 ns for AArch64 decode. Planner ranges
overlapped, so their small median differences do not establish a speedup.
The library grew by 112 bytes. A third profile added `-funroll-loops` and
LLVM `-inline-threshold=1000`; it did not consistently improve on LTO alone
and is not enabled.

Raw samples, the harness source and profile build logs are local artifacts in
`build/basic-optimization/`; they are not required for builds or distribution.

The six existing checks passed in each of these cases: Release, Debug,
RelWithDebInfo, MinSizeRel, Release with LTO disabled, Release with simulated
IPO rejection, and Debug/Release in one Ninja Multi-Config build directory.
The rejection test used a compiler wrapper that refused `-flto` while
delegating ordinary compilation to AppleClang; the resulting fallback library
passed the same checks. Build rules were inspected to confirm the intended
core IPO flags and the absence of IPO on the native lifecycle fixture.
Release packaging also passed its export, dependency and loadability checks.

## Assumptions and verification boundaries

| Assumption | Dependent result | Falsification probe |
| --- | --- | --- |
| The fixed instruction mix represents some decoder work | Reported microbenchmark reductions | Rerun with target-derived instruction distributions and startup traces |
| The selected compiler/linker supports working IPO | Optimized configurations | CMake compile/link probe followed by all six semantic, emulator, lifecycle, memory and artifact checks |
| Public behavior survives link-time optimization | Enabling LTO by default | Compare public exports, dependencies, test outcomes and benchmark checksums against the baseline |

These measurements do not establish host startup improvements or performance
on Linux, Windows, x86-64 hardware, or other compiler versions. Native CI
remains the cross-platform validation boundary. No live host validation was
performed for this build-setting change.

Scope finding [medium]: this pipeline's static FreeBASIC runtime remains
outside the LTO optimization scope; runtime-heavy paths may see little change.
Scope finding [low]: more aggressive inlining increased tuning complexity
without a consistent measured gain in this instruction mix.
