project(ppmclibs CXX)
cmake_minimum_required(VERSION 3.3.0)

# find perl
find_program(PERL_PATH perl)
if (NOT PERL_PATH)
    message(FATAL_ERROR "Unable to find perl.")
endif ()
execute_process(
    COMMAND "${PERL_PATH}" -e "print(join(';', @INC))"
    OUTPUT_VARIABLE PERL_INCLUDE_PATHS
)
message(STATUS "Detected Perl include paths: ${PERL_INCLUDE_PATHS}")

# find Perl's header files
set(PERL_INCLUDE_DIRECTORY)
foreach(PERL_INCLUDE_PATH ${PERL_INCLUDE_PATHS})
    if (EXISTS "${PERL_INCLUDE_PATH}/CORE/EXTERN.h")
        set(PERL_INCLUDE_DIRECTORY "${PERL_INCLUDE_PATH}/CORE")
    endif ()
endforeach()
if (NOT PERL_INCLUDE_DIRECTORY)
    message(FATAL_ERROR "Unable to find Perl's header within ${PERL_INCLUDE_PATHS}.")
endif()

# find typemap file used by xsubpp
set(PERL_TYPEMAP)
foreach(PERL_INCLUDE_PATH ${PERL_INCLUDE_PATHS})
    if (EXISTS "${PERL_INCLUDE_PATH}/ExtUtils/typemap")
        set(PERL_TYPEMAP "${PERL_INCLUDE_PATH}/ExtUtils/typemap")
    endif ()
endforeach()
if (NOT PERL_TYPEMAP)
    message(FATAL_ERROR "Unable to find ExtUtils/typemap within ${PERL_INCLUDE_PATHS}.")
endif()

# make rule for invoking xsubpp
find_program(XSUBPP_PATH xsubpp)
if (NOT XSUBPP_PATH)
    message(FATAL_ERROR "Unable to find xsubpp.")
endif ()
set(PREPROCESSED_XS_FILE "${CMAKE_CURRENT_BINARY_DIR}/tinycv-xs.cpp")
add_custom_command(
    COMMENT "Preprocessing Perl XS file"
    COMMAND "${XSUBPP_PATH}" -C++
        -typemap "${PERL_TYPEMAP}"
        -typemap "${CMAKE_CURRENT_SOURCE_DIR}/typemap"
        "${CMAKE_CURRENT_SOURCE_DIR}/tinycv.xs"
        > "${PREPROCESSED_XS_FILE}"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tinycv.xs"
    OUTPUT "${PREPROCESSED_XS_FILE}"
)

# finally create the tinycv library
add_library(tinycv MODULE
    tinycv.h
    tinycv_ast2100.cc
    tinycv_impl.cc
    "${PREPROCESSED_XS_FILE}"
)
target_link_libraries(tinycv PRIVATE opencv_core opencv_imgcodecs)
target_include_directories(tinycv PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "${PERL_INCLUDE_DIRECTORY}")
target_compile_definitions(tinycv PRIVATE "-DVERSION=\"1.0\"" "-DXS_VERSION=\"1.0\"" "-D_LARGEFILE_SOURCE" "-D_FILE_OFFSET_BITS=64")