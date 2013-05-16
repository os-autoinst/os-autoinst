#!/usr/bin/perl -w

use strict;
use JSON::RPC::Client;
my $client = new JSON::RPC::Client;
my $port = ($ENV{QEMUPORT} || 15222) + 2;

my $url = "http://tanana.suse.de:$port/jsonrpc/API";

my %cmds = map { $_ => 0 } (qw/
	stop_waitforneedle
	quit
	stop_vm
	freeze_vm
	cont_vm
	get_needle_template
	continue
	/);
$cmds{set_interactive} = 1;
$cmds{save_needle} = 1;
$client->prepare($url, [keys %cmds]) or die "$!\n";
while (my $cmd = shift @ARGV) {
	unless (exists $cmds{$cmd}) {
		warn "invalid command $cmd";
		next;
	}
	my @args;
	@args = splice(@ARGV,0,$cmds{$cmd}) if $cmds{$cmd};
	printf "calling %s(%s)\n", $cmd, join(', ', @args);
	my $ret;
	eval qq{
		\$ret = \$client->$cmd(\@args) or die "\$!\n";
	};
	die "$@" if ($@);
	print "$ret\n" if $ret;
}
