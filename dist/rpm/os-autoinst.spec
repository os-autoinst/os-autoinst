#
# spec file for package os-autoinst
#
# Copyright (c) 2018 SUSE LLC
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
%if 0%{?suse_version} > 1500
# openSUSE Tumbleweed
%define opencv_require pkgconfig(opencv4)
%else
%define opencv_require pkgconfig(opencv)
%endif
# The following line is generated from dependencies.yaml
%define build_base_requires %opencv_require gcc-c++ perl(Pod::Html) pkg-config pkgconfig(fftw3) pkgconfig(libpng) pkgconfig(sndfile) pkgconfig(theoraenc)
# The following line is generated from dependencies.yaml
%define build_legacy_requires %build_base_requires autoconf automake libtool make perl(ExtUtils::Embed) perl(ExtUtils::MakeMaker) >= 6.66 perl(Module::CPANfile)
# The following line is generated from dependencies.yaml
%define build_requires %build_base_requires cmake ninja
# The following line is generated from dependencies.yaml
%define main_requires git-core perl(B::Deparse) perl(Carp) perl(Carp::Always) perl(Class::Accessor::Fast) perl(Config) perl(Cpanel::JSON::XS) perl(Crypt::DES) perl(Cwd) perl(Data::Dumper) perl(Digest::MD5) perl(DynaLoader) perl(English) perl(Errno) perl(Exception::Class) perl(Exporter) perl(ExtUtils::testlib) perl(Fcntl) perl(File::Basename) perl(File::Find) perl(File::Path) perl(File::Spec) perl(File::Temp) perl(File::Touch) perl(File::Which) perl(IO::Handle) perl(IO::Scalar) perl(IO::Select) perl(IO::Socket) perl(IO::Socket::INET) perl(IO::Socket::UNIX) perl(IPC::Open3) perl(IPC::Run::Debug) perl(IPC::System::Simple) perl(List::MoreUtils) perl(List::Util) perl(Mojo::IOLoop::ReadWriteProcess) >= 0.26 perl(Mojo::JSON) perl(Mojo::Log) perl(Mojo::URL) perl(Mojo::UserAgent) perl(Mojolicious) >= 8.42 perl(Mojolicious::Lite) perl(Net::DBus) perl(Net::IP) perl(Net::SNMP) perl(Net::SSH2) perl(POSIX) perl(Scalar::Util) perl(Socket) perl(Socket::MsgHdr) perl(Term::ANSIColor) perl(Thread::Queue) perl(Time::HiRes) perl(Try::Tiny) perl(XML::LibXML) perl(XML::SemanticDiff) perl(autodie) perl(base) perl(constant) perl(integer) perl(strict) perl(version) perl(warnings) perl-base
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
%define spellcheck_make_args_for_autotools %{nil}
%else
%define spellcheck_requires %{nil}
%define spellcheck_make_args_for_autotools CHECK_DOC=0
%endif
# The following line is generated from dependencies.yaml
%define test_base_requires %main_requires perl(Benchmark) perl(Devel::Cover) perl(FindBin) perl(Pod::Coverage) perl(Test::Exception) perl(Test::Fatal) perl(Test::Mock::Time) perl(Test::MockModule) perl(Test::MockObject) perl(Test::Mojo) perl(Test::More) perl(Test::Output) perl(Test::Pod) perl(Test::Strict) perl(Test::Warnings) >= 0.029 procps python3-setuptools qemu qemu-tools qemu-x86
# The following line is generated from dependencies.yaml
%define test_legacy_requires %build_legacy_requires %test_base_requires
# The following line is generated from dependencies.yaml
%define test_requires %build_requires %spellcheck_requires %test_base_requires perl(YAML::PP) python3-yamllint
# The following line is generated from dependencies.yaml
%define devel_requires %test_requires perl(Devel::Cover) perl(Devel::Cover::Report::Codecov) perl(Perl::Tidy)
%if 0%{?suse_version} == 1315
BuildRequires:  %test_legacy_requires
%else
BuildRequires:  %test_requires
%endif
Requires:       %main_requires
Recommends:     tesseract-ocr
Recommends:     /usr/bin/xkbcomp /usr/bin/Xvnc dumponlyconsole
Recommends:     qemu >= 2.0.0
Recommends:     /usr/bin/qemu-img
Requires(pre):  %{_bindir}/getent
Requires(pre):  %{_sbindir}/useradd
BuildRoot:      %{_tmppath}/%{name}-%{version}-build

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

