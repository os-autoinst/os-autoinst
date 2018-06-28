AM_MAKEFLAGS = \
	PERL5OPT="-MDevel::Cover=-db,$(abs_builddir)/cover_db,-ignore,^*\.t|^data\/tests\/*|^fake\/tests\/*" \
	PERL5LIB="..:$$PERL5LIB"
TESTS = 00-compile-check-all.t 01-test_needle.t 02-test_ocr.t 03-testapi.t 04-check_vars_docu.t 05-pod.t 06-pod-coverage.t 07-commands.t 08-autotest.t 09-lockapi.t 10-terminal.t 11-image-ppm.t 12-bmwqemu.t 13-osutils.t 14-isotovideo.t 16-send_with_fd.t 17-basetest.t 20-openqa-benchmark-stopwatch-utils.t 99-full-stack.t

EXTRA_DIST = $(TESTS)
