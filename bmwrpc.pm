#!/usr/bin/perl -w

package bmwrpc;

use bmwqemu qw/$stop_waitforneedle/;

use base qw(JSON::RPC::Procedure);

sub stop_waitforneedle : Public {
	$bmwqemu::stop_waitforneedle = 1;
}

sub quit : Public {
	alarm 1;
}

1;
