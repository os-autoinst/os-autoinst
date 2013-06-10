#!/usr/bin/perl -w

package backend::qemu;
use strict;
use base ('backend::baseclass');
use threads;
use threads::shared;
require File::Temp;
use File::Temp ();
use Time::HiRes "sleep";

sub init() {
	my $self = shift;
	$self->{'mousebutton'} = shared_clone({'left' => 0, 'right' => 0, 'middle' => 0});
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
	sleep(0.1);
}

sub stop_audiocapture($) {
	my ($self, $index) = @_;
	$self->send("stopcapture $index");
	sleep(0.1);
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
	die "startqemu failed: $@" if $@;
	$self->open_management();
	$self->send(bmwqemu::fileContent("$ENV{HOME}/.autotestvncpw")||"");
}

sub do_stop_vm($) {
	my $self = shift;
	$self->send('quit');
	$self->close_con();
	sleep(0.1);
	kill(15, $self->{'pid'});
	unlink($self->{'pidfilename'});
}

sub do_snapshot($) {
	my ($self, $filename) = @_;
	$self->send("snapshot_blkdev virtio0 $filename qcow2");
}

sub do_savevm($) {
	my ($self, $vmname) = @_;
	$self->send("savevm $vmname");
	$self->_wait();
}

sub do_loadvm($) {
	my ($self, $vmname) = @_;
	$self->send("loadvm $vmname");
	$self->_wait();
	$self->send("stop");
	$self->send("cont");
}

sub do_delvm($) {
	my ($self, $vmname) = @_;
	$self->send("delvm $vmname");
}

# baseclass virt method overwrite end


# management console

sub open_management($) {
	my $self=shift;
	my $mgmtcon = $self->{mgmt} = backend::qemu::mgmt->new();
	$self->{mgmt}->start();
	$self->send("cont"); # start VM execution
}


sub close_con($) {
	my $self=shift;
	$self->{mgmt}->stop();
	$self->{mgmt} = undef;
}

sub send($) {
	my $self = shift;
	my $cmdstr = shift;
	while ($self->{mgmt}->{rspqueue}->dequeue_nb()) { };
	$self->{mgmt}->send($cmdstr);
	# QEMU return a line with the command. Remove from the queue.
	$self->{mgmt}->{rspqueue}->dequeue() if ($cmdstr ne 'quit');
}

sub _wait($) {
    my $self = shift;
    $self->send("help");
    bmwqemu::diag "Waiting output from rspqueue ...";
    my $result = $self->{mgmt}->{rspqueue}->dequeue();
    bmwqemu::diag "Response from rspqueue ...\n$result";
}

# management console end

package backend::qemu::mgmt;

use threads;
use threads::shared;

sub new {
	my $class = shift;
	my $self :shared = bless(shared_clone({class=>$class}), $class);
	$self->{cmdqueue} = Thread::Queue->new();
	$self->{rspqueue} = Thread::Queue->new();
	return $self;
}

sub start
{
	my $self = shift;
	my $addr = "localhost:$ENV{QEMUPORT}";
	my $tid = shared_clone(threads->create(\&_run, $addr, $self->{cmdqueue}, $self->{rspqueue}));
	$self->{runthread} = $tid;
}

sub stop
{
	my $self = shift;
	my $cmd = shift;

	$self->{cmdqueue}->enqueue(undef);

	print " waiting for console read thread to quit...\n";
	$self->{runthread}->join();
	print "done\n";
	$self->{runthread} = undef;
}


sub send
{
	my $self = shift;
	my $cmd = shift;

	#print "enqueue <$cmd>\n";
	$self->{cmdqueue}->enqueue($cmd);
}

sub _readconloop($$) {
	# read all output from management console and forward it to STDOUT
	my $socket = shift;
	my $rspqueue = shift;
	$|=1;
	while(<$socket>) {
	  #print $_;
	  chomp;
	  $rspqueue->enqueue($_);
	}
	bmwqemu::diag("exiting management console read loop");
	bmwqemu::diag("ALARM: qemu virtual machine quit! - exiting...");
	# XXX
	# TODO: set flag on graceful exit to avoid this
	alarm(3) # kill all extra threads soon
}

sub _run
{
	my $addr = shift;
	my $cmdqueue = shift;
	my $rspqueue = shift;
	my $socket = IO::Socket::INET->new($addr);

	bmwqemu::diag "started mgmt loop with thread id " . threads->tid();

	my $oldfh = select($socket); $|=1; select($oldfh); # autoflush
	my $readthread = threads->create(\&_readconloop, $socket, $rspqueue); # without this, qemu will block

	my $cmdstr;
	while (defined($cmdstr = $cmdqueue->dequeue())) {
		#printf "sending $cmdstr\n";
		print $socket "$cmdstr\n";
	}
	close($socket);
	$readthread->join();
	bmwqemu::diag("management thread exit");
}

1;
