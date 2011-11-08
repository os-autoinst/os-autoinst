$|=1;

package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep gettimeofday);
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
my $lastname :shared = 0;
my $lastinststage :shared = "";
my $lastknowninststage :shared = "";
my $prestandstillwarning :shared = 0;
my $timeoutcounter :shared = 0;
my $backend;

our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw($realname $username $password $qemupid $scriptdir $testresults $serialdev $testedversion %cmd 
&diag &fileContent &qemusend_nolog &qemusend &sendkey &sendkeyw &sendautotype &sendpassword &mousemove_raw &mousemove &mouseclick &qemualive &result_dir 
&timeout_screenshot &waitidle &waitserial &waitgoodimage &waitimage &waitinststage &waitstillimage &init_backend &startvm &open_management_console &set_hash_rects &set_ocr_rect &get_ocr &script_run &script_sudo &script_sudo_logout &x11_start_program &clear_console &set_std_hash_rects);


our $debug=1;
our $idlethreshold=($ENV{IDLETHRESHOLD}||$ENV{IDLETHESHOLD}||18)*$clock_ticks/100; # % load max for being considered idle
our $timesidleneeded=2;
our $standstillthreshold=530;
our $realname="Bernhard M. Wiedemann";
our $username="bernhard";
our $password="nots3cr3t";
our $qemupid;
our $gocrbin="/usr/bin/gocr";
our $qemupidfilename="qemu.pid";
our $testresults="testresults";
our $serialdev="ttyS0";
our $serialfile="serial0";
$ENV{QEMUPORT}||=15222;
our $logfd;
share($ENV{SCREENSHOTINTERVAL}); # to adjust at runtime
our $scriptdir=$0; $scriptdir=~s{/[^/]+$}{};
our $testedversion=$ENV{ISO}||""; $testedversion=~s{.*/}{};$testedversion=~s/\.iso$//; $testedversion=~s{^([^.]+?)(?:-Media1?)?$}{$1};
if(!$ENV{DISTRI}) {
	if($testedversion=~m/^(debian|openSUSE|Fedora|SLE[SD]-1\d|oi|FreeBSD)-/) {$ENV{DISTRI}=lc($1)}
}
my @ocrrect; share(@ocrrect);
my @extrahashrects; share(@extrahashrects);
our @keyhistory;
our %cmd=qw(
next alt-n
xnext alt-n
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
otherrootpw alt-s
change alt-c
software s
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
	$cmd{"otherrootpw"}="alt-e";
	$cmd{"change"}="alt-n";
	$cmd{"software"}="w";
}
if($ENV{INSTLANG} eq "fr_FR") {
	$cmd{"next"}="alt-s";
}

