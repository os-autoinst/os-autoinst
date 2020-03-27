ACLOCAL_AMFLAGS = -I m4
SUBDIRS = t debugviewer snd2png
COVERAGE_THRESHOLD = 30.1

doc_DATA = \
	README.asciidoc \
	INSTALL.asciidoc \
	COPYING \
	doc/basetest.html \
	doc/testapi.html

backendexecdir = $(pkglibexecdir)/backend
backendexec_DATA = \
	backend/baseclass.pm \
	backend/console_proxy.pm \
	backend/driver.pm \
	backend/generalhw.pm \
	backend/ikvm.pm \
	backend/ipmi.pm \
	backend/qemu.pm \
	backend/s390x.pm \
	backend/svirt.pm \
	backend/pvm.pm \
	backend/spvm.pm \
	backend/pvm_hmc.pm \
	backend/virt.pm

consolesexecdir = $(pkglibexecdir)/consoles
consolesexec_DATA = \
	consoles/console.pm \
	consoles/icewm.cfg \
	consoles/ipmiSol.pm \
	consoles/localXvnc.pm \
	consoles/remoteVnc.pm \
	consoles/s3270.pm \
	consoles/ssh_screen.pm \
	consoles/sshX3270.pm \
	consoles/sshVirtsh.pm \
	consoles/sshVirtshSUT.pm \
	consoles/sshIucvconn.pm \
	consoles/sshXtermIPMI.pm \
	consoles/sshXtermVt.pm \
	consoles/ttyConsole.pm \
	consoles/serial_screen.pm \
	consoles/virtio_terminal.pm \
	consoles/vnc_base.pm \
	consoles/network_console.pm \
	consoles/VNC.pm

openqaexecdir = $(pkglibexecdir)/OpenQA
openqaexec_DATA = \
	OpenQA/Commands.pm \
	OpenQA/Exceptions.pm

openqaexecbenchdir = $(pkglibexecdir)/OpenQA/Benchmark
openqaexecbench_DATA = \
	OpenQA/Benchmark/Stopwatch.pm

openqaexecrunargsdir = $(pkglibexecdir)/OpenQA/Test
openqaexecrunargs_DATA = \
    OpenQA/Test/RunArgs.pm

openqaexecqemudir = $(pkglibexecdir)/OpenQA/Qemu
openqaexecqemu_DATA = \
	OpenQA/Qemu/BlockDevConf.pm \
	OpenQA/Qemu/BlockDev.pm \
	OpenQA/Qemu/ControllerConf.pm \
	OpenQA/Qemu/DriveController.pm \
	OpenQA/Qemu/DriveDevice.pm \
	OpenQA/Qemu/DrivePath.pm \
	OpenQA/Qemu/MutParams.pm \
	OpenQA/Qemu/PFlashDevice.pm \
	OpenQA/Qemu/Proc.pm \
	OpenQA/Qemu/SnapshotConf.pm \
	OpenQA/Qemu/Snapshot.pm

openqaisotovideodir = $(pkglibexecdir)/OpenQA/Isotovideo
openqaisotovideo_DATA = \
	OpenQA/Isotovideo/CommandHandler.pm \
	OpenQA/Isotovideo/NeedleDownloader.pm \
	OpenQA/Isotovideo/Interface.pm \
	OpenQA/Isotovideo/Utils.pm

# circumvent automake's test - possibly we really shouldn't install in /usr/lib though
perlexecdir = $(pkglibexecdir)
perlexec_DATA = \
	autotest.pm \
	basetest.pm \
	bmwqemu.pm \
	testapi.pm \
	myjsonrpc.pm \
	mmapi.pm \
	lockapi.pm \
	commands.pm \
	distribution.pm \
	ocr.pm \
	cv.pm \
	needle.pm \
	osutils.pm

pkglibexec_SCRIPTS = \
	crop.py \
	os-autoinst-openvswitch

bin_SCRIPTS = isotovideo

