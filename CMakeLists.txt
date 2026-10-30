cmake_minimum_required(VERSION 3.24)
project(freelumina VERSION 3.0.0 LANGUAGES C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
option(FL_EMULATION_TESTS "Test generated instructions with Unicorn" OFF)
option(FL_LTO "Enable supported link-time optimization in optimized builds" ON)
set(FL_PLUGIN_INTERFACE_VERSION 900 CACHE STRING "Host plugin interface version")
find_package(Threads REQUIRED)
find_program(FBC_EXECUTABLE NAMES fbc
  HINTS "${CMAKE_CURRENT_SOURCE_DIR}/build/toolchain/native/bin" REQUIRED)
execute_process(COMMAND "${FBC_EXECUTABLE}" -version
  OUTPUT_VARIABLE FL_COMPILER_INFO COMMAND_ERROR_IS_FATAL ANY)
string(REGEX MATCH "Version ([0-9]+\\.[0-9]+\\.[0-9]+)" FL_COMPILER_MATCH "${FL_COMPILER_INFO}")
set(FL_COMPILER_VERSION "${CMAKE_MATCH_1}")
if(NOT FL_COMPILER_VERSION OR FL_COMPILER_VERSION VERSION_LESS "1.10.1")
  message(FATAL_ERROR "FreeBASIC 1.10.1 or newer is required")
endif()

include(CheckCSourceCompiles)
check_c_source_compiles("#if !defined(__aarch64__) && !defined(_M_ARM64)\n#error not ARM64\n#endif\nint main(void) { return 0; }" FL_TARGET_ARM64)
if(FL_TARGET_ARM64)
  set(FL_ARCH_DEFINITION FL_ARCH_ARM64)
  set(FL_CPU aarch64)
else()
  check_c_source_compiles("#if !defined(__x86_64__) && !defined(_M_X64)\n#error not x64\n#endif\nint main(void) { return 0; }" FL_TARGET_X64)
  if(NOT FL_TARGET_X64)
    message(FATAL_ERROR "Only AArch64 and x86-64 are supported")
  endif()
  set(FL_ARCH_DEFINITION FL_ARCH_X64)
  set(FL_CPU x86_64)
endif()
if(WIN32)
  if(FL_TARGET_ARM64)
    message(FATAL_ERROR "FreeBASIC 1.10.1 has no Windows ARM64 runtime; use an x64 host build")
  endif()
  set(FL_OS_DEFINITION FL_OS_WINDOWS)
  set(FL_BASIC_TARGET win64)
elseif(APPLE)
  set(FL_OS_DEFINITION FL_OS_MACOS)
  set(FL_BASIC_TARGET darwin-${FL_CPU})
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(FL_OS_DEFINITION FL_OS_LINUX)
  set(FL_BASIC_TARGET linux-${FL_CPU})
else()
  message(FATAL_ERROR "Supported platforms: Windows x64, Linux and macOS x64/ARM64")
endif()

# Compile numbered BASIC with the C backend, then let the native C toolchain
# own object generation and linking.
execute_process(COMMAND "${FBC_EXECUTABLE}" -target ${FL_BASIC_TARGET} -print fblibdir
  OUTPUT_VARIABLE FL_RUNTIME_DIR OUTPUT_STRIP_TRAILING_WHITESPACE
  COMMAND_ERROR_IS_FATAL ANY)
find_library(FREEBASIC_RUNTIME NAMES fbmtpic fbmt
  HINTS "${FL_RUNTIME_DIR}" NO_DEFAULT_PATH REQUIRED)
file(GLOB FL_BASIC_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/basic/*.bas" "${CMAKE_CURRENT_SOURCE_DIR}/src/basic/*.bi")
set(FL_GENERATED_C "${CMAKE_CURRENT_BINARY_DIR}/freelumina_core.c")
add_custom_command(OUTPUT "${FL_GENERATED_C}"
  COMMAND "${FBC_EXECUTABLE}" -lang fblite -target ${FL_BASIC_TARGET}
    -gen gcc -r -mt -dylib
    -d ${FL_ARCH_DEFINITION} -d ${FL_OS_DEFINITION}
    -i "${CMAKE_CURRENT_SOURCE_DIR}/src/basic"
    -o "${CMAKE_CURRENT_BINARY_DIR}/freelumina_core.o"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/basic/freelumina.bas"
  DEPENDS ${FL_BASIC_SOURCES} "${FBC_EXECUTABLE}"
  VERBATIM)
add_library(freelumina SHARED "${FL_GENERATED_C}" src/native_shims.c src/plugin.c)
set_target_properties(freelumina PROPERTIES PREFIX "")
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/src/exports.txt" FL_EXPORTS)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "src/exports.txt")
if(APPLE)
  set(FL_EXPORT_FILE "${CMAKE_CURRENT_BINARY_DIR}/freelumina.exports")
  set(FL_EXPORT_CONTENT "")
  foreach(symbol IN LISTS FL_EXPORTS)
    string(APPEND FL_EXPORT_CONTENT "_${symbol}\n")
  endforeach()
  file(WRITE "${FL_EXPORT_FILE}" "${FL_EXPORT_CONTENT}")
  target_link_options(freelumina PRIVATE "-Wl,-exported_symbols_list,${FL_EXPORT_FILE}" -Wl,-dead_strip)
elseif(WIN32)
  string(JOIN "\n" FL_EXPORT_CONTENT ${FL_EXPORTS})
  set(FL_EXPORT_FILE "${CMAKE_CURRENT_BINARY_DIR}/freelumina.def")
  file(WRITE "${FL_EXPORT_FILE}" "EXPORTS\n${FL_EXPORT_CONTENT}\n")
  target_sources(freelumina PRIVATE "${FL_EXPORT_FILE}")
  if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
    target_link_options(freelumina PRIVATE -static-libgcc -Wl,--dynamicbase,--nxcompat)
  endif()
else()
  set(FL_EXPORT_FILE "${CMAKE_CURRENT_BINARY_DIR}/freelumina.exports")
  string(JOIN ";\n  " FL_EXPORT_CONTENT ${FL_EXPORTS})
  file(WRITE "${FL_EXPORT_FILE}" "{ global:\n  ${FL_EXPORT_CONTENT};\nlocal: *; };\n")
  target_link_options(freelumina PRIVATE "-Wl,--version-script=${FL_EXPORT_FILE}"
    -Wl,--gc-sections,-z,relro,-z,now,--no-undefined)
endif()
set_property(TARGET freelumina APPEND PROPERTY LINK_DEPENDS "${FL_EXPORT_FILE}")
target_include_directories(freelumina PUBLIC src)
target_compile_definitions(freelumina PRIVATE FL_BUILDING_LIBRARY
  FL_INTERFACE_VERSION=${FL_PLUGIN_INTERFACE_VERSION} ${FL_ARCH_DEFINITION} ${FL_OS_DEFINITION})
target_link_libraries(freelumina PRIVATE "${FREEBASIC_RUNTIME}" Threads::Threads ${CMAKE_DL_LIBS})
if(WIN32)
  target_link_libraries(freelumina PRIVATE winmm)
endif()
if(UNIX)
  find_library(FL_TERMINAL_LIBRARY NAMES ncurses tinfo curses REQUIRED)
  target_link_libraries(freelumina PRIVATE "${FL_TERMINAL_LIBRARY}" m)
endif()
if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(freelumina PRIVATE -fwrapv -fno-strict-aliasing
    -ffunction-sections -fdata-sections "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=.")
  set_source_files_properties(src/plugin.c src/native_shims.c PROPERTIES
    COMPILE_OPTIONS "-Wall;-Wextra;-Wconversion;-Werror")
  # Suppress only C-backend bookkeeping warnings; retain semantic warnings.
  set(FL_GENERATED_WARNINGS -Wall -Wextra -Wno-unused-variable
    -Wno-unused-label -Wno-unused-but-set-variable)
  if(CMAKE_C_COMPILER_ID MATCHES "Clang")
    list(APPEND FL_GENERATED_WARNINGS -Wno-incompatible-library-redeclaration)
  else()
    list(APPEND FL_GENERATED_WARNINGS -Wno-builtin-declaration-mismatch)
  endif()
  set_source_files_properties("${FL_GENERATED_C}" PROPERTIES
    COMPILE_OPTIONS "${FL_GENERATED_WARNINGS}")
endif()

include(cmake/Optimize.cmake)

include(CTest)

if(BUILD_TESTING)
  find_package(Python3 3.9 COMPONENTS Interpreter REQUIRED)

  add_test(NAME basic_source_format
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/renumber_basic.py --check)

  add_test(NAME artifact_contract
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/check_artifact.py
      $<TARGET_FILE:freelumina>)

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
  target_link_libraries(native_lifecycle PRIVATE freelumina Threads::Threads)
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

install(TARGETS freelumina LIBRARY DESTINATION . RUNTIME DESTINATION .)

file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/release-$<CONFIG>.json"
  CONTENT "{\n  \"version\": \"${PROJECT_VERSION}\",\n  \"configuration\": \"$<CONFIG>\",\n  \"system\": \"${CMAKE_SYSTEM_NAME}\",\n  \"architecture\": \"${FL_CPU}\",\n  \"freebasic\": \"${FL_COMPILER_VERSION}\",\n  \"library\": \"$<TARGET_FILE_NAME:freelumina>\"\n}\n")
