cmake_minimum_required(VERSION 3.17.0)

include(FindPkgConfig)

function (target_use_pkg_config_module TARGET PACKAGE)
    pkg_check_modules(PKG_CONFIG "${PACKAGE}")
    target_link_libraries("${TARGET}" PRIVATE opencv_core opencv_imgcodecs ${PKG_CONFIG_LIBRARIES})
    target_include_directories("${TARGET}" PRIVATE ${PKG_CONFIG_INCLUDE_DIRS})
    target_compile_options("${TARGET}" PRIVATE ${PKG_CONFIG_CFLAGS_OTHER})
    if (COMMAND target_link_options)
        target_link_options("${TARGET}" PRIVATE ${PKG_CONFIG_LDFLAGS_OTHER})
    elseif (PKG_CONFIG_LDFLAGS_OTHER)
        # fallback for older CMake versions not supporting target_link_options
        foreach (FLAG ${PKG_CONFIG_LDFLAGS_OTHER})
            set_property(TARGET "${TARGET}" APPEND_STRING PROPERTY LINK_FLAGS " ${FLAG}")
        endforeach ()
    endif ()
endfunction ()
