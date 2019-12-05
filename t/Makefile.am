UPDIR = $(dir $(PWD))

PATHRE = ^|$(UPDIR)|\.\./

AM_MAKEFLAGS = \
	PERL5OPT="-MDevel::Cover=-db,$(abs_builddir)/cover_db,-select,($(PATHRE))(OpenQA|backend|consoles|ppmclibs)/|($(PATHRE))isotovideo|($(PATHRE))[^/]+\.pm,-ignore,\.t|.*data/tests/|.*fake/tests/" \
	PERL5LIB="$(PWD)/..:$(PWD)/../ppmclibs:$(PWD)/../ppmclibs/blib/arch/auto/tinycv:$$PERL5LIB"
# Prevent error "blank line following trailing backslash" when deleting last
# line in list in spec file to exclude tests
EMPTY =
TESTS = \
	00-compile-check-all.t \
	01-test_needle.t \
	02-test_ocr.t \
	03-testapi.t \
	04-check_vars_docu.t \
	05-pod.t \
	06-pod-coverage.t \
	07-commands.t \
	08-autotest.t \
	09-lockapi.t \
	10-terminal.t \
	10-test-image-conversion-benchmark.t \
	11-image-ppm.t \
	12-bmwqemu.t \
	13-osutils.t \
	14-isotovideo.t \
	15-logging.t \
	16-send_with_fd.t \
	17-basetest.t \
	18-qemu.t \
	18-backend-qemu.t \
	18-qemu-options.t \
	19-isotovideo-command-processing.t \
	20-openqa-benchmark-stopwatch-utils.t \
	21-needle-downloader.t \
	22-svirt.t \
	23-baseclass.t \
	24-myjsonrpc.t \
	24-myjsonrpc-debug.t \
	25-spvm.t \
	26-ssh_screen.t \
	99-full-stack.t \
	$(EMPTY)

EXTRA_DIST = $(TESTS)
