.PHONY: all
all: build-all

.PHONY: build-all
build-all: build/build.ninja
	ninja -C build/

build/build.ninja: build/
	(cd $< && cmake -GNinja ..)

build/:
	mkdir -p $@

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

.PHONY: check
check:
	$(srcdir)/tools/tidy --check
	PERL5LIB=tools/lib/perlcritic:$$PERL5LIB perlcritic --gentle --include Perl::Critic::Policy::HashKeyQuote --include Perl::Critic::Pol
cy::ConsistentQuoteLikeWords $(srcdir)
	test x$(CHECK_DOC) = x0 || $(MAKE) check-doc

.PHONY: check-doc
check-doc: check-doc-testapi

.PHONY: check-doc-testapi
check-doc-testapi:
	command -v podspell >/dev/null || (echo "Missing podspell"; exit 2)
	command -v spell >/dev/null || (echo "Missing spell"; exit 2)
	[ -z "$$(podspell testapi.pm | spell)" ]

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
