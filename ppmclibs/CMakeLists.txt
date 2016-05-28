project(ppmclibs NONE)
cmake_minimum_required(VERSION 3.3.0)

set(PERL_MODULE ${CMAKE_CURRENT_SOURCE_DIR}/blib/arch/auto/tinycv/tinycv.so)
add_custom_command(OUTPUT Makefile
    COMMAND perl Makefile.PL OPTIMIZE="${CMAKE_CXX_FLAGS}"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)
add_custom_command(OUTPUT ${PERL_MODULE}
    COMMAND make
    COMMAND make
    DEPENDS Makefile
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
add_custom_target(build ALL DEPENDS ${PERL_MODULE})
add_custom_target(install-exec-local
    COMMAND echo TODO make pure_install DESTDIR="${DESTDIR}" # INSTALLDIRS="${INSTALLDIRS}"
    DEPENDS ${PERL_MODULE})
