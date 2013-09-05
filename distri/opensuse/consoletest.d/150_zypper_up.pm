use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;

	become_root();

	# Killall is used here, make sure that is installed
	script_run("zypper -n -q in psmisc");

	script_run("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	if(!$ENV{NET} && !$ENV{TUMBLEWEED} && !$ENV{EVERGREEN} && $ENV{SUSEMIRROR}) {
		# non-NET installs have only milestone repo, which might be incompatible.
		my $repourl = $ENV{SUSEMIRROR};
		unless ($ENV{FULLURL}) {
		    $repourl = "http://$repourl/repo/oss";
		};
		script_run("zypper ar $repourl Factory");
	}
	script_run("zypper -n patch -l && echo 'worked' > /dev/$serialdev");
        waitserial("worked", 700) || die "zypper failed";
        $self->check_screen("first_run"); 
	script_run("zypper -n patch -l && echo 'worked' > /dev/$serialdev"); # first one might only have installed "update-test-affects-package-manager"
	waitserial("worked", 700) || die "zypper failed";
        $self->check_screen("second_run");
	script_run("rpm -q libzypp zypper", 0);
	checkneedle("rpm-q-libzypp", 5);
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_run("zypper -n -q patch", 0);
	checkneedle("zypper-patch-3", 30);
	script_run('echo $?');
	script_run('exit');
	$self->check_screen;
}

sub test_flags() {
	return {'milestone' => 1};
}

1;
