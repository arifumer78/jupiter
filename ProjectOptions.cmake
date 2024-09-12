include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(jupiter_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(jupiter_setup_options)
  option(jupiter_ENABLE_HARDENING "Enable hardening" ON)
  option(jupiter_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    jupiter_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    jupiter_ENABLE_HARDENING
    OFF)

  jupiter_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR jupiter_PACKAGING_MAINTAINER_MODE)
    option(jupiter_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(jupiter_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(jupiter_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(jupiter_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(jupiter_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(jupiter_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(jupiter_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(jupiter_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(jupiter_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(jupiter_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(jupiter_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(jupiter_ENABLE_PCH "Enable precompiled headers" OFF)
    option(jupiter_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(jupiter_ENABLE_IPO "Enable IPO/LTO" ON)
    option(jupiter_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(jupiter_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(jupiter_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(jupiter_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(jupiter_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(jupiter_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(jupiter_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(jupiter_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(jupiter_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(jupiter_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(jupiter_ENABLE_PCH "Enable precompiled headers" OFF)
    option(jupiter_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      jupiter_ENABLE_IPO
      jupiter_WARNINGS_AS_ERRORS
      jupiter_ENABLE_USER_LINKER
      jupiter_ENABLE_SANITIZER_ADDRESS
      jupiter_ENABLE_SANITIZER_LEAK
      jupiter_ENABLE_SANITIZER_UNDEFINED
      jupiter_ENABLE_SANITIZER_THREAD
      jupiter_ENABLE_SANITIZER_MEMORY
      jupiter_ENABLE_UNITY_BUILD
      jupiter_ENABLE_CLANG_TIDY
      jupiter_ENABLE_CPPCHECK
      jupiter_ENABLE_COVERAGE
      jupiter_ENABLE_PCH
      jupiter_ENABLE_CACHE)
  endif()

  jupiter_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (jupiter_ENABLE_SANITIZER_ADDRESS OR jupiter_ENABLE_SANITIZER_THREAD OR jupiter_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(jupiter_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(jupiter_global_options)
  if(jupiter_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    jupiter_enable_ipo()
  endif()

  jupiter_supports_sanitizers()

  if(jupiter_ENABLE_HARDENING AND jupiter_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR jupiter_ENABLE_SANITIZER_UNDEFINED
       OR jupiter_ENABLE_SANITIZER_ADDRESS
       OR jupiter_ENABLE_SANITIZER_THREAD
       OR jupiter_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${jupiter_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${jupiter_ENABLE_SANITIZER_UNDEFINED}")
    jupiter_enable_hardening(jupiter_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(jupiter_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(jupiter_warnings INTERFACE)
  add_library(jupiter_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  jupiter_set_project_warnings(
    jupiter_warnings
    ${jupiter_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(jupiter_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    jupiter_configure_linker(jupiter_options)
  endif()

  include(cmake/Sanitizers.cmake)
  jupiter_enable_sanitizers(
    jupiter_options
    ${jupiter_ENABLE_SANITIZER_ADDRESS}
    ${jupiter_ENABLE_SANITIZER_LEAK}
    ${jupiter_ENABLE_SANITIZER_UNDEFINED}
    ${jupiter_ENABLE_SANITIZER_THREAD}
    ${jupiter_ENABLE_SANITIZER_MEMORY})

  set_target_properties(jupiter_options PROPERTIES UNITY_BUILD ${jupiter_ENABLE_UNITY_BUILD})

  if(jupiter_ENABLE_PCH)
    target_precompile_headers(
      jupiter_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(jupiter_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    jupiter_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(jupiter_ENABLE_CLANG_TIDY)
    jupiter_enable_clang_tidy(jupiter_options ${jupiter_WARNINGS_AS_ERRORS})
  endif()

  if(jupiter_ENABLE_CPPCHECK)
    jupiter_enable_cppcheck(${jupiter_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(jupiter_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    jupiter_enable_coverage(jupiter_options)
  endif()

  if(jupiter_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(jupiter_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(jupiter_ENABLE_HARDENING AND NOT jupiter_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR jupiter_ENABLE_SANITIZER_UNDEFINED
       OR jupiter_ENABLE_SANITIZER_ADDRESS
       OR jupiter_ENABLE_SANITIZER_THREAD
       OR jupiter_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    jupiter_enable_hardening(jupiter_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
