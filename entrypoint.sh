#!/bin/sh -l

cd /testing

export PERL5LIB="$PWD:$PWD/ppmclibs:$PWD/ppmclibs/blib/arch/auto/tinycv:$PERL5LIB"
#prove -I. -v t/24-myjsonrpc.t
#prove -I. t/00-compile-check-all.t
#prove -I. t/01-test_needle.t
#prove -I. t/02-test_ocr.t
#prove -I. t/03-testapi.t
#prove -I. t/04-check_vars_docu.t
#prove -I. t/05-pod.t
#prove -I. t/06-pod-coverage.t
#prove -I. t/07-commands.t
#prove -I. t/08-autotest.t
#prove -I. t/09-lockapi.t
#prove -I. t/10-terminal.t
#prove -I. t/10-test-image-conversion-benchmark.t
#prove -I. t/10-virtio_terminal.t
#prove -I. t/11-image-ppm.t
#prove -I. t/12-bmwqemu.t
#prove -I. t/15-logging.t
#prove -I. t/16-send_with_fd.t
#prove -I. t/17-basetest.t
#prove -I. t/18-backend-qemu.t
#prove -I. t/19-isotovideo-command-processing.t
#prove -I. t/20-openqa-benchmark-stopwatch-utils.t
#prove -I. t/21-needle-downloader.t
#prove -I. t/22-svirt.t
#prove -I. t/23-baseclass.t
#prove -I. t/24-myjsonrpc-debug.t
#prove -I. t/24-myjsonrpc.t
#prove -I. t/25-spvm.t
#prove -I. t/26-serial_screen.t
#prove -I. t/26-ssh_screen.t

prove -I. t/13-osutils.t
#prove -I. t/14-isotovideo.t
#prove -I. t/18-qemu-options.t
#prove -I. t/18-qemu.t
#prove -I. t/99-full-stack.t

#perldoc -l YAML::PP || true
#perldoc -l YAML::PP::LibYAML || true
#perldoc -l YAML::Tiny || true
#perldoc -l YAML || true
#perldoc -l XXX || true
