#!/usr/bin/perl -w

use strict;
use JSON::RPC::Client;
my $client = new JSON::RPC::Client;
my $port = ($ENV{QEMUPORT} || 15222) + 2;

my $url = "http://tanana.suse.de:$port/jsonrpc/API";

my %cmds = map { $_ => 0 } ('stop_waitforneedle', 'quit', 'stop_vm', 'freeze_vm', 'cont_vm');
$client->prepare($url, [keys %cmds]);
for my $cmd (@ARGV) {
	unless (exists $cmds{$cmd}) {
		warn "invalid command $cmd";
		next;
	}
#print $client->stop_waitforneedle(), "\n";
	eval {
		$client->$cmd();
	}
}
