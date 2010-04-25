$|=1;

package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep);
use Exporter;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw($qemupid %cmd &sendkey &sendautotype &autotype &take_screenshot &qemualive &waitidle &open_management_console);


our $qemupid;
our $managementcon;
our %cmd=qw(
next alt-n
install alt-i
finish alt-f
accept alt-a
createpartsetup alt-c
custompart alt-c
addpart alt-d
donotformat alt-d
addraid alt-i
add alt-a
raid0 alt-0
raid1 alt-1
raid6 alt-6
raid10 alt-i
mountpoint alt-m
filesystem alt-s
acceptlicense alt-a
);

$ENV{INSTLANG}||="us";
if($ENV{INSTLANG} eq "de") {
	$cmd{"next"}="alt-w";
	$cmd{"createpartsetup"}="alt-e";
	$cmd{"custompart"}="alt-b";
	$cmd{"addpart"}="alt-h";
	$cmd{"finish"}="alt-b";
	$cmd{"accept"}="alt-r";
	$cmd{"donotformat"}="alt-n";
	$cmd{"add"}="alt-h";
	$cmd{"raid6"}="alt-d";
	$cmd{"raid10"}="alt-r";
	$cmd{"mountpoint"}="alt-e";
}

sub qemusend($)
{
	print shift(@_)."\n";
}

sub sendkey($)
{
	my $key=shift;
	qemusend "sendkey $key";
	sleep(0.05);
}

my %charmap=("."=>"dot", "/"=>"slash", 
   "\t"=>"tab", "\n"=>"ret", " "=>"spc", "\b"=>"backspace", "\e"=>"esc");

sub sendautotype($)
{
	my $string=shift;
	foreach my $letter (split("", $string)) {
		if($charmap{$letter}) { $letter=$charmap{$letter} }
		sendkey $letter;
	}
}

sub autotype($)
{
	my $string=shift;
	my $result="";
	foreach my $letter (split("", $string)) {
		$result.="sendkey $letter\n";
	}
	return $result;
}

my $lasttime;
my $n=0;

sub take_screenshot()
{
	my $path="/tmp/qemuscreenshot/";
	mkdir $path;
	my $now=time();
	if(!$lasttime || $lasttime!=$now) {$n=0};
	my $filename=$path.$now."-".$n++;
	#print STDERR $filename,"\n";
	qemusend "screendump $filename.ppm";
	$lasttime=$now;
}

sub qemualive()
{ 
	if(!$qemupid) {$qemupid=`pidof -s qemu-kvm`; chomp $qemupid;}
	return 0 unless $qemupid;
	kill 0, $qemupid;
}

sub waitidle(;$)
{
	my $timeout=shift||10;
	my $prev;
	for my $n (1..$timeout) {
		open(my $statf, "< /proc/$qemupid/stat");
		#open(my $statf, "< /proc/$qemupid/schedstat");
		my $stat=<$statf>;
		close($statf);
		my @a=split(" ", $stat);
		$stat=$a[13];
		#$stat=$a[1];
		if($prev) {
			my $diff=$stat-$prev;
			if($diff<30) { # idle for one sec
			#if($diff<2000000) { # idle for one sec
				last;
			}
		}
		$prev=$stat;
		sleep 1;
	}
}


use IO::Socket;
use threads;

# read all output from management console and forward it to STDOUT
sub readconloop
{
	$|=1;
	while(<$managementcon>) {
		print $_;
	}
}

sub open_management_console()
{
	$managementcon=IO::Socket::INET->new("localhost:15222") or die "error opening management console: $!";
	our $readconthread=threads->create(\&readconloop); # without this, qemu will block
	select $managementcon;
	$|=1; # autoflush
	$managementcon;
}

1;
