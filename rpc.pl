#!/usr/bin/perl -w

use strict;
use JSON::RPC::Client;
my $client = new JSON::RPC::Client;
my $port = ($ENV{QEMUPORT} || 15222) + 2;

my $url = "http://tanana.suse.de:$port/jsonrpc/API";

$client->prepare($url, ['stop_waitforneedle', 'quit', 'stop_vm']);
#print $client->stop_waitforneedle(), "\n";
$client->stop_vm();