install-exec-hook:
	sed -i -e "s,\$$installprefix = undef;,\$$installprefix = '$(pkglibexecdir)';," $(DESTDIR)$(bindir)/isotovideo && \
	sed -i -e "s,\$$sysdir = undef;,\$$sysdir = '$(pkglibexecdir)';," $(DESTDIR)$(pkglibexecdir)/cv.pm

pkglibexec_FOLDERS = \
	tools \
	inst \
	inst.d \
	dmidata

# sort the above out so it is not done directory wise

pkglibexec_PROGRAMS = videoencoder

videoencoder_SOURCES = videoencoder.cpp
videoencoder_CFLAGS = -O2 -Wall -W $(OPENCV_CFLAGS)
videoencoder_LDADD = $(OPENCV_LIBS) $(THEORAENC_LIBS) -lm

EXTRA_DIST = \
	autogen.sh \
	ppmclibs/tinycv.i \
	$(backendhelpexec_SCRIPTS) $(backendexec_SCRIPTS) \
	$(doc_DATA) $(pkglibexec_DATA) $(pkglibexec_SCRIPTS) $(packagestate_DATA_FOLDERS) $(pkglibexec_FOLDERS) \
	etc/dbus-1/system.d/org.opensuse.os_autoinst.switch.conf \
	systemd/os-autoinst-openvswitch.service

CLEANFILES = \
	$(ppmcexec_SCRIPTS) \
	ppmclibs/tinycv_wrap.cxx \
	doc/basetest.html \
	doc/testapi.html

PERL_MODULE = ppmclibs/blib/arch/auto/tinycv/tinycv.so
OPENVSWITCH_SERVICE = systemd/os-autoinst-openvswitch.service

ppmclibs/Makefile: ppmclibs/Makefile.PL
	cd ppmclibs && \
	perl Makefile.PL OPTIMIZE="$(CXXFLAGS)" CC="$(CXX)"

$(PERL_MODULE): ppmclibs/Makefile
	$(MAKE) -C ppmclibs

$(OPENVSWITCH_SERVICE):
	rm -f $@ $@.tmp
	sed -e 's,@pkglibexecdir[@],$(pkglibexecdir),g' '$(top_srcdir)/$@.in' > '$(top_srcdir)/$@.tmp'
	mv '$(top_srcdir)/$@.tmp' '$(top_srcdir)/$@'

install-exec-local: $(PERL_MODULE)
	$(MAKE) -C ppmclibs pure_install DESTDIR="$(DESTDIR)" INSTALLDIRS="$(INSTALLDIRS)"

all-local: $(PERL_MODULE)

doc/%.html: %.pm
	pod2html $< > $@

install-data-local: $(OPENVSWITCH_SERVICE)
	$(MKDIR_P) $(DESTDIR)/$(packagestatedir) ; \
	for i in $(packagestate_DATA_FOLDERS) ; do \
		cp -r $(top_srcdir)/$$i "$(DESTDIR)/$(packagestatedir)" ; \
	done
	$(MKDIR_P) "$(DESTDIR)/$(pkgdatadir)" ; \
	for i in $(pkglibexec_FOLDERS) ; do \
		cp -r $(top_srcdir)/$$i "$(DESTDIR)/$(pkglibexecdir)" ; \
	done
	install -D -m 644 $(top_srcdir)/etc/dbus-1/system.d/org.opensuse.os_autoinst.switch.conf "$(DESTDIR)/etc/dbus-1/system.d/org.opensuse.os_autoinst.switch.conf"
	install -D -m 644 "$(top_srcdir)/$(OPENVSWITCH_SERVICE)" "$(DESTDIR)/usr/lib/systemd/system/os-autoinst-openvswitch.service"

uninstall-local:
	for i in $(packagestate_DATA_FOLDERS) ; do \
		rm -rf "$(DESTDIR)/$(packagestatedir)/$$i" ; \
	done
	for i in $(pkglibexec_FOLDERS) ; do \
		rm -rf "$(DESTDIR)/$(pkglibexecdir)/$$i" ; \
	done

