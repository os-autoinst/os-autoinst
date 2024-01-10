#
# spec file for package os-autoinst
#
# Copyright 2018 SUSE LLC
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           os-autoinst
Version:        4.6
Release:        0
Summary:        OS-level test automation
License:        GPL-2.0-or-later
Group:          Development/Tools/Other
Url:            https://github.com/os-autoinst/os-autoinst
Source0:        %{name}-%{version}.tar.xz
%{perl_requires}
%if 0%{?suse_version} > 1500 || 0%{?sle_version} >= 150400
# openSUSE Tumbleweed and Leap 15.4
%define opencv_require pkgconfig(opencv4)
%else
%define opencv_require pkgconfig(opencv)
%endif
# The following line is generated from dependencies.yaml
%define build_base_requires %opencv_require gcc-c++ perl(Pod::Html) pkg-config pkgconfig(fftw3) pkgconfig(libpng) pkgconfig(sndfile) pkgconfig(theoraenc)
# The following line is generated from dependencies.yaml
%define build_requires %build_base_requires cmake ninja
# The following line is generated from dependencies.yaml
%define main_requires git-core perl(B::Deparse) perl(Carp) perl(Carp::Always) perl(Config) perl(Cpanel::JSON::XS) perl(Crypt::DES) perl(Cwd) perl(Data::Dumper) perl(Digest::MD5) perl(DynaLoader) perl(English) perl(Errno) perl(Exception::Class) perl(Exporter) perl(ExtUtils::testlib) perl(Fcntl) perl(File::Basename) perl(File::Find) perl(File::Path) perl(File::Temp) perl(File::Touch) perl(File::Which) perl(File::chdir) perl(IO::Handle) perl(IO::Scalar) perl(IO::Select) perl(IO::Socket) perl(IO::Socket::INET) perl(IO::Socket::UNIX) perl(IPC::Open3) perl(IPC::Run::Debug) perl(IPC::System::Simple) perl(JSON::Validator) perl(List::MoreUtils) perl(List::Util) perl(Mojo::IOLoop::ReadWriteProcess) >= 0.26 perl(Mojo::JSON) perl(Mojo::Log) perl(Mojo::URL) perl(Mojo::UserAgent) perl(Mojolicious) >= 9.340.0 perl(Mojolicious::Lite) perl(Net::DBus) perl(Net::Domain) perl(Net::IP) perl(Net::SNMP) perl(Net::SSH2) perl(POSIX) perl(Scalar::Util) perl(Socket) perl(Socket::MsgHdr) perl(Term::ANSIColor) perl(Thread::Queue) perl(Time::HiRes) perl(Time::Moment) perl(Time::Seconds) perl(Try::Tiny) perl(XML::LibXML) perl(XML::SemanticDiff) perl(YAML::PP) perl(YAML::XS) perl(autodie) perl(base) perl(constant) perl(integer) perl(strict) perl(version) perl(warnings) perl-base rsync sshpass
# all requirements needed by the tests, do not require on this in the package
# itself or any sub-packages
# SLE is missing spell check requirements
%if !0%{?is_opensuse}
%bcond_with spellcheck
%else
%bcond_without spellcheck
%endif
%if %{with spellcheck}
# The following line is generated from dependencies.yaml
%define spellcheck_requires aspell-en aspell-spell perl(Pod::Spell)
%else
%define spellcheck_requires %{nil}
%endif
%if 0%{?sle_version} < 150200 && !0%{?is_opensuse}
%bcond_without yamllint
%else
%bcond_with yamllint
%endif
%if %{with yamllint}
# The following line is generated from dependencies.yaml
%define yamllint_requires python3-yamllint
%else
%define yamllint_requires %{nil}
%endif
%if 0%{?suse_version} >= 1550
%bcond_without black
%else
%bcond_with black
%endif
%if %{with black}
# The following line is generated from dependencies.yaml
%define python_style_requires python3-black
%else
%define python_style_requires %{nil}
%endif
%ifnarch ppc ppc64 ppc64le s390x
%bcond_without ocr
%else
%bcond_with ocr
%endif
%if %{with ocr}
# The following line is generated from dependencies.yaml
%define ocr_requires tesseract-ocr tesseract-ocr-traineddata-english
%else
%define ocr_requires %{nil}
%endif
# The following line is generated from dependencies.yaml
%define test_base_requires %main_requires cpio icewm ipxe-bootimgs perl(Benchmark) perl(Devel::Cover) perl(FindBin) perl(Pod::Coverage) perl(Test::Fatal) perl(Test::Mock::Time) perl(Test::MockModule) perl(Test::MockObject) perl(Test::MockRandom) perl(Test::Mojo) perl(Test::Most) perl(Test::Output) perl(Test::Pod) perl(Test::Strict) perl(Test::Warnings) >= 0.029 procps python3-setuptools qemu >= 4.0 qemu-tools qemu-x86 xorg-x11-Xvnc xterm xterm-console
# The following line is generated from dependencies.yaml
%define test_version_only_requires perl(Mojo::IOLoop::ReadWriteProcess) >= 0.28
# The following line is generated from dependencies.yaml
%define test_requires %build_requires %ocr_requires %spellcheck_requires %test_base_requires %yamllint_requires perl(Inline::Python) python3-Pillow-tk
# The following line is generated from dependencies.yaml
%define devel_requires %python_style_requires %test_requires ShellCheck perl(Code::TidyAll) perl(Devel::Cover) perl(Devel::Cover::Report::Codecov) perl(Perl::Tidy) perl(Template::Toolkit)
%define s390_zvm_requires /usr/bin/xkbcomp /usr/bin/Xvnc x3270 icewm xterm xterm-console xdotool fonts-config mkfontdir mkfontscale openssh-clients
%define qemu_requires qemu-tools e2fsprogs
BuildRequires:  %test_requires %test_version_only_requires
# For unbuffered output of Perl testsuite, especially when running it on OBS so timestamps in the log are actually useful
BuildRequires:  expect
Requires:       %main_requires
%if %{with ocr}
Recommends:     tesseract-ocr
%endif
Recommends:     dumponlyconsole %s390_zvm_requires
Recommends:     qemu >= 4.0.0
Recommends:     %qemu_requires
# Optional dependency for Python test API support
Recommends:     perl(Inline::Python)
# Optional dependency for crop.py
Recommends:     python3-Pillow-tk
# Optional dependency for QEMU's built-in samba service (enabled via QEMU_ENABLE_SMBD=1)
Recommends:     samba
# More efficient video encoding is done automatically if ffmpeg is present
Recommends:     ffmpeg >= 4
Requires(pre):  %{_bindir}/getent
Requires(pre):  %{_sbindir}/useradd
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
ExcludeArch:    %{ix86}

