# Keep the generated BASIC core and C adapters in the same optimization unit
# at link time. Do not apply IPO to the deliberately unoptimized test fixtures.
if(FL_LTO)
  include(CheckIPOSupported)
  check_ipo_supported(RESULT FL_IPO_SUPPORTED OUTPUT FL_IPO_ERROR LANGUAGES C)
  if(FL_IPO_SUPPORTED)
    set_target_properties(freelumina PROPERTIES
      INTERPROCEDURAL_OPTIMIZATION_RELEASE ON
      INTERPROCEDURAL_OPTIMIZATION_RELWITHDEBINFO ON
      INTERPROCEDURAL_OPTIMIZATION_MINSIZEREL ON)
    message(STATUS "FREELUMINA: C link-time optimization enabled for optimized builds")
  else()
    message(WARNING "FREELUMINA: C link-time optimization unavailable; using normal compilation. ${FL_IPO_ERROR}")
  endif()
endif()
