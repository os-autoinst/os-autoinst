%define name_ext -test
%define         short_name os-autoinst-openvswitch
Name:           %{short_name}%{?name_ext}
Version:        4.6
Release:        0
Summary:        test package for %{short_name}
License:        GPL-2.0-or-later
BuildRequires:  %{short_name} == %{version}
ExcludeArch:    %{ix86}

%description
.

%prep
# workaround to prevent post/install failing assuming this file for whatever
# reason
touch %{_sourcedir}/%{short_name}

%build
# call one of the components but not openqa itself which would need a valid
# configuration
/usr/lib/os-autoinst/os-autoinst-openvswitch --help

%install
# disable debug packages in package test to prevent error about missing files
%define debug_package %{nil}

%changelog
