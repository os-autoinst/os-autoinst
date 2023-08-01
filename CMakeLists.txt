cmake_minimum_required(VERSION 3.17.0)
project(os-autoinst CXX)

# list non-C++ source files
set(DOC_FILES
    doc/architecture.md
    doc/backend_vars.asciidoc
    doc/backends.md
    doc/memorydumps.asciidoc
    doc/networking.md
)
set(PERL_FILES
    autotest.pm
    backend/amt.pm
    backend/baseclass.pm
    backend/console_proxy.pm
    backend/driver.pm
    backend/generalhw.pm
    backend/ipmi.pm
    backend/null.pm
    backend/pvm_hmc.pm
    backend/qemu.pm
    backend/s390x.pm
    backend/spvm.pm
    backend/svirt.pm
    backend/vagrant.pm
    backend/virt.pm
    basetest.pm
    bmwqemu.pm
    commands.pm
    consoles/amtSol.pm
    consoles/console.pm
    consoles/ipmiSol.pm
    consoles/localXvnc.pm
    consoles/network_console.pm
    consoles/s3270.pm
    consoles/serial_screen.pm
    consoles/sshIucvconn.pm
    consoles/ssh_screen.pm
    consoles/sshSerial.pm
    consoles/sshVirtsh.pm
    consoles/sshVirtshSUT.pm
    consoles/sshX3270.pm
    consoles/sshXtermIPMI.pm
    consoles/sshXtermVt.pm
    consoles/ttyConsole.pm
    consoles/video_base.pm
    consoles/video_stream.pm
    consoles/virtio_terminal.pm
    consoles/vnc_base.pm
    consoles/VNC.pm
    consoles/VMWare.pm
    distribution.pm
    lockapi.pm
    log.pm
    mmapi.pm
    myjsonrpc.pm
    needle.pm
    ocr.pm
    OpenQA/Benchmark/Stopwatch.pm
    OpenQA/Commands.pm
    OpenQA/Exceptions.pm
    OpenQA/Isotovideo/Backend.pm
    OpenQA/Isotovideo/CommandHandler.pm
    OpenQA/Isotovideo/Interface.pm
    OpenQA/Isotovideo/NeedleDownloader.pm
    OpenQA/Isotovideo/Runner.pm
    OpenQA/Isotovideo/Utils.pm
    OpenQA/NamedIOSelect.pm
    OpenQA/Qemu/BlockDevConf.pm
    OpenQA/Qemu/BlockDev.pm
    OpenQA/Qemu/ControllerConf.pm
    OpenQA/Qemu/DriveController.pm
    OpenQA/Qemu/DriveDevice.pm
    OpenQA/Qemu/DrivePath.pm
    OpenQA/Qemu/MutParams.pm
    OpenQA/Qemu/PFlashDevice.pm
    OpenQA/Qemu/Proc.pm
    OpenQA/Qemu/SnapshotConf.pm
    OpenQA/Qemu/Snapshot.pm
    OpenQA/Test/RunArgs.pm
    osutils.pm
    signalblocker.pm
    testapi.pm
)
set(MISC_FILES
    consoles/icewm.cfg
    crop.py
    testapi.py
    dmidata/dell_e6330/smbios_type_1.bin
    dmidata/dell_e6330/smbios_type_2.bin
    dmidata/dell_e6330/smbios_type_3.bin
    dmidata/hp_elitebook_820g1/smbios_type_1.bin
    dmidata/hp_elitebook_820g1/smbios_type_2.bin
    dmidata/hp_elitebook_820g1/smbios_type_3.bin
    dmidata/dump
)

# determine install directories
# note: Not using ${CMAKE_INSTALL_LIBDIR} here because this seems always lib in our packaging (and
#       never lib64) regardless of the architecture.
include(GNUInstallDirs)
set(OS_AUTOINST_DATA_DIR "lib/os-autoinst"
    CACHE STRING "directory to install os-autoinst internal Perl modules and misc files to")
set(OS_AUTOINST_DOC_DIR "${CMAKE_INSTALL_DATAROOTDIR}/doc/packages/os-autoinst"
    CACHE STRING "directory to install documentation to")
