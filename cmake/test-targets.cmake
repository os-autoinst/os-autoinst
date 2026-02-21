cmake_minimum_required(VERSION 3.17.0)

enable_testing()

# enable verbose CTest output by default
# note: We're mainly using prove which already provides a condensed output by default. To be able
#       to follow the prove output as usual and configure the test verbosity on prove-level it makes
#       sense to configure CTest to be verbose by default.
option(VERBOSE_CTEST "enables verbose tests on CTest level" ON)
if (VERBOSE_CTEST)
    set(CMAKE_CTEST_COMMAND ${CMAKE_CTEST_COMMAND} -V)
endif ()

# test for install target
add_test(
    NAME test-installed-files
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-installed-files" "${CMAKE_MAKE_PROGRAM}"
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# add targets for invoking Perl test suite
find_program(PROVE_PATH prove)
find_program(UNBUFFER_PATH unbuffer)
if (PROVE_PATH)
    set(INVOKE_TEST_ARGS --prove-tool "${PROVE_PATH}" --make-tool "${CMAKE_MAKE_PROGRAM}" --unbuffer-tool "${UNBUFFER_PATH}" --build-directory "${CMAKE_CURRENT_BINARY_DIR}")
    add_test(
        NAME test-perl-testsuite
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/invoke-tests" ${INVOKE_TEST_ARGS}
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    set_tests_properties(test-perl-testsuite
        PROPERTIES ENVIRONMENT "TESTS=t")
    add_test(
        NAME test-local-author-perl
        COMMAND "${PROVE_PATH}" xt
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set PROVE_PATH to the path of the prove executable to enable running the Perl testsuite.")
endif ()

# add build system targets for invoking specific tests
add_custom_target(test-local-author-perl COMMAND ${CMAKE_CTEST_COMMAND} -R "test-local-author-perl" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_custom_target(test-local COMMAND ${CMAKE_CTEST_COMMAND} -R "test-local-.*" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_custom_target(test-doc COMMAND ${CMAKE_CTEST_COMMAND} -R "test-doc-.*" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_custom_target(test-installed-files COMMAND ${CMAKE_CTEST_COMMAND} -R "test-installed-files" WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
if (PROVE_PATH)
    add_custom_target(test-perl-testsuite
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/invoke-tests" ${INVOKE_TEST_ARGS}
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        USES_TERMINAL
    )
endif ()
add_custom_target(check COMMAND ${CMAKE_CTEST_COMMAND} WORKING_DIRECTORY ${CMAKE_BINARY_DIR} USES_TERMINAL)
add_custom_target(check-pkg-build COMMAND ${CMAKE_CTEST_COMMAND} -E "test-local-.*" WORKING_DIRECTORY ${CMAKE_BINARY_DIR} USES_TERMINAL)
foreach (CUSTOM_TARGET test-perl-testsuite check check-pkg-build)
    add_dependencies(${CUSTOM_TARGET} symlinks)
endforeach ()

# add target for computing test coverage of Perl test suite
find_program(COVER_PATH cover)
if (COVER_PATH AND PROVE_PATH)
    add_custom_command(
        COMMENT "Run Perl testsuite with coverage instrumentation if no coverage data has been collected so far"
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/invoke-tests" --coverage --skip-if-cover-db-exists ${INVOKE_TEST_ARGS}
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_custom_command(
        COMMENT "Generate coverage report (HTML)"
        COMMAND "${COVER_PATH}" -report html_basic "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/coverage.html"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_custom_target(
        coverage-reset
        COMMENT "Resetting previously gathered Perl test suite coverage"
        COMMAND rm -r "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
    )
    add_custom_target(
        coverage
        COMMENT "Perl test suite coverage (HTML)"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/coverage.html"
    )
    add_dependencies(coverage symlinks)
    add_custom_target(
        coverage-codecov
        COMMENT "Perl test suite coverage (codecov, if direct report uploading possible, e.g. within travis CI)"
        COMMAND "${COVER_PATH}" -report codecov "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
    )
    add_dependencies(coverage-codecov symlinks)
    add_custom_target(
        coverage-codecovbash
        COMMENT "Perl test suite coverage (codecovbash, useful if direct report upload not available)"
        COMMAND "${COVER_PATH}" -report codecovbash "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_dependencies(coverage-codecovbash symlinks)

else ()
    message(STATUS "Set COVER_PATH to the path of the cover executable to enable coverage computition of the Perl testsuite.")
endif ()
