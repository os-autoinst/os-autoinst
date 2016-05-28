project(os-autoinst CXX)
cmake_minimum_required(VERSION 3.3.0)

add_subdirectory(debugviewer)
add_subdirectory(snd2png)
add_subdirectory(ppmclibs)

set(COVERAGE_THRESHOLD 30.1)

set(pkglibexecdir TODO cmake equivalent?)

find_package(OpenCV REQUIRED)
include(FindPkgConfig)
add_executable(videoencoder videoencoder.cpp)
target_link_libraries(videoencoder ${OpenCV_LIBS})
pkg_check_modules(THEORAENC theoraenc>=1.1)
target_link_libraries(videoencoder ${OpenCV_LIBS} ${THEORAENC_LIBRARIES})
set_target_properties(videoencoder
    PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

# TODO install all these
set(doc_DATA
    README.asciidoc
    INSTALL.asciidoc
    COPYING
    doc/basetest.html
    doc/testapi.html
    )

set(backendexecdir $(pkglibexecdir)/backend)
set(backendexec_DATA
    backend/baseclass.pm
    backend/console_proxy.pm
    backend/driver.pm
    backend/generalhw.pm
    backend/ikvm.pm
    backend/ipmi.pm
    backend/qemu.pm
    backend/s390x.pm
    backend/svirt.pm
    backend/pvm.pm
    backend/spvm.pm
    backend/pvm_hmc.pm
    backend/virt.pm)

set(consolesexecdir $(pkglibexecdir)/consoles)
set(consolesexec_DATA
    consoles/console.pm
    consoles/icewm.cfg
    consoles/ipmiSol.pm
    consoles/localXvnc.pm
    consoles/remoteVnc.pm
    consoles/s3270.pm
    consoles/ssh_screen.pm
    consoles/sshX3270.pm
    consoles/sshVirtsh.pm
    consoles/sshVirtshSUT.pm
    consoles/sshIucvconn.pm
    consoles/sshXtermIPMI.pm
    consoles/sshXtermVt.pm
    consoles/ttyConsole.pm
    consoles/serial_screen.pm
    consoles/virtio_terminal.pm
    consoles/vnc_base.pm
    consoles/network_console.pm
    consoles/VNC.pm)

set(openqaexecdir $(pkglibexecdir)/OpenQA)
set(openqaexec_DATA
    OpenQA/Commands.pm
    OpenQA/Exceptions.pm)

set(openqaexecbenchdir $(pkglibexecdir)/OpenQA/Benchmark)
set(openqaexecbench_DATA
    OpenQA/Benchmark/Stopwatch.pm)

set(openqaexecrunargsdir $(pkglibexecdir)/OpenQA/Test)
set(openqaexecrunargs_DATA
    OpenQA/Test/RunArgs.pm)

set(openqaexecqemudir $(pkglibexecdir)/OpenQA/Qemu)
set(openqaexecqemu_DATA
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
    OpenQA/Qemu/Snapshot.pm)

set(openqaisotovideodir $(pkglibexecdir)/OpenQA/Isotovideo)
set(openqaisotovideo_DATA
    OpenQA/Isotovideo/CommandHandler.pm
    OpenQA/Isotovideo/NeedleDownloader.pm
    OpenQA/Isotovideo/Interface.pm
    OpenQA/Isotovideo/Utils.pm)

# circumvent automake's test - possibly we really shouldn't install in /usr/lib though
set(perlexecdir $(pkglibexecdir))
set(perlexec_DATA
    autotest.pm
    basetest.pm
    bmwqemu.pm
    testapi.pm
    myjsonrpc.pm
    mmapi.pm
    lockapi.pm
    commands.pm
    distribution.pm
    ocr.pm
    cv.pm
    needle.pm
    osutils.pm)

set(pkglibexec_SCRIPTS
    crop.py
    os-autoinst-openvswitch)

set(bin_SCRIPTS isotovideo)

enable_testing()
add_test(NAME check COMMAND make -C ${CMAKE_CURRENT_SOURCE_DIR} test)
