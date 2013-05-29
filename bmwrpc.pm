#!/usr/bin/perl -w

package bmwrpc;

use threads;
use threads::shared;
use JSON;
use Data::Dump;

use bmwqemu ();

use base qw(JSON::RPC::Procedure);

sub stop_waitforneedle : Public {
	$bmwqemu::stop_waitforneedle = 1;
}

sub stop_vm : Public {
	printf "bmwrpc stop_vm %d\n", threads->tid();
	bmwqemu::stop_vm();
	print "<< done\n";
}

sub cont_vm : Public {
	bmwqemu::cont_vm();
}

sub freeze_vm : Public {
	bmwqemu::freeze_vm();
}

sub alive : Public {
	bmwqemu::alive();
}

sub set_interactive : Public(suffix)
{
	my ($self, $args) = @_;
	$bmwqemu::interactive_mode = $args->[0];
	print ">> interactive mode set to $bmwqemu::interactive_mode\n";
}

sub get_needle_template : Str
{
	lock($bmwqemu::interactive_lock);
	return undef unless $bmwqemu::waiting_for_new_needle;
	return JSON->new->pretty->encode( $bmwqemu::needle_template );
}

# first parameter is the name
# second parameter is the needle structure (as a real hash)
sub save_needle($) : Public(data)
{
	my ($self, $args) = @_;
	my $new_needle = $args->[1];
	$new_needle->{"name"} = $args->[0];
	$new_needle->{'name'} =~ s/[^a-zA-Z0-9]/_/g;
	lock($bmwqemu::interactive_lock);
	$bmwqemu::waiting_for_new_needle = shared_clone($new_needle);
	cond_signal($bmwqemu::interactive_lock);
	return 1;
}

# continue if main thread is waiting for user input. Will lead to fail if
# waitforneedle was called and simple continue for checkneedle.
sub continue($) : Public
{
	lock($bmwqemu::interactive_lock);
	$bmwqemu::waiting_for_new_needle = undef;
	cond_signal($bmwqemu::interactive_lock);
}

sub quit : Public {
	kill('SIGTERM', $$);
	# need to continue the main thread in case it's waiting
	lock($bmwqemu::interactive_lock);
	cond_signal($bmwqemu::interactive_lock);
}

1;