if(!-x $gocrbin) {$gocrbin=undef}
if($ENV{SUSEMIRROR} && $ENV{SUSEMIRROR}=~s{^(\w+)://}{}) { # strip & check proto
	if($1 ne "http") {die "only http mirror URLs are currently supported but found '$1'."}
}


sub diag($)
{ $logfd && print $logfd "@_\n"; return unless $debug; print STDERR "@_\n";}

sub mydie($)
{ kill(15, $qemupid); unlink($qemupidfilename); diag "@_"; close $logfd; sleep 1 ; exit 1; }

sub fileContent($) {my($fn)=@_;
	open(my $fd, $fn) or return undef;
	local $/;
	my $result=<$fd>;
	close($fd);
	return $result;
}

sub qemusend_nolog($)
{
	if($backend) { $backend->send(@_); }
	else {warn "no backend"}
}
sub qemusend($)
{
	print $logfd "qemusend: $_[0]\n";
	&qemusend_nolog;
}

sub sendkey($)
{
	my $key=shift;
	qemusend "sendkey $key";
	my @t=gettimeofday();
	push(@keyhistory, [$t[0]*1000000+$t[1], $key]);
	sleep(0.25);
}

sub sendkeyw($) {sendkey(shift); waitidle();}

my %charmap=(","=>"comma", "."=>"dot", "/"=>"slash", "="=>"equal", "-"=>"minus", "*"=>"asterisk", 
   "["=>"bracket_left", "]"=>"bracket_right",
   "{"=>"shift-bracket_left", "}"=>"shift-bracket_right",
   "\\"=>"backslash", "|"=>"shift-backslash",
   ";"=>"semicolon", ":"=>"shift-semicolon",
   "'"=>"apostrophe", '"'=>"shift-apostrophe",
   "`"=>"grave_accent", "~"=>"shift-grave_accent",
   "<"=>"shift-comma", ">"=>"shift-dot",
   "+"=>"shift-equal", "_"=>"shift-minus", '?'=>"shift-slash",
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

sub sendpassword()
{
	sendautotype($password);
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

my $n=0;
my %md5file;
our %md5badlist=qw();
our %md5goodlist;
our %md5inststage;
do "goodimage.pm"; # fill above vars

sub set_hash_rects
{ 
	# sharing nested structure does not work, so turn arrayref into string
	@extrahashrects=map {join(",", @$_)} @_;
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

sub hashrect($$$)
{ my($ppm,$rect,$flags)=@_;
	my $ppm2=$ppm->copyrect(@$rect);
	my @result;
	return unless $ppm2;
	if($flags=~m/r/) {$ppm2->replacerect(0,137,13,15);} # mask out text
	if($flags=~m/c/) {push(@result, [Digest::MD5::md5_hex($ppm2->{data}),$rect,$flags])} # extra coloured version hash
	if($flags=~m/t/) {$ppm2->threshold(0x80);} # black/white => drop most background
	return (@result,[Digest::MD5::md5_hex($ppm2->{data}),$rect,$flags]);
}

my %goodsizes=(1440015=>1, 2359312=>1, 864015=>1);

# input: ref on PPM data
sub inststagedetect($)
{ my $dataref=shift;
	return if !$goodsizes{length($$dataref)}; # only work on images of 800x600 and 1024x768
	my $ppm=ppm->new($$dataref);
	return unless $ppm;
	my @md5=();
	# use several relevant non-text parts of the screen to look them up
	# WARNING: some break when background/theme changes (%md5inststage needs updating)
	# popup text detector
	push(@md5, hashrect($ppm, [230,230, 300,100], "t"));
	# smaller popup text detector
	push(@md5, hashrect($ppm, [300,240, 100,100], "t"));
	# smaller popup text detector on 1024x768
	push(@md5, hashrect($ppm, [500,320, 100,100], "t"));
	# use header text for GNOME-installer
	push(@md5, hashrect($ppm, [0,0, 250,30], "t"));
	# KDE/NET/DVD detect checks on left
	push(@md5, hashrect($ppm, [27,128,13,200], "rct"));
	
	foreach my $rect (@extrahashrects) {
		next unless $rect;
		my @r=split(",", $rect);
		push(@md5, hashrect($ppm, \@r, ""));
	}

	my $found=0;
	foreach my $md5e (@md5) {
		my($md5,$rect,$flags)=@$md5e;
		my $currentinststage=$md5inststage{$md5}||"";
		diag "stage=$currentinststage $md5 ".join(",",@$rect)." $flags";
		next if $found;
		if($currentinststage) { $lastknowninststage=$lastinststage=$currentinststage }
		if($currentinststage){$found=1}; # stop on first match - so must put most specific tests first
	}
	if($found) {return}
	$lastinststage="unknown";
}

sub result_dir()
{
	mkdir $testresults;
	mkdir "$testresults/$testedversion";
	"$testresults/$testedversion"
}

sub do_take_screenshot($)
{
	my($filename)=@_;
	qemusend "screendump $filename";
}

sub timeout_screenshot()
{
	my $n=++$timeoutcounter;
	my $dir=result_dir;
	my $n2=sprintf("%02i",$n);
	do_take_screenshot("$dir/timeout-$n2.ppm");
}

sub do_start_audiocapture($)
{
	my($filename)=@_;
	qemusend "wavcapture $filename 44100 16 1";
}

sub do_stop_audiocapture($)
{
	my $index = shift;
	qemusend "stopcapture $index";
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
			if($linkcount>$standstillthreshold) { 
				timeout_screenshot(); sleep 1;
				my $dir=result_dir;
				do_take_screenshot("$dir/standstill-1.ppm");sleep 1;
				mydie "standstill detected. test ended. see $lastname\n"; # above 120s of autoreboot
			}
		} else { # new
			$md5file{$md5}=[$lastname,1];
			my $ocr=get_ocr(\$data);
			if($ocr) { diag $ocr }
			inststagedetect(\$data);
		}
		if(($framecounter++ < 10) && length($data)<800*600*3) {unlink($lastname)}
	}
	my $t=[gettimeofday()];
	my $filename=$path.sprintf("%i.%06i.ppm", $t->[0], $t->[1]);
	#print STDERR $filename,"\n";
	do_take_screenshot($filename);
	$lastname=$filename;
}

sub checkrefimgs($$$)
{
	my ($screenimg,$refimg,$flags) = @_;
	my $screenppm=ppm->new(fileContent($screenimg));
	my $refppm=ppm->new(fileContent($refimg));
	if(!$screenppm || !$refppm) {
		return undef;
	}
	if($flags=~m/t/) {
		# black/white => drop most background
		$screenppm->threshold(0x80);
		$refppm->threshold(0x80);
	}
	return $screenppm->search($refppm);
}

sub decodewav($)
{
	my $wavfile = shift;
	my $dtmf = '';
	my $mm = "multimon -a DTMF -t wav $wavfile";
	open M, "$mm |" || return 1;
	while (<M>) {
		next unless /^DTMF: .$/;
		my ($a, $b) = split ':';
		$b =~ tr/0-9*#ABCD//csd; # Allow 0-9 * # A B C D
		$dtmf .= $b;
	}
	return $dtmf;
}

sub waitimage($;$) {
	my ($reflist,$timeout) = @_;
	$timeout = 60 unless defined $timeout;
	diag "Waiting for <$reflist.ppm> in screenshot. timeout=$timeout";
	my @refimgs=<$scriptdir/waitimgs/$reflist.ppm>;
	my ($lastmd5,$thismd5) = (0,0);
	for(my $i=0;$i<=$timeout;$i+=2) {
		# prevent reading while screendump is not finished
		my $mylastname = $lastname;
		sleep 2;
		$thismd5 = Digest::MD5::md5_hex(fileContent($mylastname));
		# image is equal with previous one
		unless($lastmd5 eq $thismd5) {
			foreach my $refimg (@refimgs) {
				if(defined checkrefimgs($mylastname,$refimg,'t')) {
					diag "Found $refimg in $mylastname";
					return 1;
				}
			}
		}
		$lastmd5 = $thismd5;
	}
	timeout_screenshot();
	diag "Waiting for images $reflist timed out!";
	return 0;
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

# wait for a message to appear on serial output
sub waitserial($;$)
{ my $regexp=shift;
  my $timeout=shift||90; # seconds
	for my $n (1..$timeout) {
		my $str=`tail $serialfile`;
		if($str=~m/$regexp/) {diag "found $regexp"; return 1;}
		if($prestandstillwarning) {return 2}
		sleep 1;
	}
	return 0;
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
	timeout_screenshot();
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
		if($prestandstillwarning) {
			timeout_screenshot();
			diag "WARNING: waited too long for stage=$stage";
			$prestandstillwarning=0;
			return 2;
		}
		sleep 1;
	}
	timeout_screenshot() if($timeout>1);
	diag "waitinststage stage=$stage timed out after $timeout";
	return 0;
}

sub waitstillimage(;$$)
{
	my $stilltime=shift||7;
	my $timeout=shift||30;
	my $starttime=time;
	my @recentmd5; # fifo
	diag "start waitstillimage($stilltime,$timeout)";
	while(time-$starttime<$timeout) {
		my $mylastname = $lastname;
		sleep 1;
		my $md5=Digest::MD5::md5(fileContent($mylastname));
		push(@recentmd5, $md5);
		if(@recentmd5>$stilltime) {
			my $e=shift @recentmd5;
			if($e eq $md5) {
				diag "detected same image for $stilltime seconds";
				return 1;
			}
		}
	}
	diag "waitstillimage timed out after $timeout";
	return 0;
}

sub init_backend($)
{
	my $name=shift;
	require "backend_$name.pm";
	$backend="backend_$name"->new();

	open($logfd, ">>", "currentautoinst-log.txt");
	# set unbuffered so that sendkey lines from main thread will be written
	my $oldfh=select($logfd); $|=1; select($oldfh);
}

sub startvm()
{
	$backend->start_vm();
}

sub open_management_console()
{
	$backend->open_management();
}

# start console application
sub script_run($;$)
{ my $name=shift; my $wait=shift;
	waitidle;
	sendautotype("$name\n");
	waitidle $wait;
	sleep 3;
}

my $sudotimeout=300; # 5 mins
my $lastsudotime;
my $sudos=0;
sub script_sudo($;$)
{ my ($prog,$wait)=@_;
	sendautotype("sudo $prog\n");
	if(!$lastsudotime||$lastsudotime+$sudotimeout<time()) {$sudos=0}
	if($password && !$sudos++) {
		waitidle;
		sendpassword;
		sendkey "ret";
	}
	$lastsudotime=time();
	waitidle $wait;
}
# reset so that next sudo will send password
sub script_sudo_logout()
{ $sudos=0 }


sub x11_start_program($)
{ my $program=shift;
	sendkey "alt-f2"; sleep 3;
	sendautotype $program; sleep 1;
	sendkey "ret";
	waitidle;
	sleep 1;
}

sub clear_console()
{
	sendkey "ctrl-c";
	sleep 1;
	sendkey "ctrl-c";
	sendautotype "reset\n";
	sleep 2;
}

sub set_std_hash_rects()
{
  set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	[0,750,90,10 ], # bottom line (KDE/GNOME bar) in 1024
	);
}

1;
