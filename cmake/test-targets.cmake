cmake_minimum_required(VERSION 3.3.0)

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

# add test for YAML syntax
find_program(YAMLLINT_PATH yamllint)
if (YAMLLINT_PATH)
    add_test(
        NAME test-local-yaml-syntax
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-yaml-syntax" "${YAMLLINT_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set YAMLLINT_PATH to the path of the yamllint executable to enable YAML syntax checks.")
endif ()

# add tidy check
add_test(
    NAME test-local-tidy
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/tidy" --check
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

# add test for Perl syntax/style issues
find_program(PERLCRITIC_PATH perlcritic)
if (PERLCRITIC_PATH)
    add_test(
        NAME test-local-perl-style
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/check-perl-style" "${PERLCRITIC_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set PERLCRITIC_PATH to the path of the perlcritic executable to enable Perl syntax/style checks.")
endif ()

# add spell checking for test API documentation
find_program(PODSPELL_PATH podspell)
find_program(SPELL_PATH spell)
if (PODSPELL_PATH AND SPELL_PATH)
    add_test(
        NAME test-doc-testapi-spellchecking
        COMMAND sh -c "\"${PODSPELL_PATH}\" \"${CMAKE_CURRENT_SOURCE_DIR}/testapi.pm\" | \"${SPELL_PATH}\""
    )
else ()
    message(STATUS "Set PODSPELL_PATH/SPELL_PATH to the path of the podspell/spell executable to enable spell checking.")
endif ()

# add targets for invoking Perl test suite
find_program(PROVE_PATH prove REQUIRED)
add_test(
    NAME test-perl-testsuite
    COMMAND make test
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

# add build system targets for invoking specific tests
add_custom_target(test-local COMMAND ${CMAKE_CTEST_COMMAND} -R "test-local-.*")
add_custom_target(test-doc COMMAND ${CMAKE_CTEST_COMMAND} -R "test-doc-.*")
add_custom_target(test-installed-files COMMAND ${CMAKE_CTEST_COMMAND} -R "test-installed-files")
add_custom_target(test-perl-testsuite
    COMMAND make test
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    USES_TERMINAL
)
add_custom_target(check COMMAND ${CMAKE_CTEST_COMMAND})
add_custom_target(check-pkg-build COMMAND ${CMAKE_CTEST_COMMAND} -E "test-local-.*")
foreach (CUSTOM_TARGET test-perl-testsuite check check-pkg-build)
    add_dependencies(${CUSTOM_TARGET} symlinks)
endforeach ()

# add target for computing test coverage of Perl test suite
find_program(COVER_PATH cover)
if (COVER_PATH AND PROVE_PATH)
    add_custom_command(
        COMMENT "Run Perl testsuite with coverage instrumentation if no coverage data has been collected so far"
        COMMAND "${COVER_PATH}" -test
        OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_custom_command(
        COMMENT "Generate coverage report (HTML)"
        COMMAND "${COVER_PATH}" -report html_basic
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/coverage.html"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_custom_target(
        coverage-reset
        COMMENT "Resetting previously gathered Perl test suite coverage"
        COMMAND rm -r "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
    )
    add_custom_target(
        coverage
        COMMENT "Perl test suite coverage (HTML)"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/coverage.html"
    )
    add_dependencies(coverage symlinks)
    add_custom_target(
        coverage-codecov
        COMMENT "Perl test suite coverage (codecov, if direct report uploading possible, e.g. within travis CI)"
        COMMAND "${COVER_PATH}" -report codecov
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_dependencies(coverage-codecov symlinks)
    add_custom_target(
        coverage-codecovbash
        COMMENT "Perl test suite coverage (codecovbash, useful if direct report upload not available)"
        COMMAND "${COVER_PATH}" -report codecovbash
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cover_db"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_dependencies(coverage-codecovbash symlinks)

else ()
    message(STATUS "Set COVER_PATH to the path of the cover executable to enable coverage computition of the Perl testsuite.")
endif ()
