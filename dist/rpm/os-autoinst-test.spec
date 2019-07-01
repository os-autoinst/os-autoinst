%define name_ext -test
%define         short_name os-autoinst
Name:           %{short_name}%{?name_ext}
Version:        4.5.1544111663.31867f0e
Release:        0
Summary:        test package for os-autoinst
License:        GPL-2.0+
#BuildRequires:  %{short_name} == %{version}
BuildRequires:  %{short_name}

%description
.

%prep
# workaround to prevent post/install failing assuming this file for whatever
# reason
touch %{_sourcedir}/%{short_name}

%build
# call one of the components but not openqa itself which would need a valid
# configuration
isotovideo --help
echo '1;' > main.pm
mkdir needles
cat - > vars.json <<EOF
{
    "CASEDIR": "/tmp",
    "PRJDIR": "/tmp"
}
EOF
isotovideo -d casedir=$(pwd -P) productdir=$(pwd -P) |& tee isotovideo.log ||:
grep 'no kvm-img/qemu-img found' isotovideo.log

%install
# disable debug packages in package test to prevent error about missing files
%define debug_package %{nil}

%changelog
