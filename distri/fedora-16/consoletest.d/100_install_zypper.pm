use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	script_sudo("wget -O/etc/yum.repos.d/zypp.repo http://download.opensuse.org/repositories/zypp:/Head/Fedora_16/zypp:Head.repo");
	script_sudo("yum -y install zypper");
	script_sudo("zypper --no-gpg-checks ref");
	waitstillimage(12,90);
}

1;