%description
The OS-autoinst project aims at providing a means to run fully
automated tests. Especially to run tests of basic and low-level
operating system components such as bootloader, kernel, installer
and upgrade, which can not easily and safely be tested with other
automated testing frameworks. However, it can just as well be used
to test firefox and openoffice operation on top of a newly
installed OS.

%package devel
Summary:        Development package pulling in all build+test dependencies
Group:          Development/Tools/Other
Requires:       %devel_requires

%description devel
Development package pulling in all build+test dependencies.

%package openvswitch
Summary:        Openvswitch support for os-autoinst
Group:          Development/Tools/Other
Requires:       openvswitch
Requires:       openvswitch-switch
Requires:       os-autoinst
Requires(post): dbus-1

%description openvswitch
This package contains openvswitch support for os-autoinst.

%ifarch x86_64
%package qemu-kvm
Summary:        Convenience package providing os-autoinst+qemu-kvm
Group:          Development/Tools/Other
Requires:       os-autoinst
Requires:       qemu-kvm >= 4.0.0
Requires:       %qemu_requires

%description qemu-kvm

%package qemu-x86
Summary:        Convenience package providing os-autoinst+qemu-x86
Group:          Development/Tools/Other
Requires:       os-autoinst
Requires:       qemu-x86 >= 4.0.0
Requires:       %qemu_requires

%description qemu-x86
Convenience package providing os-autoinst and qemu-x86 dependencies.
%endif

%package swtpm
Summary:        Convenience package providing os-autoinst+swtpm
Group:          Development/Tools/Other
Requires:       os-autoinst
Requires:       swtpm

%description swtpm
Convenience package providing os-autoinst and swtpm dependencies.

%package s390-deps
Summary:        Convenience package providing os-autoinst + s390 worker jumphost deps
Group:          Development/Tools/Other
Requires:       os-autoinst
Requires:       %s390_zvm_requires

%description s390-deps
Convenience package providing os-autoinst + s390 worker jumphost dependencies.


%prep
%setup -q

# don't require qemu within OBS
# and exclude known flaky tests in OBS check
# https://progress.opensuse.org/issues/52652
# 07-commands: https://progress.opensuse.org/issues/60755
# 29-backend-driver: https://progress.opensuse.org/issues/105061
# 29-backend-generalhw: https://progress.opensuse.org/issues/117352
for i in 07-commands 13-osutils 14-isotovideo 18-qemu-options 18-backend-qemu 29-backend-driver 29-backend-generalhw 99-full-stack; do
    rm t/$i.t