set(SYSTEMD_SERVICE_DIR "lib/systemd/system"
    CACHE STRING "directory to install systemd service files to")

# common dependency lookup
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake;${CMAKE_MODULE_PATH}")
include(pkg-config)
find_package(OpenCV REQUIRED)

# configure flags regarding warnings
include(warnings)

# build and install tools/libraries in sub directories
add_subdirectory(debugviewer)
add_subdirectory(snd2png)
add_subdirectory(ppmclibs)
add_subdirectory(doc)
add_subdirectory(systemd)

# build and install videoencoder
add_executable(videoencoder videoencoder.cpp)
target_use_pkg_config_module(videoencoder "theoraenc>=1.1")
install(TARGETS videoencoder RUNTIME DESTINATION "${OS_AUTOINST_DATA_DIR}")

# allow symlinking created executables into source directory
# note: This target is supposed to be used for making a development environment. The symlinks will
#       allow isotovideo to find all native executables created by this build.
get_filename_component(SRC_DIR "${CMAKE_SOURCE_DIR}" REALPATH)
get_filename_component(BIN_DIR "${CMAKE_BINARY_DIR}" REALPATH)
if (NOT SRC_DIR STREQUAL BIN_DIR)
    set(OUT_OF_SOURCE_TREE_BUILD_COMMANDS
        COMMAND ln -fs $<TARGET_FILE:videoencoder> "${CMAKE_CURRENT_SOURCE_DIR}/videoencoder"
        COMMAND ln -fs $<TARGET_FILE:snd2png> "${CMAKE_CURRENT_SOURCE_DIR}/snd2png/snd2png"
        COMMAND ln -fs $<TARGET_FILE:debugviewer> "${CMAKE_CURRENT_SOURCE_DIR}/debugviewer/debugviewer"
    )
endif ()
add_custom_target(
    symlinks
    COMMENT "Symlinking created executables into source directory"
    COMMAND mkdir -p "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/arch/auto/tinycv"
    COMMAND mkdir -p "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/lib"
    COMMAND ln -fs "../../tinycv.pm" "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/lib/tinycv.pm"
    COMMAND ln -fs $<TARGET_FILE:tinycv> "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/arch/auto/tinycv/tinycv.so"
    ${OUT_OF_SOURCE_TREE_BUILD_COMMANDS}
)
add_dependencies(symlinks videoencoder snd2png debugviewer tinycv)

# create installable versions of isotovideo and cv.pm
set(OS_AUTOINST_VERSION "" CACHE STRING "os-autoinst version to set for the installation")
find_program(GIT_BIN git)
if (OS_AUTOINST_VERSION)
    set(OS_AUTOINST_VERSION_REPLACE "${OS_AUTOINST_VERSION}")
