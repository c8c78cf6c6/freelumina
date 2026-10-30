cmake_minimum_required(VERSION 3.24)

# On macOS, prefer a conventional Homebrew compiler over other PATH entries.
# Explicit compiler selections and toolchains retain control of discovery.
if(CMAKE_HOST_APPLE AND NOT DEFINED CMAKE_Fortran_COMPILER
    AND "$ENV{FC}" STREQUAL ""
    AND NOT DEFINED CMAKE_SYSTEM_NAME
    AND NOT DEFINED CMAKE_TOOLCHAIN_FILE
    AND "$ENV{CMAKE_TOOLCHAIN_FILE}" STREQUAL "")
  find_program(FL_HOMEBREW_FORTRAN NAMES gfortran
    PATHS /opt/homebrew/bin /usr/local/bin NO_DEFAULT_PATH NO_CACHE)
  if(FL_HOMEBREW_FORTRAN)
    set(CMAKE_Fortran_COMPILER "${FL_HOMEBREW_FORTRAN}" CACHE FILEPATH "Fortran compiler")
  endif()
endif()

project(freelumina VERSION 2.0.0 LANGUAGES C Fortran)

# ---------------------------------------------------------------------------
# Global settings
# ---------------------------------------------------------------------------
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_Fortran_STANDARD 2008)
set(CMAKE_Fortran_STANDARD_REQUIRED ON)
set(CMAKE_Fortran_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/modules")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(FL_RUNTIME_CHECKS "Enable GNU Fortran bounds/runtime checks" OFF)
option(FL_EMULATION_TESTS "Test generated code with Unicorn (Python test dependency)" OFF)
option(FL_AGGRESSIVE_OPTIMIZATION "Aggressively inline C and Fortran in optimized builds" ON)
option(FL_LTO "Use compatible compiler/linker LTO in optimized builds" ON)
set(FL_PLUGIN_INTERFACE_VERSION 900 CACHE STRING "Plugin interface version")

find_package(Threads REQUIRED)

# ---------------------------------------------------------------------------
# Target architecture
# ---------------------------------------------------------------------------
include(CheckCSourceCompiles)

check_c_source_compiles(
  "#if !defined(__aarch64__) && !defined(_M_ARM64)\n#error not ARM64\n#endif\nint main(void) { return 0; }"
  FL_TARGET_ARM64)
if(FL_TARGET_ARM64)
  set(FL_ARCH_DEFINITION FL_ARCH_ARM64)
else()
  check_c_source_compiles(
    "#if !defined(__x86_64__) && !defined(_M_X64)\n#error not x86-64\n#endif\nint main(void) { return 0; }"
    FL_TARGET_X64)
  if(NOT FL_TARGET_X64)
    message(FATAL_ERROR "Only AArch64 and x86-64 are supported")
  endif()
  set(FL_ARCH_DEFINITION FL_ARCH_X64)
endif()

# ---------------------------------------------------------------------------
# Target operating system
# ---------------------------------------------------------------------------
if(WIN32)
  set(FL_OS_DEFINITION FL_OS_WINDOWS)
elseif(APPLE)
  set(FL_OS_DEFINITION FL_OS_MACOS)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(FL_OS_DEFINITION FL_OS_LINUX)
else()
  message(FATAL_ERROR "Supported operating systems: Windows, macOS, Linux")
endif()

# ---------------------------------------------------------------------------
# Main library
# ---------------------------------------------------------------------------
set(FL_FORTRAN_SOURCES
  src/fl_abi.f90
  src/fl_bytes.f90
  src/fl_decode.f90
  src/fl_search.f90
  src/fl_patch.f90
  src/fl_platform.F90
  src/fl_lifecycle.f90)

add_library(freelumina SHARED
  ${FL_FORTRAN_SOURCES}
  src/native_shims.c
  src/plugin.c)

target_compile_definitions(freelumina PRIVATE
  FL_INTERFACE_VERSION=${FL_PLUGIN_INTERFACE_VERSION}
  FL_BUILDING_LIBRARY
  ${FL_ARCH_DEFINITION}
  ${FL_OS_DEFINITION})

set_target_properties(freelumina PROPERTIES
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)

# MinGW and LLVM-MinGW: a single explicit dllexport in any object disables the
# linker's automatic symbol export, and the Fortran compiler cannot express
# dllexport. Force full export so the C ABI stays reachable from the test
# fixtures and from ctypes.
if(WIN32 AND CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  target_link_options(freelumina PRIVATE "-Wl,--export-all-symbols")
endif()

# MinGW: keep the Fortran runtime inside the library. A DLL that imports
# libgfortran-*.dll cannot be loaded anywhere without the toolchain's bin
# directory on PATH, which neither the test harness nor a plugin host has.
if(WIN32 AND CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  target_link_options(freelumina PRIVATE -static)
endif()

target_include_directories(freelumina PUBLIC src)
target_link_libraries(freelumina PRIVATE Threads::Threads ${CMAKE_DL_LIBS})

include(cmake/Optimize.cmake)

# ---------------------------------------------------------------------------
# Compiler warnings
# ---------------------------------------------------------------------------
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  set(FL_PREFIX_MAP "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=.")
  target_compile_options(freelumina PRIVATE
    $<$<COMPILE_LANGUAGE:Fortran>:-Wall>
    $<$<COMPILE_LANGUAGE:Fortran>:-Wextra>
    $<$<COMPILE_LANGUAGE:Fortran>:-Wimplicit-interface>
    $<$<COMPILE_LANGUAGE:Fortran>:-Werror=line-truncation>
    # Absolute source paths are recorded in runtime diagnostics; map them to
    # relative paths so artifacts do not leak the build machine's layout.
    $<$<COMPILE_LANGUAGE:Fortran>:${FL_PREFIX_MAP}>)
  if(FL_RUNTIME_CHECKS)
    target_compile_options(freelumina PRIVATE
      $<$<COMPILE_LANGUAGE:Fortran>:-fcheck=all>
      $<$<COMPILE_LANGUAGE:Fortran>:-fbacktrace>)
  endif()
endif()

if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
  set(FL_PREFIX_MAP "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=.")
  target_compile_options(freelumina PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-Wall>
    $<$<COMPILE_LANGUAGE:C>:-Wextra>
    $<$<COMPILE_LANGUAGE:C>:-Wconversion>
    $<$<COMPILE_LANGUAGE:C>:${FL_PREFIX_MAP}>)
endif()

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
include(CTest)

if(BUILD_TESTING)
  find_package(Python3 COMPONENTS Interpreter REQUIRED)

  add_test(NAME semantic_and_relocation
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_core.py
      $<TARGET_FILE:freelumina>)

  if(FL_EMULATION_TESTS)
    execute_process(COMMAND ${Python3_EXECUTABLE} -c "import unicorn"
      RESULT_VARIABLE FL_UNICORN_IMPORT)
    if(NOT FL_UNICORN_IMPORT EQUAL 0)
      message(FATAL_ERROR "FL_EMULATION_TESTS requires Unicorn in the selected Python interpreter")
    endif()
    add_test(NAME emulated_execution
      COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_execution.py
        $<TARGET_FILE:freelumina>)
  endif()

  add_executable(native_lifecycle tests/native_lifecycle.c)
  # This fixture needs a decoder-supported entry prologue in every build type.
  # Optimize the library under test, while retaining the Debug fixture shape.
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(native_lifecycle PRIVATE -O0)
  elseif(MSVC)
    target_compile_options(native_lifecycle PRIVATE /Od)
  endif()
  target_link_libraries(native_lifecycle PRIVATE freelumina)
  if(APPLE)
    target_link_options(native_lifecycle PRIVATE -Wl,-export_dynamic)
  elseif(UNIX)
    target_link_options(native_lifecycle PRIVATE -rdynamic)
  endif()
  add_test(NAME native_lifecycle COMMAND native_lifecycle)

  add_executable(platform_memory tests/platform_memory.c)
  target_link_libraries(platform_memory PRIVATE freelumina)
  add_test(NAME platform_memory COMMAND platform_memory)
endif()

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install(TARGETS freelumina LIBRARY DESTINATION . RUNTIME DESTINATION .)