dist-hook:
	@if test -d "$(srcdir)/.git"; \
	then \
		echo Creating ChangeLog && \
		( cd "$(top_srcdir)" && \
		  echo '# Generated by Makefile. Do not edit.'; echo; \
		  $(top_srcdir)/missing --run git log ) > ChangeLog.tmp \
		&& mv -f ChangeLog.tmp $(distdir)/ChangeLog \
		|| ( rm -f ChangeLog.tmp ; \
		     echo Failed to generate ChangeLog >&2 ); \
	else \
		echo A git clone is required to generate a ChangeLog >&2; \
	fi
	rm -rf `find $(distdir) -name .gitignore`

distclean-local: clean-local

check-local:
	$(srcdir)/tools/tidy --check
	PERL5LIB=tools/lib/perlcritic:$$PERL5LIB perlcritic --gentle --include Perl::Critic::Policy::HashKeyQuote $(srcdir)
	test x$(CHECK_DOC) = x0 || $(MAKE) check-doc

.PHONY: check-doc
check-doc: check-doc-testapi

.PHONY: check-doc-testapi
check-doc-testapi:
	command -v podspell >/dev/null || (echo "Missing podspell"; exit 2)
	command -v spell >/dev/null || (echo "Missing spell"; exit 2)
	[ -z "$$(podspell testapi.pm | spell)" ]

clean-local:
	@if test -e ppmclibs/Makefile; then $(MAKE) -C ppmclibs distclean; fi
	-rm -rf *.tar.*
	-rm -rf cover_db/

# Prevent error "blank line following trailing backslash" when deleting last
# line in list in spec file to exclude tests
EMPTY =
TEST_FILES = \
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
	10-virtio_terminal.t \
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
	26-serial_screen.t \
	26-ssh_screen.t \
	99-full-stack.t \
	$(EMPTY)

PATHRE = ^|$(PWD)/|\.\./
COVER_OPTS = \
	PERL5OPT="-MDevel::Cover=-db,$(abs_builddir)/cover_db,-select,($(PATHRE))(OpenQA|backend|consoles|ppmclibs)/|($(PATHRE))isotovideo|($(PATHRE))[^/]+\.pm,-ignore,\.t|data/tests/|fake/tests/|/usr/bin/prove,-coverage,statement"
TEST_OPTS = \
	PERL5LIB="$(PWD):$(PWD)/ppmclibs:$(PWD)/ppmclibs/blib/arch/auto/tinycv:$$PERL5LIB"

.PHONY: test
test:
	( cd t && $(TEST_OPTS) prove $(TEST_FILES) )

.PHONY: testv
testv:
	( cd t && $(TEST_OPTS) prove -v $(TEST_FILES) )

.PHONY: test-cover
test-cover:
	( cd t && $(TEST_OPTS) $(COVER_OPTS) prove $(TEST_FILES) )

.PHONY: test-cover-summary
test-cover-summary:
	cover -summary cover_db

cover_db/: test-cover

.PHONY: coverage
coverage: coverage-html

.PHONY: coverage-codecov
coverage-codecov: cover_db/
	cover -report codecov cover_db

cover_db/coverage.html: cover_db/
	cover -report html_basic cover_db

.PHONY: coverage-html
coverage-html: cover_db/coverage.html

.PHONY: coverage-check
coverage-check: cover_db/coverage.html
	./tools/check_coverage ${COVERAGE_THRESHOLD}

.PHONY: tidy-cpp
tidy-cpp:
	clang-format --style=WebKit -i $$(find . -name \*.cc -o -name \*.cpp)

.PHONY: docker-test-build
docker-test-build:
	docker build --no-cache $(top_srcdir)/docker/travis_test -t os-autoinst/travis_test:latest

.PHONY: docker-test-run
docker-test-run:
	docker run --rm -v $(abs_top_srcdir):/opt/repo os-autoinst/travis_test:latest 'make && make check test VERBOSE=1'

.PHONY: docker-test
.NOTPARALLEL: docker-test
docker-test: docker-test-build docker-test-run
	echo "Use docker-rm and docker-rmi to remove the container and image if necessary"
