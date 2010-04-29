$|=1;

package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep);
use Digest::MD5;
use Exporter;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw($qemubin $qemupid %cmd 
&qemusend &sendkey &sendautotype &autotype &take_screenshot &qemualive &waitidle &waitgoodimage &open_management_console);


our $debug=1;
our $qemubin="/usr/bin/kvm";
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
instdetails alt-d
rebootnow alt-n
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

sub diag($)
{ return unless $debug; print STDERR "@_\n";}

sub mydie($)
{ kill(15, $qemupid); print STDERR @_; sleep 1 ; exit 1; }

sub fileContent($) {my($fn)=@_;
	open(my $fd, $fn) or return undef;
	local $/;
	my $result=<$fd>;
	close($fd);
	return $result;
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
my $lastname;
my $n=0;
my %md5file;
my %md5badlist=qw();
our %md5goodlist;
eval(fileContent("goodimage.pm"));
use threads;
use threads::shared;
my $goodimageseen :shared = 0;

sub take_screenshot()
{
	my $path="qemuscreenshot/";
	mkdir $path;
	if($lastname && -e $lastname) { # processing previous image, because saving takes time
		# hardlinking identical files saves space
		my $md5=Digest::MD5::md5_hex(fileContent($lastname));
		if($md5badlist{$md5}) {diag "error condition detected. test failed. see $lastname"; sleep 1; mydie "bad image seen"}
		diag("md5=$md5");
		if($md5goodlist{$md5}) {$goodimageseen=1; diag "good image"}
		if($md5file{$md5}) {
			unlink($lastname); # warning: will break if FS does not support hardlinking
			link($md5file{$md5}->[0], $lastname);
			my $linkcount=$md5file{$md5}->[1]++;
			#my $linkcount=(stat($lastname))[3]; # relies on FS
			if($linkcount>530) {mydie "standstill detected. test ended. see $lastname\n"} # above 120s of autoreboot
		} else {
			$md5file{$md5}=[$lastname,1];
		}
	}
	my $now=time();
	if(!$lasttime || $lasttime!=$now) {$n=0};
	my $filename=$path.$now."-".$n++.".ppm";
	#print STDERR $filename,"\n";
	qemusend "screendump $filename";
	$lastname=$filename;
	$lasttime=$now;
}

sub qemualive()
{ 
#	if(!$qemupid) {$qemupid=`pidof -s $qemubin`; chomp $qemupid;}
	return 0 unless $qemupid;
	kill 0, $qemupid;
}

sub waitidle(;$)
{
	my $timeout=shift||10;
	my $prev;
	diag "waitidle(timeout=$timeout)";
	for my $n (1..$timeout) {
		my $stat=fileContent("/proc/$qemupid/stat");
			#"/proc/$qemupid/schedstat");
		my @a=split(" ", $stat);
		$stat=$a[13];
		next unless $stat;
		#$stat=$a[1];
		if($prev) {
			my $diff=$stat-$prev;
			if($diff<10) { # idle for one sec
			#if($diff<2000000) # idle for one sec
				diag "idle detected";
				return 1;
			}
		}
		$prev=$stat;
		sleep 1;
	}
	diag "waitidle timed out";
	return 0;
}

sub waitgoodimage($)
{
	my $timeout=shift||10;
	$goodimageseen=0;
	diag "waiting for good image(timeout=$timeout)";
	for my $n (1..$timeout) {
		if($goodimageseen) {diag "seen good image... continuing execution"; return 1;}
		sleep 1;
	}
	return 0;
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
	$managementcon=IO::Socket::INET->new("localhost:15222") or mydie "error opening management console: $!";
	our $readconthread=threads->create(\&readconloop); # without this, qemu will block
	select $managementcon;
	$|=1; # autoflush
	$managementcon;
}

1;
