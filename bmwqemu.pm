$|=1;

package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep);
use Digest::MD5;
use IO::Socket;
use Exporter;
use ppm;
use ocr;
use threads;
use threads::shared;
use POSIX; 
our $clock_ticks = POSIX::sysconf( &POSIX::_SC_CLK_TCK );
my $goodimageseen :shared = 0;
my $endreadingcon :shared = 0;
my $lastname;
my $lastinststage :shared = "";
my $lastknowninststage :shared = "";
my $prestandstillwarning :shared = 0;

our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw($username $password $qemubin $qemupid $scriptdir $testedversion %cmd 
&diag &fileContent &qemusend &sendkey &sendautotype &autotype &mousemove_raw &mousemove &mouseclick &qemualive &waitidle &waitgoodimage &waitinststage &open_management_console &close_management_console &set_ocr_rect &get_ocr &script_run &script_sudo &script_sudo_logout);


our $debug=1;
our $idlethreshold=($ENV{IDLETHESHOLD}||18)*$clock_ticks/100; # % load max for being considered idle
our $timesidleneeded=2;
our $standstillthreshold=530;
our $username="bernhard";
our $password="nots3cr3t";
our $qemubin="/usr/bin/kvm";
our $qemupid;
our $gocrbin="/usr/bin/gocr";
our $qemupidfilename="qemu.pid";
$ENV{QEMUPORT}||=15222;
our $managementcon;
share($ENV{SCREENSHOTINTERVAL}); # to adjust at runtime
our $scriptdir=$0; $scriptdir=~s{/[^/]+$}{};
our $testedversion=$ENV{SUSEISO}||""; $testedversion=~s{.*/}{};$testedversion=~s{^([^.]+?)(?:-Media)?\.iso$}{$1};
my @ocrrect; share(@ocrrect);
my @extrahashrects; share(@extrahashrects);
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
raid5 alt-5
raid6 alt-6
raid10 alt-i
mountpoint alt-m
filesystem alt-s
acceptlicense alt-a
instdetails alt-d
rebootnow alt-n
);


$ENV{INSTLANG}||="en_US";
if($ENV{INSTLANG} eq "de_DE") {
	$cmd{"next"}="alt-w";
	$cmd{"createpartsetup"}="alt-e";
	$cmd{"custompart"}="alt-b";
	$cmd{"addpart"}="alt-h";
	$cmd{"finish"}="alt-b";
	$cmd{"accept"}="alt-r";
	$cmd{"donotformat"}="alt-n";
	$cmd{"add"}="alt-h";
#	$cmd{"raid6"}="alt-d"; 11.2 only
	$cmd{"raid10"}="alt-r";
	$cmd{"mountpoint"}="alt-e";
	$cmd{"rebootnow"}="alt-j";
}

