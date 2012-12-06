#!/usr/bin/perl -w

package backend::qemu;
use strict;
use threads;
use threads::shared;  
use bmwqemu;

sub send($)
{
	my $self=shift;
	my $m=$self->{managementcon};
	print $m shift(@_)."\n";
}

sub handlemuxcon($)
{ my $conn=shift;
	while(<$conn>) {
		chomp;
		qemusend $_;
	}
}

# accept connections and forward to management console
sub conmuxloop
{
	my $listen_sock=IO::Socket::INET->new(
		Listen    => 1,
	#	LocalAddr => 'localhost',
		LocalPort => $ENV{QEMUPORT}+1,
		Proto     => 'tcp',
		ReUseAddr => 1,
	);

	while(my $conn=$listen_sock->accept()) {
		# launch one thread per connection
		my $thr=threads->create(\&handlemuxcon, $conn);
		$thr->detach();
	}
}

# read all output from management console and forward it to STDOUT
sub readconloop
{
	my $managementcon=shift;
	$|=1;
	while(<$managementcon>) {
		print $_;
	}
	bmwqemu::diag "exiting management console read loop";
	unlink $bmwqemu::qemupidfilename;
	alarm 3; # kill all extra threads soon
}

sub open_management()
{
	my $self=shift;
	my $managementcon=IO::Socket::INET->new("localhost:$ENV{QEMUPORT}") or bmwqemu::mydie "error opening management console: $!";
	$self->{managementcon}=$managementcon;
	my $oldfh=select($managementcon); $|=1; select($oldfh); # autoflush
	$self->{conmuxthread}=threads->create(\&conmuxloop); # allow external qemu input
	$self->{conmuxthread}->detach();
	$self->{readconthread}=threads->create(\&readconloop, $managementcon); # without this, qemu will block
	$self->{readconthread}->detach();
	qemusend("cont"); # start VM execution
	$managementcon;
}

sub new()
{
	my $class=shift;
	my $self={class=>$class};
	$self=bless $self, $class;
	return $self;
}

sub close_con()
{
	my $self=shift;
	close $self->{managementcon};
	qemusend "";
}

sub start_vm
{
	do "inst/startqemu.pm";
}

1;