done
# exclude unnecessary author tests
rm xt/00-tidy.t
# Remove test relying on a git working copy
rm xt/30-make.t
# https://progress.opensuse.org/issues/114881
rm t/27-consoles-vmware.t
# exclude tests requiring OCR dependencies when those are disabled
%if %{without ocr}
rm t/02-test_ocr.t
%endif

%build
%define __builder ninja
%cmake \
    -DOS_AUTOINST_DOC_DIR:STRING="%{_docdir}/%{name}" \
    -DOS_AUTOINST_VERSION:STRING="%{version}" \
    -DSYSTEMD_SERVICE_DIR:STRING="%{_unitdir}"
%cmake_build

%install
%cmake_install install-openvswitch

ls -lR %buildroot
find %{buildroot} -type f -name .packlist -print0 | xargs -0 --no-run-if-empty rm -f
find %{buildroot} -depth -type d -and -not -name distri -print0 | xargs -0 --no-run-if-empty rmdir 2>/dev/null || true
%perl_gen_filelist
#
# service symlink
mkdir -p %{buildroot}%{_sbindir}
ln -s ../sbin/service %{buildroot}%{_sbindir}/rcos-autoinst-openvswitch
#
# we need the stale symlinks to point to git
export NO_BRP_STALE_LINK_ERROR=yes

%check
export CI=1
# set TESSDATA_PREFIX for 02-ocr.t
export TESSDATA_PREFIX="%{_datadir}/tessdata/"
# account for sporadic slowness in build environments
# https://progress.opensuse.org/issues/89059
export OPENQA_TEST_TIMEOUT_SCALE_CI=20
# We don't want fatal warnings during package building
export PERL_TEST_WARNINGS_ONLY_REPORT_WARNINGS=1
# Enable verbose test output as we can not store test artifacts within package
# build environments in case of needing to investigate failures
export PROVE_ARGS="--timer -v --nocolor"
cd %{__builddir}
%cmake_build check-pkg-build

%pre openvswitch
%service_add_pre os-autoinst-openvswitch.service

%post openvswitch
%service_add_post os-autoinst-openvswitch.service
if test $1 -eq 1 ; then
  %{_bindir}/dbus-send --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig 2>&1 || :
fi

%preun openvswitch
%service_del_preun os-autoinst-openvswitch.service

%postun openvswitch
%service_del_postun os-autoinst-openvswitch.service

%files -f %{name}.files
%defattr(-,root,root)
%{_docdir}/os-autoinst
%dir %{_prefix}/lib/os-autoinst
%{_prefix}/lib/os-autoinst/videoencoder
%{_prefix}/lib/os-autoinst/basetest.pm
#
%{_prefix}/lib/os-autoinst/dmidata
#
%{_prefix}/lib/os-autoinst/bmwqemu.pm
%{_prefix}/lib/os-autoinst/commands.pm
%{_prefix}/lib/os-autoinst/distribution.pm
%{_prefix}/lib/os-autoinst/testapi.pm
%{_prefix}/lib/os-autoinst/mmapi.pm
%{_prefix}/lib/os-autoinst/lockapi.pm
%{_prefix}/lib/os-autoinst/log.pm
%{_prefix}/lib/os-autoinst/cv.pm
%{_prefix}/lib/os-autoinst/ocr.pm
%{_prefix}/lib/os-autoinst/needle.pm
%{_prefix}/lib/os-autoinst/osutils.pm
%{_prefix}/lib/os-autoinst/signalblocker.pm
%{_prefix}/lib/os-autoinst/myjsonrpc.pm
%{_prefix}/lib/os-autoinst/backend
%{_prefix}/lib/os-autoinst/OpenQA
%{_prefix}/lib/os-autoinst/consoles
%{_prefix}/lib/os-autoinst/autotest.pm
%{_prefix}/lib/os-autoinst/*.py
%{_prefix}/lib/os-autoinst/check_qemu_oom
%{_prefix}/lib/os-autoinst/dewebsockify
%{_prefix}/lib/os-autoinst/vnctest

%dir %{_prefix}/lib/os-autoinst/schema
%{_prefix}/lib/os-autoinst/schema/Wheels-01.yaml

%files openvswitch
%defattr(-,root,root)
%{_prefix}/lib/os-autoinst/os-autoinst-openvswitch
%{_unitdir}/os-autoinst-openvswitch.service
%config /etc/dbus-1/system.d/org.opensuse.os_autoinst.switch.conf
%{_sbindir}/rcos-autoinst-openvswitch

%files devel
%ifarch x86_64
%files qemu-kvm
%files qemu-x86
%endif
%files swtpm
%files s390-deps

%changelog
