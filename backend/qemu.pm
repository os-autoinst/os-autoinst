#!/usr/bin/perl -w

package backend::qemu;
use strict;
use base ('backend::baseclass');
use threads;
require File::Temp;
use File::Temp ();
use Time::HiRes "sleep";

sub init() {
	my $self = shift;
	$self->{'mousebutton'} = {'left' => 0, 'right' => 0, 'middle' => 0};
	$self->{'pid'} = undef;
	$self->{'pidfilename'} = 'qemu.pid';
}


# baseclass virt method overwrite

sub sendkey($) {
	my ($self, $key) = @_;
	$self->send("sendkey $key");
}

# warning: will not work due to https://bugs.launchpad.net/qemu/+bug/752476
sub mouse_set($$) {
	my $self = shift;
	my ($x, $y) = @_;
	# ... assuming size of screen is 800x600
	# (FIXME: size from last screenshot?)
	my ($rx, $ry) = (800, 600);
	my $ax = int($x / $rx * 0x7fff);
	my $ay = int($y / $ry * 0x7fff);
	$self->send("mouse_move $ax $ay");
}

sub mouse_button($$$) {
	my ($self, $button, $bstate) = @_;;
	$self->{'mousebutton'}->{$button} = $bstate;
	my $btn_bin = 0;
	$btn_bin |= 0b001 if($self->{'mousebutton'}->{'left'});
	$btn_bin |= 0b010 if($self->{'mousebutton'}->{'right'});
	$btn_bin |= 0b100 if($self->{'mousebutton'}->{'middle'});
	$self->send("mouse_button $btn_bin");
}

sub mouse_hide(;$) {
	my $self = shift;
	my $border_offset = shift || 0;
	unless($border_offset) {
		$self->send("mouse_move 0x7fff 0x7fff");
		sleep 1;
		# work around no reaction first time
		$self->send("mouse_move 0x7fff 0x7fff");
	}
	else {
		# not completely in the corner to not trigger hover actions
		$self->send("mouse_move 0x7000 0x7000");
	}
}

sub screendump() {
	my $self = shift;
	my $tmp = File::Temp->new( UNLINK => 0, SUFFIX => '.ppm', OPEN => 0 );
	$self->send("screendump $tmp");
	my $ret;
        while (!defined $ret) {
	  sleep(0.02);
	  my $fs = -s $tmp;
	  next if ($fs < 70);
	  my $header;
	  next if (!open(PPM, $tmp));
	  if (read(PPM, $header, 70) < 70) {
	    close(PPM);
	    next;
	  }
	  close(PPM);
	  my ($xres,$yres) = ($header=~m/\AP6\n(?:#.*\n)?(\d+) (\d+)\n255\n/);
	  next if(!$xres);
	  my $d=$xres*$yres*3+length($&);
	  next if ($fs != $d);
          $ret = tinycv::read($tmp);
        }
	unlink $tmp;
	return $ret;
}

sub raw_alive($) {
	my $self = shift;
	return 0 unless $self->{'pid'};
	return kill(0, $self->{'pid'});
}

sub start_audiocapture($) {
	my ($self, $filename) = @_;
	$self->send("wavcapture $filename 44100 16 1");
}
sub stop_audiocapture($) {
	my ($self, $index) = @_;
	$self->send("stopcapture $index");
}

sub power($) {
	# parameters: acpi, reset, (on), off
	my ($self, $action) = @_;
	if ($action eq 'acpi') {
		$self->send("system_powerdown");
	}
	elsif ($action eq 'reset') {
		$self->send("system_reset");
	}
	elsif ($action eq 'off') {
		$self->send("quit");
	}
}

sub eject_cd(;$) {
	my $self = shift;
	$self->send("eject -f ide1-cd0");
}

sub cpu_stat($) {
	my $self = shift;
	my $stat = bmwqemu::fileContent("/proc/".$self->{'pid'}."/stat");
	my @a=split(" ", $stat);
	return @a[13,14];
}

sub do_start_vm($) {
	my $self = shift;
	eval bmwqemu::fileContent("$bmwqemu::scriptdir/inst/startqemu.pm");
	$self->open_management();
	$self->send(bmwqemu::fileContent("$ENV{HOME}/.autotestvncpw")||"");
}

sub do_stop_vm($) {
	my $self = shift;
	$self->send('quit');
	sleep(0.1);
	kill(15, $self->{'pid'});
	unlink($self->{'pidfilename'});
}

# baseclass virt method overwrite end


# management console

sub readconloop($) {
	# read all output from management console and forward it to STDOUT
	my $self = shift;
	$|=1;
	my $conn = $self->{'managementcon'};
	while(<$conn>) {
		# print $_;
	}
	bmwqemu::diag("exiting management console read loop");
	unlink($self->{'pidfilename'});
	bmwqemu::diag("ALARM: qemu virtual machine quit! - exiting...");
	# FIXME: this leads to unclean exit
	alarm 3; # kill all extra threads soon
}

sub open_management($) {
	my $self=shift;
	my $managementcon=IO::Socket::INET->new("localhost:$ENV{QEMUPORT}") or bmwqemu::mydie("error opening management console: $!");
	$self->{managementcon}=$managementcon;
	my $oldfh=select($managementcon); $|=1; select($oldfh); # autoflush
	$self->{readconthread}=threads->create(\&readconloop, $self); # without this, qemu will block
	$self->{readconthread}->detach();
	$self->send("cont"); # start VM execution
	$managementcon;
}


sub close_con($) {
	my $self=shift;
	close($self->{managementcon});
	$self->send("");
}

sub send($) {
	my $self = shift;
	my $cmdstr = shift;
	my $m = $self->{managementcon};
	print $m $cmdstr."\n";
}

# management console end






1;
