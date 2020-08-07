ACLOCAL_AMFLAGS = -I m4
SUBDIRS = t debugviewer snd2png
COVERAGE_THRESHOLD = 30.1

doc_DATA = \
	README.asciidoc \
	COPYING \
	doc/basetest.html \
	doc/testapi.html

backendexecdir = $(pkglibexecdir)/backend
backendexec_DATA = \
	backend/amt.pm \
	backend/baseclass.pm \
	backend/console_proxy.pm \
	backend/driver.pm \
	backend/generalhw.pm \
	backend/ikvm.pm \
	backend/ipmi.pm \
	backend/qemu.pm \
	backend/null.pm \
	backend/s390x.pm \
	backend/svirt.pm \
	backend/pvm.pm \
	backend/spvm.pm \
	backend/pvm_hmc.pm \
	backend/virt.pm

consolesexecdir = $(pkglibexecdir)/consoles
consolesexec_DATA = \
	consoles/amtSol.pm \
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
	osutils.pm \
	signalblocker.pm

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
videoencoder_CXXFLAGS = -O2 -Wall -W $(OPENCV_CFLAGS)
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

check-local-files-specified:
	$(srcdir)/tools/check-installed-files

test-yaml:
	@which yamllint >/dev/null 2>&1 || echo "Command 'yamllint' not found, can not execute YAML syntax checks"
	$(srcdir)/tools/check-yaml-syntax

check-local: check-local-files-specified test-yaml
	$(srcdir)/tools/tidy --check
	$(srcdir)/tools/check-perl-style perlcritic $(srcdir)
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

.PHONY: test
test:
	( $(srcdir)/tools/invoke-tests --build-directory $(abs_builddir) )

.PHONY: testv
testv:
	( PROVE_ARGS=-v $(srcdir)/tools/invoke-tests --build-directory $(abs_builddir) )

.PHONY: test-cover
test-cover:
	( $(srcdir)/tools/invoke-tests --coverage --build-directory $(abs_builddir) )

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
	clang-format --style=WebKit -i $$(find . -name \*.h -o -name \*.cc -o -name \*.cpp)

.PHONY: docker-test
docker-test:
	docker run --rm --entrypoint '' -v $(abs_top_srcdir):/opt/repo registry.opensuse.org/devel/openqa/containers/openqa_dev sh -c 'cd /opt/repo && ./autogen.sh && make && make check test VERBOSE=1'

.PHONY: update-deps
update-deps:
	./tools/update-deps --specfile dist/rpm/os-autoinst.spec --dockerfile docker/travis_test/Dockerfile