%description openvswitch
This package contains openvswitch support for os-autoinst.

%prep
%setup -q
sed -e 's,/bin/env python,/bin/python3,' -i crop.py
# Replace version number from git to what's reported by the package
sed  -i 's/ my $thisversion = qx{git.*rev-parse HEAD}.*;/ my $thisversion = "%{version}";/' isotovideo

# don't require qemu within OBS
# and exclude known flaky tests in OBS check
# https://progress.opensuse.org/issues/52652
# 07-commands: https://progress.opensuse.org/issues/60755
for i in 07-commands 13-osutils 14-isotovideo 18-qemu-options 18-backend-qemu 99-full-stack; do
    rm t/$i.t
done

%build
%if 0%{?suse_version} == 1315
autoreconf -f -i
%configure --docdir=%{_docdir}/%{name}
make %{?_smp_mflags} INSTALLDIRS=vendor
%else
%define __builder ninja
%cmake -DOS_AUTOINST_DOC_DIR:STRING=%{_docdir}/%{name}
%cmake_build
%endif

%install
%if 0%{?suse_version} == 1315
%make_install INSTALLDIRS=vendor
# remove internal tools
rm -r %{buildroot}/usr/lib/os-autoinst/tools/
%else
%cmake_install install-openvswitch
%endif

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
%if 0%{?suse_version} == 1315
sed '/perlcritic/d' -i Makefile
sed '/tidy/d' -i Makefile
sed '/Perl::Critic/d' -i cpanfile
rm -r t/27-make-update-deps.t tools/update-deps
# unstable test https://progress.opensuse.org/issues/69820
rm t/28-signalblocker.t
printf '#!/bin/sh\necho YAML syntax check disabled' > tools/check-yaml-syntax
make check test VERBOSE=1 %{spellcheck_make_args_for_autotools}
%else
cd %{__builddir}
%cmake_build check-pkg-build
%endif

%pre openvswitch
%service_add_pre os-autoinst-openvswitch.service

%post openvswitch
%service_add_post os-autoinst-openvswitch.service

%preun openvswitch
%service_del_preun os-autoinst-openvswitch.service

%postun openvswitch
%service_del_postun os-autoinst-openvswitch.service

%files -f %{name}.files
%defattr(-,root,root)
%{_docdir}/os-autoinst
%dir %{_libexecdir}/os-autoinst
%{_libexecdir}/os-autoinst/videoencoder
%{_libexecdir}/os-autoinst/basetest.pm
#
%{_libexecdir}/os-autoinst/dmidata
#
%{_libexecdir}/os-autoinst/bmwqemu.pm
%{_libexecdir}/os-autoinst/commands.pm
%{_libexecdir}/os-autoinst/distribution.pm
%{_libexecdir}/os-autoinst/testapi.pm
%{_libexecdir}/os-autoinst/mmapi.pm
%{_libexecdir}/os-autoinst/lockapi.pm
%{_libexecdir}/os-autoinst/cv.pm
%{_libexecdir}/os-autoinst/ocr.pm
%{_libexecdir}/os-autoinst/needle.pm
%{_libexecdir}/os-autoinst/osutils.pm
%{_libexecdir}/os-autoinst/signalblocker.pm
%{_libexecdir}/os-autoinst/myjsonrpc.pm
%{_libexecdir}/os-autoinst/backend
%{_libexecdir}/os-autoinst/OpenQA
%{_libexecdir}/os-autoinst/consoles
%{_libexecdir}/os-autoinst/autotest.pm
%{_libexecdir}/os-autoinst/crop.py

%files openvswitch
%defattr(-,root,root)
%{_libexecdir}/os-autoinst/os-autoinst-openvswitch
/usr/lib/systemd/system/os-autoinst-openvswitch.service
%config /etc/dbus-1/system.d/org.opensuse.os_autoinst.switch.conf
%{_sbindir}/rcos-autoinst-openvswitch

%files devel

%changelog