if(!-x $gocrbin) {$gocrbin=undef}
if(!-x $qemubin) {$qemubin=~s/kvm/qemu-kvm/}
if(!-x $qemubin) {$qemubin=~s/-kvm//}
if(!-x $qemubin) {die "no Qemu/KVM found"}
if($ENV{SUSEMIRROR} && $ENV{SUSEMIRROR}=~s{^(\w+)://}{}) { # strip & check proto
	if($1 ne "http") {die "only http mirror URLs are currently supported but found '$1'."}
}


sub diag($)
{ print LOG "@_\n"; return unless $debug; print STDERR "@_\n";}

sub mydie($)
{ kill(15, $qemupid); unlink($qemupidfilename); diag "@_"; close LOG; sleep 1 ; exit 1; }

sub fileContent($) {my($fn)=@_;
	open(my $fd, $fn) or return undef;
	local $/;
	my $result=<$fd>;
	close($fd);
	return $result;
}

sub qemusend($)
{
	print LOG "qemusend: $_[0]\n";
	print $managementcon shift(@_)."\n";
}

sub sendkey($)
{
	my $key=shift;
	qemusend "sendkey $key";
	sleep(0.25);
}

my %charmap=(","=>"comma", "."=>"dot", "/"=>"slash", "="=>"equal", "-"=>"minus", "*"=>"asterisk", 
   "+"=>"shift-equal", "_"=>"shift-minus", '?'=>"shift-slash", ">"=>"shift-<",
   "\t"=>"tab", "\n"=>"ret", " "=>"spc", "\b"=>"backspace", "\e"=>"esc");
for my $c ("A".."Z") {$charmap{$c}="shift-\L$c"}
{
	my $n=0;
	for my $c (')','!','@','#','$','%','^','&','*','(') {$charmap{$c}="shift-".($n++)}
}


sub sendautotype($)
{
	my $string=shift;
	diag "sendautotype '$string'";
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

sub mousemove_raw($$)
{
	qemusend "mouse_move @_";
	sleep 0.5;
}

# send mouse move via emulated touch screen
# in: x,y coords in pixels
sub mousemove($$)
{ my(@coord)=@_;
	my @size=(800,600);
	my $maxtouch=0x7fff;
	# transform to touchscreen coords (0..$maxtouch)
	for my $i (0..1) {$coord[$i]=int($coord[$i]*$maxtouch/$size[$i])}
	mousemove_raw($coord[0], $coord[1]);
}

# send mouse click
# in: button (default:L=1; R=2; M=4), duration of click (default: 0.15 sec)
# still broken for some reason (Qemu?)
sub mouseclick(;$$)
{
	my $button=shift||1;
	my $time=shift||0.15;
	qemusend "mouse_button $button";
	sleep $time;
	qemusend "mouse_button 0";
}

my $lasttime;
my $n=0;
my %md5file;
our %md5badlist=qw();
our %md5goodlist;
our %md5inststage;
do "goodimage.pm"; # fill above vars
my $readconthread;
my $conmuxthread;

sub set_hash_rects()
{ 
	@extrahashrects=@_;
}

sub set_ocr_rect
{
	@ocrrect=@_;
}
# input: ref on PPM data
sub get_ocr($)
{ my $dataref=shift;
	my $ocr=ocr::get_ocr($dataref, "-m 2 -s 6", \@ocrrect);
	if(!$ocr) {return ""}
	$ocr=~s/^[_ \t\n]+//;
	$ocr=~s/\n/ --- /g;
	# correct common mis-readings:
	$ocr=~s/nstaII/nstall/g;
	$ocr=~s/l(install|Remaining)/($1/g;
	return " ocr='$ocr'";
}

# input: ref on PPM data
sub inststagedetect($)
{ my $dataref=shift;
	return if length($$dataref)!=1440015; # only work on images of 800x600
	my $ppm=ppm->new($$dataref);
	my @md5=();
	# use several relevant non-text parts of the screen to look them up up
	# WARNING: some break when background/theme changes (%md5inststage needs updating)
	my $ppm2;
	# popup text detector
	$ppm2=$ppm->copyrect(230,230, 300,100);
	$ppm2->threshold(0x80); # black/white => drop most background
	push(@md5, Digest::MD5::md5_hex($ppm2->{data}));
	# use header text for GNOME
	$ppm2=$ppm->copyrect(0,0, 250,30);
	$ppm2->threshold(0x80); # black/white => drop most background
	push(@md5, Digest::MD5::md5_hex($ppm2->{data}));
	# KDE/NET/DVD detect checks on left
	$ppm2=$ppm->copyrect(27,128,13,200);
	$ppm2->replacerect(0,137,13,15); # mask out text
	push(@md5, Digest::MD5::md5_hex($ppm2->{data}));
	$ppm2->threshold(0x80); # black/white => drop most background
	push(@md5, Digest::MD5::md5_hex($ppm2->{data}));
	foreach my $rect (@extrahashrects) {
		$ppm2=$ppm->copyrect(@$rect);
		push(@md5, Digest::MD5::md5_hex($ppm2->{data}));
	}

	foreach my $md5 (@md5) {
		my $currentinststage=$md5inststage{$md5}||"";
		if($currentinststage) { $lastknowninststage=$lastinststage=$currentinststage }
		diag "stage=$currentinststage $md5";
		return if($currentinststage); # stop on first match - so must put most specific tests first
	}
	$lastinststage="unknown";
}

my $framecounter=0;
sub take_screenshot()
{
	my $path="qemuscreenshot/";
	mkdir $path;
	if($lastname && -e $lastname) { # processing previous image, because saving takes time
		# hardlinking identical files saves space
		my $data=fileContent($lastname);
		my $md5=Digest::MD5::md5_hex($data);
		if($md5badlist{$md5}) {diag "error condition detected. test failed. see $lastname"; sleep 1; mydie "bad image seen"}
		my($statuser,$statsystem)=proc_stat_cpu($qemupid);
		for($statuser,$statsystem) {$_/=$clock_ticks}
		diag("md5=$md5 laststage=$lastinststage statuser=$statuser statsystem=$statsystem");
		if($md5goodlist{$md5}) {$goodimageseen=1; diag "good image"}
		# ignore bottom 15 lines (blinking cursor, animated mouse-pointer)
		if(length($data)==1440015) {$md5=Digest::MD5::md5(substr($data,15,800*3*(600-15)))}
		if($md5file{$md5}) { # old
			unlink($lastname); # warning: will break if FS does not support hardlinking
			link($md5file{$md5}->[0], $lastname);
			my $linkcount=$md5file{$md5}->[1]++;
			#my $linkcount=(stat($lastname))[3]; # relies on FS
			$prestandstillwarning=($linkcount>$standstillthreshold/2);
			if($linkcount>$standstillthreshold) {mydie "standstill detected. test ended. see $lastname\n"} # above 120s of autoreboot
		} else { # new
			$md5file{$md5}=[$lastname,1];
			my $ocr=get_ocr(\$data);
			if($ocr) { diag $ocr }
			inststagedetect(\$data);
		}
		if(($framecounter++ < 10) && length($data)<800*600*3) {unlink($lastname)}
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
	if(!$qemupid) {($qemupid=fileContent($qemupidfilename)) && chomp $qemupid;}
	return 0 unless $qemupid;
	kill 0, $qemupid;
}

# input: PID (process identifier)
# output: user/system clock_ticks used
sub proc_stat_cpu($)
{ my $pid=shift;
	my $stat=fileContent("/proc/$pid/stat");
	my @a=split(" ", $stat);
	return @a[13,14];
}

sub waitidle(;$)
{
	my $timeout=shift||19;
	my $prev;
	diag "waitidle(timeout=$timeout)";
	my $timesidle=0;
	for my $n (1..$timeout) {
		my($stat,$systemstat)=proc_stat_cpu($qemupid);
		next unless $stat;
		$stat+=$systemstat;
		if($prev) {
			my $diff=$stat-$prev;
			if($diff<$idlethreshold) {
				if(++$timesidle>$timesidleneeded) { # idle for $x sec
				#if($diff<2000000) # idle for one sec
					diag "idle detected";
					return 1;
				}
			} else {$timesidle=0}
		}
		$prev=$stat;
		sleep 1;
	}
	diag "waitidle timed out";
	return 0;
}

sub waitgoodimage(;$)
{
	my $timeout=shift||10;
	$goodimageseen=0;
	diag "waiting for good image(timeout=$timeout)";
	for my $n (1..$timeout) {
		if($goodimageseen) {diag "seen good image... continuing execution"; return 1;}
		sleep 1;
	}
	diag "waitgoodimage timed out";
	return 0;
}

sub waitinststage($;$$)
{
	my $stage=shift;
	my $timeout=shift||30;
	my $extradelay=shift||3;
	diag "start waiting $timeout seconds for stage=$stage";
	if($prestandstillwarning) { sleep 3 }
	for my $n (1..$timeout) {
		if($lastinststage=~m/$stage/) {diag "detected stage=$stage ... continuing execution"; sleep $extradelay; return 1;}
		if($prestandstillwarning) { diag "WARNING: waited too long for stage=$stage"; return 2; }
		sleep 1;
	}
	diag "waitinststage stage=$stage timed out after $timeout";
	return 0;
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
	$|=1;
	while(<$managementcon>) {
		print $_;
		last if($endreadingcon);
	}
	diag "exiting management console read loop";
	unlink $qemupidfilename;
	alarm 3; # kill all extra threads soon
}

sub open_management_console()
{
	open(LOG, ">", "currentautoinst-log.txt");
	# set unbuffered so that sendkey lines from main thread will be written
	my $oldfh=select(LOG); $|=1; select($oldfh);

	$managementcon=IO::Socket::INET->new("localhost:$ENV{QEMUPORT}") or mydie "error opening management console: $!";
	$endreadingcon=0;
	select($managementcon); $|=1; select($oldfh); # autoflush
	$conmuxthread=threads->create(\&conmuxloop); # allow external qemu input
	$conmuxthread->detach();
	$readconthread=threads->create(\&readconloop); # without this, qemu will block
	$readconthread->detach();
	$managementcon;
}

sub close_management_console()
{
	$endreadingcon=1;
	qemusend "";
	close $managementcon;
}

# start console application
sub script_run($;$)
{ my $name=shift; my $wait=shift;
	waitidle;
	sendautotype("$name\n");
	waitidle $wait;
	sleep 3;
}

my $sudos=0;
sub script_sudo($;$)
{ my ($prog,$wait)=@_;
	sendautotype("sudo $prog\n");
	if(!$sudos++) {
		sleep 1;
		sendautotype "$password\n";
	}
	waitidle $wait;
}
# reset so that next sudo will send password
sub script_sudo_logout()
{ $sudos=0 }


1;
