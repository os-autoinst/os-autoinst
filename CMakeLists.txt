project(os-autoinst CXX)
cmake_minimum_required(VERSION 3.3.0)

# list non-C++ source files
set(DOC_FILES
    README.asciidoc
    INSTALL.asciidoc
    COPYING
    doc/basetest.html
    doc/testapi.html
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
    ppmclibs/tinycv.pm
    signalblocker.pm
    testapi.pm
)
set(SCRIPT_FILES
    crop.py
    os-autoinst-openvswitch
    isotovideo
)

# common dependency lookup
find_package(OpenCV REQUIRED)
include(FindPkgConfig)

# build tools/libraries in sub directories
add_subdirectory(debugviewer)
add_subdirectory(snd2png)
add_subdirectory(ppmclibs)

# build videoencoder
add_executable(videoencoder videoencoder.cpp)
pkg_check_modules(THEORAENC theoraenc>=1.1)
target_link_libraries(videoencoder PRIVATE opencv_core opencv_imgcodecs ${THEORAENC_LIBRARIES})
target_include_directories(videoencoder PRIVATE ${THEORAENC_INCLUDE_DIRS})
target_compile_options(videoencoder PRIVATE ${THEORAENC_CFLAGS})
target_link_options(videoencoder PRIVATE ${THEORAENC_LDFLAGS})

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
