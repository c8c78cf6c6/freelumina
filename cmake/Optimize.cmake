# Keep Debug/runtime-check builds available; flatten only optimized configurations.
set(FL_OPTIMIZED_CONFIG "$<OR:$<CONFIG:Release>,$<CONFIG:RelWithDebInfo>>")

if(FL_AGGRESSIVE_OPTIMIZATION)
  set(FL_GNU_OPTIMIZATION_FLAGS
    -O3 -funroll-loops -finline-functions -fno-semantic-interposition
    --param=max-inline-insns-single=100000
    --param=max-inline-insns-auto=100000
    --param=inline-unit-growth=1000
    --param=large-function-growth=1000)
  # One Fortran compilation unit also permits cross-module inlining when the
  # selected C and Fortran compilers use incompatible LTO representations.
  set(FL_FORTRAN_UNITY "")
  foreach(source IN LISTS FL_FORTRAN_SOURCES)
    string(APPEND FL_FORTRAN_UNITY "#include \"${CMAKE_CURRENT_SOURCE_DIR}/${source}\"\n")
  endforeach()
  file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/freelumina_core.F90"
    CONTENT "${FL_FORTRAN_UNITY}")
  get_target_property(FL_TARGET_SOURCES freelumina SOURCES)
  list(REMOVE_ITEM FL_TARGET_SOURCES ${FL_FORTRAN_SOURCES})
  set_property(TARGET freelumina PROPERTY SOURCES "${FL_TARGET_SOURCES}")
  target_sources(freelumina PRIVATE
    "$<${FL_OPTIMIZED_CONFIG}:${CMAKE_CURRENT_BINARY_DIR}/freelumina_core.F90>")
  foreach(source IN LISTS FL_FORTRAN_SOURCES)
    target_sources(freelumina PRIVATE "$<$<NOT:${FL_OPTIMIZED_CONFIG}>:${source}>")
  endforeach()

  foreach(language C Fortran)
    if(CMAKE_${language}_COMPILER_ID STREQUAL "GNU")
      target_compile_options(freelumina PRIVATE
        "$<$<AND:${FL_OPTIMIZED_CONFIG},$<COMPILE_LANGUAGE:${language}>>:${FL_GNU_OPTIMIZATION_FLAGS}>")
    elseif(CMAKE_${language}_COMPILER_ID STREQUAL "LLVMFlang")
      target_compile_options(freelumina PRIVATE
        "$<$<AND:${FL_OPTIMIZED_CONFIG},$<COMPILE_LANGUAGE:${language}>>:-O3;-mllvm;-inline-threshold=100000>")
    elseif(CMAKE_${language}_COMPILER_ID MATCHES "Clang")
      # LLVM exposes the inlining budget through its backend option interface.
      target_compile_options(freelumina PRIVATE
        "$<$<AND:${FL_OPTIMIZED_CONFIG},$<COMPILE_LANGUAGE:${language}>>:-O3;-funroll-loops;-mllvm;-inline-threshold=100000>")
    elseif(CMAKE_${language}_COMPILER_ID STREQUAL "MSVC")
      target_compile_options(freelumina PRIVATE
        "$<$<AND:${FL_OPTIMIZED_CONFIG},$<COMPILE_LANGUAGE:${language}>>:/O2;/Ob3>")
    else()
      message(WARNING "No aggressive optimization profile for ${language}: ${CMAKE_${language}_COMPILER_ID}")
    endif()
  endforeach()
  if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    # LTO's final inliner must receive the same budgets as the frontend.
    target_link_options(freelumina PRIVATE "$<${FL_OPTIMIZED_CONFIG}:${FL_GNU_OPTIMIZATION_FLAGS}>")
  endif()

  # Preserve the named C interface but allow LTO to discard Fortran module
  # implementation symbols, including compiler-generated type helpers.
  if(APPLE)
    target_link_options(freelumina PRIVATE
      "$<${FL_OPTIMIZED_CONFIG}:-Wl,-dead_strip,-exported_symbol,_fl_*,-exported_symbol,_PLUGIN>")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/freelumina.exports"
      CONTENT "{ global: fl_*; PLUGIN; local: *; };\n")
    target_link_options(freelumina PRIVATE
      "$<${FL_OPTIMIZED_CONFIG}:-Wl,--version-script=${CMAKE_CURRENT_BINARY_DIR}/freelumina.exports>")
  endif()
endif()

if(FL_LTO AND WIN32 AND FL_TARGET_X64 AND
    CMAKE_C_COMPILER_ID STREQUAL "GNU" AND CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  # With GNU LTO, automatic exports can classify Fortran functions as data
  # imports, producing out-of-range call pseudo-relocations in x64 clients.
  set_target_properties(freelumina PROPERTIES
    INTERPROCEDURAL_OPTIMIZATION_RELEASE OFF
    INTERPROCEDURAL_OPTIMIZATION_RELWITHDEBINFO OFF)
  message(STATUS "FREELUMINA: Windows x64 GNU LTO disabled; Fortran unity inlining is available")
elseif(FL_LTO)
  # GNU GIMPLE and LLVM bitcode cannot participate in the same LTO link.
  # Even matching compiler families may lack linker support: probe both.
  string(REGEX MATCH "^[0-9]+" FL_C_COMPILER_MAJOR "${CMAKE_C_COMPILER_VERSION}")
  string(REGEX MATCH "^[0-9]+" FL_FORTRAN_COMPILER_MAJOR "${CMAKE_Fortran_COMPILER_VERSION}")
  if(FL_C_COMPILER_MAJOR STREQUAL FL_FORTRAN_COMPILER_MAJOR AND
      ((CMAKE_C_COMPILER_ID STREQUAL "GNU" AND CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
      OR (CMAKE_C_COMPILER_ID STREQUAL "Clang" AND CMAKE_Fortran_COMPILER_ID STREQUAL "LLVMFlang")))
    include(CheckIPOSupported)
    check_ipo_supported(RESULT FL_IPO_SUPPORTED OUTPUT FL_IPO_ERROR LANGUAGES C Fortran)
    if(FL_IPO_SUPPORTED)
      set_target_properties(freelumina PROPERTIES
        INTERPROCEDURAL_OPTIMIZATION_RELEASE ON
        INTERPROCEDURAL_OPTIMIZATION_RELWITHDEBINFO ON)
      if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
        # Give the whole Fortran core one link-time optimization partition.
        target_link_options(freelumina PRIVATE "$<${FL_OPTIMIZED_CONFIG}:-O3;-flto-partition=one>")
      endif()
      message(STATUS "FREELUMINA: release C/Fortran LTO enabled")
    else()
      message(WARNING "FREELUMINA: LTO unavailable; using compilation-unit optimization. ${FL_IPO_ERROR}")
    endif()
  else()
    message(STATUS "FREELUMINA: mixed compiler LTO disabled; Fortran unity inlining is available")
  endif()
endif()
