project(doc CXX)
cmake_minimum_required(VERSION 3.17.0)

find_program(POD2HTML_PATH pod2html)
if (NOT POD2HTML_PATH)
    message(FATAL_ERROR "Unable to find pod2html.")
endif ()

set(GENERATED_DOC_FILES)
foreach (PERL_MODULE basetest testapi)
    add_custom_command(
        COMMENT "Generating ${PERL_MODULE}.html"
        COMMAND "${POD2HTML_PATH}"
            --infile "${CMAKE_CURRENT_SOURCE_DIR}/../${PERL_MODULE}.pm"
            --outfile "${CMAKE_CURRENT_BINARY_DIR}/${PERL_MODULE}.html"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../${PERL_MODULE}.pm"
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${PERL_MODULE}.html"
    )
    list(APPEND GENERATED_DOC_FILES "${CMAKE_CURRENT_BINARY_DIR}/${PERL_MODULE}.html")
endforeach ()

add_custom_target(generate_documentation ALL
    COMMENT "Generate documentation"
    DEPENDS ${GENERATED_DOC_FILES}
)
set(GENERATED_DOC_FILES "${GENERATED_DOC_FILES}" PARENT_SCOPE)
