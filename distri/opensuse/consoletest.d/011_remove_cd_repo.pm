use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DVD};
}

sub run()
{
        my $self=shift;

	become_root();
        script_run("grep -l cd:/// /etc/zypp/repos.d/* | xargs rm -v");
	waitforneedle("cdreporemoved");
	script_run('exit');
}

sub test_flags() {
  return {'milestone' => 1};
}

1;
