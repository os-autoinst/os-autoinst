cmake_minimum_required(VERSION 3.3.0)

enable_testing()

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
find_program(PROVE_PATH prove)
if (PROVE_PATH)
    set(INVOKE_TEST_ARGS --prove-tool "${PROVE_PATH}" --make-tool "${CMAKE_MAKE_PROGRAM}" --build-directory "${CMAKE_CURRENT_BINARY_DIR}")
    add_test(
        NAME test-perl-testsuite
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/invoke-tests" ${INVOKE_TEST_ARGS}
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
else ()
    message(STATUS "Set PROVE_PATH to the path of the prove executable to enable running the Perl testsuite.")
endif ()

# add build system targets for invoking specific tests
add_custom_target(test-local COMMAND ${CMAKE_CTEST_COMMAND} -R "test-local-.*" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_custom_target(test-doc COMMAND ${CMAKE_CTEST_COMMAND} -R "test-doc-.*" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_custom_target(test-installed-files COMMAND ${CMAKE_CTEST_COMMAND} -R "test-installed-files" WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
add_custom_target(test-perl-testsuite COMMAND ${CMAKE_CTEST_COMMAND} -R "test-perl-testsuite" WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
add_dependencies(test-perl-testsuite symlinks)

# add target for computing test coverage of Perl test suite
find_program(COVER_PATH cover)
if (COVER_PATH AND PROVE_PATH)
    add_custom_command(
        COMMENT "Run Perl testsuite with coverage instrumentation"
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/invoke-tests" --coverage ${INVOKE_TEST_ARGS}
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/cover_db/structure"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    add_custom_command(
        COMMENT "Generate coverage report (HTML)"
        COMMAND "${COVER_PATH}" -report html_basic "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/cover_db/structure"
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/coverage.html"
    )
    add_custom_target(
        coverage
        COMMENT "Perl test suite coverage (HTML)"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/coverage.html"
    )
    add_custom_target(
        coverage-codecov
        COMMENT "Perl test suite coverage (codecov)"
        COMMAND "${COVER_PATH}" -report codecov "${CMAKE_CURRENT_BINARY_DIR}/cover_db"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/cover_db/structure"
    )
else ()
    message(STATUS "Set COVER_PATH to the path of the cover executable to enable coverage computition of the Perl testsuite.")
endif ()