elseif (GIT_BIN AND IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.git")
    execute_process(COMMAND "${GIT_BIN}" rev-parse HEAD
                    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
                    OUTPUT_VARIABLE OS_AUTOINST_VERSION_REPLACE)
    string(REPLACE "\n" "" OS_AUTOINST_VERSION_REPLACE "${OS_AUTOINST_VERSION_REPLACE}")
else ()
    set(OS_AUTOINST_VERSION_REPLACE "unknown")
endif ()
add_custom_command(
    COMMENT "Make directory to store intermediate files for install target"
    COMMAND mkdir -p "${CMAKE_CURRENT_BINARY_DIR}/install-target"
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/install-target"
)
add_custom_command(
    COMMENT "Make install version of isotovideo"
    COMMAND
        sed -e "\"s,\\$$installprefix = undef\;,\\$$installprefix = '${CMAKE_INSTALL_PREFIX}/${OS_AUTOINST_DATA_DIR}'\;,\""
            -e "\"s,my \\$$thisversion = \\(.*\\);,my \\$$thisversion = '${OS_AUTOINST_VERSION_REPLACE}';,\""
        "${CMAKE_CURRENT_SOURCE_DIR}/isotovideo" > "${CMAKE_CURRENT_BINARY_DIR}/install-target/isotovideo"
    DEPENDS "isotovideo" "CMakeLists.txt" "${CMAKE_CURRENT_BINARY_DIR}/install-target"
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/install-target/isotovideo"
)
add_custom_command(
    COMMENT "Make install version of cv.pm"
    COMMAND
        sed -e "\"s,\\$$sysdir = undef\;,\\$$sysdir = '${CMAKE_INSTALL_PREFIX}/${OS_AUTOINST_DATA_DIR}'\;,\""
        "${CMAKE_CURRENT_SOURCE_DIR}/cv.pm" > "${CMAKE_CURRENT_BINARY_DIR}/install-target/cv.pm"
    DEPENDS "cv.pm" "CMakeLists.txt" "${CMAKE_CURRENT_BINARY_DIR}/install-target"
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/install-target/cv.pm"
)
add_custom_target(generate-install-versions ALL
    COMMENT "Generate install version of isotovideo and cv.pm"
    DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/install-target/isotovideo" "${CMAKE_CURRENT_BINARY_DIR}/install-target/cv.pm"
)

# install non-C++ files
set(EXECUTABLE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
install(
    FILES "${CMAKE_CURRENT_BINARY_DIR}/install-target/isotovideo"
    DESTINATION "${CMAKE_INSTALL_BINDIR}"
    PERMISSIONS ${EXECUTABLE_PERMISSIONS}
)
foreach (FILE README.asciidoc COPYING ${GENERATED_DOC_FILES})
    install(FILES "${FILE}" DESTINATION "${OS_AUTOINST_DOC_DIR}")
endforeach ()
foreach (FILE ${PERL_FILES} ${MISC_FILES})
    get_filename_component(SUB_DIR ${FILE} DIRECTORY)
    install(FILES "${FILE}" DESTINATION "${OS_AUTOINST_DATA_DIR}/${SUB_DIR}")
endforeach ()
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/install-target/cv.pm" DESTINATION "${OS_AUTOINST_DATA_DIR}")
install(FILES "schema/Wheels-01.yaml" DESTINATION "${OS_AUTOINST_DATA_DIR}/schema")

# install openvswitch files
install(
    FILES "os-autoinst-openvswitch"
    DESTINATION "${OS_AUTOINST_DATA_DIR}"
    PERMISSIONS ${EXECUTABLE_PERMISSIONS}
    COMPONENT "openvswitch" EXCLUDE_FROM_ALL
)
install(
    FILES "script/os-autoinst-setup-multi-machine"
    DESTINATION "${CMAKE_INSTALL_BINDIR}"
    PERMISSIONS ${EXECUTABLE_PERMISSIONS}
    COMPONENT "openvswitch" EXCLUDE_FROM_ALL
)
install(
    FILES "etc/dbus-1/system.d/org.opensuse.os_autoinst.switch.conf"
    DESTINATION "${CMAKE_INSTALL_FULL_SYSCONFDIR}/dbus-1/system.d"
    COMPONENT "openvswitch"
    EXCLUDE_FROM_ALL
)
foreach (EXTRA_SCRIPT check_qemu_oom dewebsockify vnctest)
    install(
        FILES "${EXTRA_SCRIPT}"
        DESTINATION "${OS_AUTOINST_DATA_DIR}"
        PERMISSIONS ${EXECUTABLE_PERMISSIONS}
    )
endforeach ()
add_custom_target(install-openvswitch
    COMMAND "${CMAKE_COMMAND}" -DCMAKE_INSTALL_COMPONENT=openvswitch -P "${CMAKE_BINARY_DIR}/cmake_install.cmake")

# add tests
include(test-targets)

# add target to update files containing dependency information
add_custom_target(
    update-deps
    COMMENT "Updating dependency information"
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/tools/update-deps" --specfile dist/rpm/os-autoinst.spec --dockerfile container/os-autoinst_dev/Dockerfile
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

# add target for formatting C++ source code
find_program(CLANG_FORMAT_PATH clang-format)
add_custom_target(
    tidy-cpp
    COMMENT "Formatting C++ source code"
    COMMAND sh -c "'${CLANG_FORMAT_PATH}" "--style=WebKit" "-i" "$$(find" "." "-name" "\*.h" "-o" "-name" "\*.cc" "-o" "-name" "\*.cpp)'"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
