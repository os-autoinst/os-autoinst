project(os-autoinst CXX)
cmake_minimum_required(VERSION 3.3.0)

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
    backend/ikvm.pm
    backend/ipmi.pm
    backend/null.pm
    backend/pvm_hmc.pm
    backend/pvm.pm
    backend/qemu.pm
    backend/s390x.pm
    backend/spvm.pm
    backend/svirt.pm
    backend/virt.pm
    basetest.pm
    bmwqemu.pm
    commands.pm
    consoles/amtSol.pm
    consoles/console.pm
    consoles/ipmiSol.pm
    consoles/localXvnc.pm
    consoles/network_console.pm
    consoles/remoteVnc.pm
    consoles/s3270.pm
    consoles/serial_screen.pm
    consoles/sshIucvconn.pm
    consoles/ssh_screen.pm
    consoles/sshVirtsh.pm
    consoles/sshVirtshSUT.pm
    consoles/sshX3270.pm
    consoles/sshXtermIPMI.pm
    consoles/sshXtermVt.pm
    consoles/ttyConsole.pm
    consoles/virtio_terminal.pm
    consoles/vnc_base.pm
    consoles/VNC.pm
    cv.pm
    distribution.pm
    lockapi.pm
    mmapi.pm
    myjsonrpc.pm
    needle.pm
    ocr.pm
    OpenQA/Benchmark/Stopwatch.pm
    OpenQA/Commands.pm
    OpenQA/Exceptions.pm
    OpenQA/Isotovideo/CommandHandler.pm
    OpenQA/Isotovideo/Interface.pm
    OpenQA/Isotovideo/NeedleDownloader.pm
    OpenQA/Isotovideo/Utils.pm
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
    dmidata/dell_e6330/smbios_type_1.bin
    dmidata/dell_e6330/smbios_type_2.bin
    dmidata/dell_e6330/smbios_type_3.bin
    dmidata/dump
)
set(EXECUTABLE_FILES
    isotovideo
)

# determine install directories
# note: Not using ${CMAKE_INSTALL_LIBDIR} here because this seems always lib in our packaging (and
#       never lib64) regardless of the architecture.
include(GNUInstallDirs)
set(OS_AUTOINST_DATA_DIR "lib/os-autoinst"
    CACHE STRING "directory to install os-autoinst internal Perl modules and misc files to")
set(OS_AUTOINST_DOC_DIR "${CMAKE_INSTALL_DATAROOTDIR}/doc/packages/os-autoinst"
    CACHE STRING "directory to install documentation to")

# common dependency lookup
find_package(OpenCV REQUIRED)
include(FindPkgConfig)

# build and install tools/libraries in sub directories
add_subdirectory(debugviewer)
add_subdirectory(snd2png)
add_subdirectory(ppmclibs)

# build and install videoencoder
add_executable(videoencoder videoencoder.cpp)
pkg_check_modules(THEORAENC theoraenc>=1.1)
target_link_libraries(videoencoder PRIVATE opencv_core opencv_imgcodecs ${THEORAENC_LIBRARIES})
target_include_directories(videoencoder PRIVATE ${THEORAENC_INCLUDE_DIRS})
target_compile_options(videoencoder PRIVATE ${THEORAENC_CFLAGS})
target_link_options(videoencoder PRIVATE ${THEORAENC_LDFLAGS})
install(TARGETS videoencoder RUNTIME DESTINATION "${OS_AUTOINST_DATA_DIR}")

# allow symlinking created executables into source directory
# note: This target is supposed to be used for making a development environment. The symlinks will
#       allow isotovideo to find all native executables created by this build.
add_custom_target(
    symlinks
    COMMENT "Symlinking created executables into source directory"
    COMMAND mkdir -p "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/arch/auto/tinycv"
    COMMAND mkdir -p "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/lib"
    COMMAND ln -fs $<TARGET_FILE:videoencoder> "${CMAKE_CURRENT_SOURCE_DIR}/videoencoder"
    COMMAND ln -fs $<TARGET_FILE:snd2png> "${CMAKE_CURRENT_SOURCE_DIR}/snd2png/snd2png"
    COMMAND ln -fs $<TARGET_FILE:debugviewer> "${CMAKE_CURRENT_SOURCE_DIR}/debugviewer/debugviewer"
    COMMAND ln -fs "../../tinycv.pm" "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/lib/tinycv.pm"
    COMMAND ln -fs $<TARGET_FILE:tinycv> "${CMAKE_CURRENT_SOURCE_DIR}/ppmclibs/blib/arch/auto/tinycv/tinycv.so"
)

# install non-C++ files
foreach (FILE ${EXECUTABLE_FILES})
    install(FILES "${FILE}" DESTINATION "${CMAKE_INSTALL_BINDIR}")
endforeach ()
foreach (FILE README.asciidoc INSTALL.asciidoc COPYING)
    install(FILES "${FILE}" DESTINATION "${OS_AUTOINST_DOC_DIR}")
endforeach ()
foreach (FILE ${PERL_FILES} ${MISC_FILES})
    get_filename_component(SUB_DIR ${FILE} DIRECTORY)
    install(FILES "${FILE}" DESTINATION "${OS_AUTOINST_DATA_DIR}/${SUB_DIR}")
endforeach ()
