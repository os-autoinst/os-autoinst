use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde" && !$ENV{TUMBLEWEED} && !$ENV{NICEVIDEO};
}

sub run()
{
	my $self=shift;
	x11_start_program("xterm");
	#script_sudo("/sbin/OneClickInstallUI http://i.opensu.se/Documentation:Tools/sikuli");
	script_sudo("zypper ar http://download.opensuse.org/repositories/Documentation:/Tools/openSUSE_Factory/ doc");
	script_sudo("zypper ar http://download.opensuse.org/repositories/home:/bmwiedemann:/branches:/Documentation:/Tools/openSUSE_Factory/ bmwdoc");
	script_sudo("zypper -n --gpg-auto-import-keys in sikuli yast2-ycp-ui-bindings-devel ; echo sikuli installed > /dev/ttyS0");
	waitserial("sikuli installed", 200);
	script_run("cd /tmp;curl openqa.opensuse.org/opensuse/qatests/ykuli.tar | tar x ; cd ykuli");
	$self->take_screenshot;
	script_run("./run_ykuli.sh ; echo yastsikuli finished > /dev/ttyS0");
	waitserial("yastsikuli finished", 680);
	$self->take_screenshot;
	sendkey "alt-f4";
	script_sudo_logout();
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
