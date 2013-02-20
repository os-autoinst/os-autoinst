#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my %notinupgrade=qw(timezone 1 disk 1 usersettings 1 automaticconfiguration 1);
	my %notinlive=(%notinupgrade,qw(welcome 1 installationoverview 1 performinstallation 1));
	my @stages=(qw"booted");
	my $results=\%::results;
	foreach my $s (@stages) {
		next if($notinupgrade{$s} && $ENV{UPGRADE});
		next if($notinlive{$s} && $ENV{LIVETEST});
		my $found=0;
		foreach(keys(%::stageseen)) {if(m/$s/){$found=1;last;}}
		$results->{$s}=($found?"OK":"unknown");
		::printresult $s;
		return 1 if ::is_ok($results->{mediacheck});
	}

	autotest::runtest("$ENV{CASEDIR}/inst.d/010_initenv.pm",sub{my $test=shift;$test->run;});

	autotest::runtestdir("$scriptdir/inst.d", \&::checkfunc);
	autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/consoletest.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/x11test.d", \&::checkfunc);

	my $overall=(::is_ok($results->{xterm}) or ::is_ok($results->{sshxterm}) or ::is_ok($results->{firefox}));
	if($ENV{TEXTMODE}) {$overall=1}
	for my $test (qw(zypper_in yast2_lan isosize)) {
		next if($test eq "automaticconfiguration" && ($ENV{UPGRADE}||$ENV{LIVETEST}));
		$overall=0 unless ::is_ok $results->{$test};
	}
	if(::is_ok $results->{mediacheck}) { return $results->{mediacheck} }
	return $overall;
}

1;
