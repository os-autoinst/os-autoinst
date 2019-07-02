#
# spec file for package os-autoinst
#
# Copyright (c) 2018 SUSE LINUX GmbH, Nuernberg, Germany.
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
Version:        4.5.1544111663.31867f0e
Release:        0
Summary:        OS-level test automation
License:        GPL-2.0-or-later
Group:          Development/Tools/Other
Url:            https://github.com/os-autoinst/os-autoinst
Source0:        %{name}-%{version}.tar.xz
BuildRequires:  autoconf
BuildRequires:  automake
BuildRequires:  gcc-c++
BuildRequires:  libtool
BuildRequires:  opencv-devel > 3.0
BuildRequires:  pkg-config
BuildRequires:  perl(Module::CPANfile)
BuildRequires:  perl(Perl::Tidy)
BuildRequires:  perl(Test::Compile)
BuildRequires:  pkgconfig(fftw3)
BuildRequires:  pkgconfig(libpng)
BuildRequires:  pkgconfig(sndfile)
BuildRequires:  pkgconfig(theoraenc)
# just for the test suite
BuildRequires:  qemu-tools
Requires:       /usr/bin/qemu-img
Requires:       git-core
Requires:       optipng
%{perl_requires}
Requires:       qemu >= 2.0.0
Recommends:       tesseract-ocr
%define t_requires perl(Carp::Always) perl(Data::Dump) perl(Crypt::DES) perl(JSON) perl(autodie) perl(Class::Accessor::Fast) perl(Exception::Class) perl(File::Touch) perl(File::Which) perl(IPC::Run::Debug) perl(Net::DBus) perl(Net::SNMP) perl(Net::IP) perl(IPC::System::Simple) perl(Net::SSH2) perl(XML::LibXML) perl(XML::SemanticDiff) perl(Test::Exception) perl(Test::Output) perl(Test::Fatal) perl(Test::Warnings) perl(Pod::Coverage) perl(Test::Pod) perl(Test::MockModule) perl(Devel::Cover) perl(JSON::XS) perl(List::MoreUtils) perl(Mojo::IOLoop::ReadWriteProcess) perl(Test::Mock::Time) perl(Socket::MsgHdr) perl(Cpanel::JSON::XS) perl(IO::Scalar)
BuildRequires:  %t_requires
Requires:       %t_requires
BuildRequires:  perl(Mojolicious)
Requires:       perl(Mojolicious) >= 7.92
Requires:       perl(Mojo::IOLoop::ReadWriteProcess) >= 0.23
# we shuffle around a lot of JSON, so make sure this is fast
# and the JSON modules have subtle differences and we only test against XS in production
Requires:       perl(JSON::XS)
Recommends:     /usr/bin/xkbcomp /usr/bin/Xvnc dumponlyconsole
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
sed -e 's,/bin/env python,/bin/python,' -i crop.py

%build
mkdir -p m4
autoreconf -f -i
%configure --docdir=%{_docdir}/%{name}
make INSTALLDIRS=vendor %{?_smp_mflags}

%install
%make_install INSTALLDIRS=vendor
# Replace version number from git to what's reported by the package
sed  -i 's/ my $thisversion = qx{git rev-parse HEAD};/ my $thisversion = "%{version}";/' %{buildroot}/usr/bin/isotovideo
# only internal stuff
rm %{buildroot}/usr/lib/os-autoinst/tools/{tidy,check_coverage,absolutize}
rm -r %{buildroot}/usr/lib/os-autoinst/tools/lib/perlcritic
#
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
# disable code quality checks - not worth the time for package builds
sed '/perlcritic/d' -i Makefile
sed '/Perl::Critic/d' -i cpanfile
sed '/tidy/d' -i Makefile
rm tools/lib/perlcritic/Perl/Critic/Policy/*.pm

# don't require qemu within OBS
cp t/05-pod.t t/18-qemu-options.t
cp t/05-pod.t t/99-full-stack.t

# should work offline
for p in $(cpanfile-dump); do rpm -q --whatprovides "perl($p)"; done
make check VERBOSE=1

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
%{_libexecdir}/os-autoinst/myjsonrpc.pm
%{_libexecdir}/os-autoinst/backend
%{_libexecdir}/os-autoinst/OpenQA
%{_libexecdir}/os-autoinst/consoles
%dir %{_libexecdir}/os-autoinst/tools
%{_libexecdir}/os-autoinst/tools/preparepool
%{_libexecdir}/os-autoinst/autotest.pm
%{_libexecdir}/os-autoinst/crop.py

%files openvswitch
%defattr(-,root,root)
%{_libexecdir}/os-autoinst/os-autoinst-openvswitch
/usr/lib/systemd/system/os-autoinst-openvswitch.service
%config /etc/dbus-1/system.d/org.opensuse.os_autoinst.switch.conf
%{_sbindir}/rcos-autoinst-openvswitch

%changelog
