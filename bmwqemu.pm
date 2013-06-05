$|=1;

package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep gettimeofday);
use Digest::MD5;
use IO::Socket;
use File::Basename;
eval {require Algorithm::Line::Bresenham;};
use Exporter;
use ocr;
use cv;
use needle;
use threads;
use threads::shared;
use Thread::Queue;
use POSIX; 
use Term::ANSIColor;
use Data::Dump "dump";
use Carp;
use JSON;

our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw($realname $username $password $scriptdir $testresults $serialdev $testedversion %cmd
&diag &modstart &fileContent &qemusend_nolog &qemusend &backend_send_nolog &backend_send &sendkey 
&sendkeyw &sendautotype &sendpassword &mouse_move &mouse_set &mouse_click &mouse_hide &clickimage &result_dir
&timeout_screenshot &waitidle &waitserial &waitimage &waitforneedle &waitstillimage &waitcolor 
&checkneedle &goandclick &set_current_test
&init_backend &start_vm &stop_vm &set_ocr_rect &get_ocr save_results;
&script_run &script_sudo &script_sudo_logout &x11_start_program &ensure_installed &clear_console 
&getcurrentscreenshot &power &mydie &checkEnv &waitinststage &makesnapshot &loadsnapshot
$stop_waitforneedle &interactive_mode &needle_template &waiting_for_new_needle &interactive_lock
);


# shared vars

my $goodimageseen :shared = 0;
my $screenshotQueue = Thread::Queue->new();
my $prestandstillwarning :shared = 0;
my $timeoutcounter :shared = 0;
share($ENV{SCREENSHOTINTERVAL}); # to adjust at runtime
my @ocrrect; share(@ocrrect);
my @extrahashrects; share(@extrahashrects);

our $interactive_lock : shared; # lock for cond variable. protects waiting_for_new_needle and needle_template
our $stop_waitforneedle : shared;
our $interactive_mode : shared;
our $needle_template : shared; # set if waitforneedle failed
our $waiting_for_new_needle : shared;

# shared vars end


# global vars

our $current_test;
our $testmodules = [];

our $logfd;

our $clock_ticks = POSIX::sysconf( &POSIX::_SC_CLK_TCK );

our $debug=1;
our $idlethreshold=($ENV{IDLETHRESHOLD}||$ENV{IDLETHESHOLD}||18)*$clock_ticks/100; # % load max for being considered idle
our $timesidleneeded=2;
our $standstillthreshold=930;

our $realname="Bernhard M. Wiedemann";
our $username="bernhard";
our $password="nots3cr3t";

our $testresults="testresults";
our $serialdev="ttyS0"; #FIXME: also backend
our $serialfile="serial0";
our $gocrbin="/usr/bin/gocr";

our $scriptdir=$0; $scriptdir=~s{/[^/]+$}{};
our $testedversion=$ENV{NAME};
unless ($testedversion) {
	$testedversion=$ENV{ISO}||"";
	$testedversion=~s{.*/}{};
	$testedversion=~s/\.iso$//;
	$testedversion=~s{-Media1?$}{};
}
if(!$ENV{DISTRI}) {
	if($testedversion=~m/^(debian|openSUSE|Fedora|SLE[SD]-1\d|oi|FreeBSD|archlinux)-/) {$ENV{DISTRI}=lc($1)}
}
$ENV{CASEDIR}||="$scriptdir/distri/$ENV{DISTRI}" if $ENV{DISTRI};
foreach my $part (split("-", $testedversion)) {$ENV{uc($part)}=1}
$ENV{LIVECD}=$ENV{LIVE};

## env vars
$ENV{UEFI_BIOS_DIR}||='/usr/share/qemu-ovmf/bios-ms';
$ENV{QEMUPORT}||=15222;
$ENV{INSTLANG}||="en_US";
$ENV{CASEDIR}||="$scriptdir/distri/$ENV{DISTRI}" if $ENV{DISTRI};
if(defined($ENV{DISTRI}) && $ENV{DISTRI} eq 'archlinux') {$ENV{HDDMODEL}="ide";}

if ($ENV{LAPTOP}) {
    $ENV{LAPTOP} = 'dell_e6330' if $ENV{LAPTOP} eq '1';
    die "no dmi data for '$ENV{LAPTOP}'\n" unless -d "$scriptdir/dmidata/$ENV{LAPTOP}";
    $ENV{LAPTOP} = "$scriptdir/dmidata/$ENV{LAPTOP}";
}

## env vars end

## keyboard cmd vars
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
	noautologin alt-a
	change alt-c
	software s
	bootloader b
);

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
if($ENV{INSTLANG} eq "es_ES") {
	$cmd{"next"}="alt-i";
}
if($ENV{INSTLANG} eq "fr_FR") {
	$cmd{"next"}="alt-s";
}
## keyboard cmd vars end

## some var checks
if(!-x $gocrbin) {$gocrbin=undef}
if($ENV{SUSEMIRROR} && $ENV{SUSEMIRROR}=~s{^(\w+)://}{}) { # strip & check proto
	if($1 ne "http") {die "only http mirror URLs are currently supported but found '$1'."}
}
## some var checks end

# global vars end


# local vars

our $backend : shared; #FIXME: make local after adding frontend-api to bmwqemu

my $framecounter = 0; # screenshot counter

## sudo stuff
my $sudos=0;
## sudo stuff end

## charmap (like L => shift+l)
my %charmap=(
	","=>"comma", "."=>"dot", "/"=>"slash", "="=>"equal", "-"=>"minus", "*"=>"asterisk",
	"["=>"bracket_left", "]"=>"bracket_right",
	"{"=>"shift-bracket_left", "}"=>"shift-bracket_right",
	"\\"=>"backslash", "|"=>"shift-backslash",
	";"=>"semicolon", ":"=>"shift-semicolon",
	"'"=>"apostrophe", '"'=>"shift-apostrophe",
	"`"=>"grave_accent", "~"=>"shift-grave_accent",
	"<"=>"shift-comma", ">"=>"shift-dot",
	"+"=>"shift-equal", "_"=>"shift-minus", '?'=>"shift-slash",
	"\t"=>"tab", "\n"=>"ret", " "=>"spc", "\b"=>"backspace", "\e"=>"esc"
);
for my $c ("A".."Z") {$charmap{$c}="shift-\L$c"}
{
	my $n=0;
	for my $c (')','!','@','#','$','%','^','&','*','(') {$charmap{$c}="shift-".($n++)}
}
## charmap end

# local vars end


# global/shared var set functions

sub set_ocr_rect {@ocrrect=@_;}

# global/shared var set functions end



# util and helper functions

sub diag($) {
	$logfd && print $logfd "@_\n";
	return unless $debug;
	print STDERR "@_\n";
}

sub fctlog {
	my $fname = shift;
	my @fparams = @_;
	$logfd && print $logfd '<<< '.$fname.'('.join(', ', @fparams).")\n";
	return unless $debug;
	print STDERR colored('<<< '.$fname.'('.join(', ', @fparams).')', 'blue')."\n";
}

sub fctres {
	my $fname = shift;
	my @fparams = @_;
	$logfd && print $logfd ">>> $fname: @fparams\n";
	return unless $debug;
	print STDERR colored(">>> $fname: @fparams", 'green')."\n";
}

sub fctinfo {
	my $fname = shift;
	my @fparams = @_;
	$logfd && print $logfd "::: $fname: @fparams\n";
	return unless $debug;
	print STDERR colored("::: $fname: @fparams", 'yellow')."\n";
}

sub modstart {
	my @text = @_;
	$logfd && print $logfd "||| @text\n";
	return unless $debug;
	print STDERR colored("||| @text", 'bold')."\n";
}

sub checkEnv($$) {
	my $var = shift;
	my $val = shift;
	return 1 if (defined $ENV{$var} && $ENV{$var} eq $val);
        return 0;
}

sub fileContent($) {
	my($fn)=@_;
	open(my $fd, $fn) or return undef;
	local $/;
	my $result=<$fd>;
	close($fd);
	return $result;
}

sub result_dir() {
	unless (-e "$testresults/$testedversion") {
		mkdir $testresults;
		mkdir "$testresults/$testedversion" or die "mkdir $testresults/$testedversion: $!\n";
	}
	return "$testresults/$testedversion"
}

our $lastscreenshot;
our $lastscreenshotName;
our $lastscreenshotCount;
sub getcurrentscreenshot() {
        my $filename;
	# using a queue to get the latest is most likely the least efficient solution,
        # but we need to check the current screenshot not to miss things
	while ($screenshotQueue->pending()) {
		# unfortunately passing objects between threads is almost impossible
		$filename = $screenshotQueue->dequeue();
	}

	# if this is the first screenshot, be sure that we have something to return
	if (!$lastscreenshot && !$filename) {
	        # blocking call
		$filename = $screenshotQueue->dequeue();
	}

	if ($filename) {
		$lastscreenshot = tinycv::read($filename);
		$lastscreenshotName = $filename;
		$lastscreenshotCount = 0;
	}

	return $lastscreenshot;
}

sub check_color($$) {
	my $color = shift;
	my $range = shift;
	my $n=0;
	foreach my $r (@$range) {
		my $c=$color->[$n++];
		next unless defined $r;
		return 0 unless $r->[0]<=$c && $c<=$r->[1];
	}
	return 1;
}
# TODO: move to a separate tests file:
sub test_check_color()
{
	my $c=[0.1, 0.6, 0.2];
	die 1 unless check_color($c, []); # all zero ranges match
	die 2 unless check_color($c, [undef, [0.2,0.7], undef]); # just match green
	die 3 unless check_color($c, [[0,0.4], [0.4,0.7], [0,0.4]]); # all three must match
	die 4 if check_color($c, [[0.3,0.4], [0.2,0.7], [0,0.4]]); # red too low
	die 5 if check_color($c, [undef, [0.7,0.9], [0,0.4]]); # green too low
	die 6 if check_color($c, [undef, [0.4,0.9], [0,0.1]]); # blue too high
}


# util and helper functions end


# backend management

sub init_backend($) {
	my $name=shift;
	require "backend/$name.pm";
	$backend="backend::$name"->new();
	open($logfd, ">>", "autoinst-log.txt");
	# set unbuffered so that sendkey lines from main thread will be written
	my $oldfh=select($logfd); $|=1; select($oldfh);
}

sub start_vm() {
	return unless $backend;
	$backend->start_vm();
}

sub stop_vm()
{
	return unless $backend;
	$backend->stop_vm();
        close $logfd;
}

sub freeze_vm()
{
	backend_send("stop");
}

sub cont_vm()
{
	backend_send("cont");
}

sub mydie {
	fctlog('mydie', "@_");
#	$backend->stop_vm();
	croak "mydie";
}

sub backend_send_nolog($) {
	# should not be used if possible
	if($backend) {
		$backend->send(@_);
	}
	else {
		warn "no backend"
	}
}

sub backend_send($) {
	# should not be used if possible
	fctlog('backend_send', join(',', @_));
	&backend_send_nolog;
}

sub qemusend_nolog($) {&backend_send_nolog;} # deprecated
sub qemusend($) {&backend_send;} # deprecated

# backend management end


# runtime keyboard/mouse io functions

## keyboard
=head2 sendkey

sendkey($qemu_key_name)

=cut
sub sendkey($) {
	my $key=shift;
	fctlog('sendkey', "key=$key");
	$backend->sendkey($key);
	my @t=gettimeofday();
	push(@keyhistory, [$t[0]*1000000+$t[1], $key]);
	sleep(0.1);
}

=head2 sendkeyw

sendkeyw($qemu_key_name)

L</sendkey> then L</waitidle>

=cut
sub sendkeyw($) {
	sendkey(shift);
	waitidle();
}

=head2 sendautotype

sendautotype($string, [$keyboardbuffersize])

send a string of characters, mapping them to appropriate key names as necessary

=cut

sub sendautotype($;$) {
	my $string=shift;
	my $maxinterval=shift||25;
	my $typedchars=0;
	fctlog('sendautotype', "string='$string'");
	my @letters = split("", $string);
	while (@letters) {
		my $letter = shift @letters;
		if($charmap{$letter}) { $letter=$charmap{$letter} }
		sendkey $letter;
		if ($typedchars++ >= $maxinterval ) {
			waitstillimage(1.6);
			$typedchars=0;
		}
	}
	waitstillimage(1.6) if ($typedchars > 0);
}

sub sendpassword() {
	sendautotype($password);
}
## keyboard end


## mouse
sub mouse_move_nosleep($$) {
	my ($mdx, $mdy) = @_;
	fctlog('mouse_move', "delta_x=$mdx", "delta_y=$mdy");
	$backend->mouse_move($mdx, $mdy);
}

sub mouse_set_nosleep($$) {
	my ($mx, $my) = @_;
	fctlog('mouse_set', "x=$mx", "y=$my");
	$backend->mouse_set($mx, $my);
}

sub mouse_move($$) {
	# relative
	# FIXME: backend value abstraction
	my ($mdx, $mdy) = @_;
	mouse_move_nosleep($mdx, $mdy);
	sleep 0.5;
}

sub mouse_set($$) {
	# absolute
	my ($mx, $my) = @_;
	mouse_set_nosleep($mx, $my);
	sleep 0.5;
}

sub mouse_click(;$$) {
	my $button = shift || 'left';
	my $time = shift || 0.15;
	fctlog('mouse_click', "button=$button", "cursor_down=$time");
	$backend->mouse_button($button, 1);
	sleep $time;
	$backend->mouse_button($button, 0);
}

sub mouse_hide(;$) {
	my $border_offset = shift || 0;
	fctlog('mouse_hide', "border_offset=$border_offset");
	$backend->mouse_hide($border_offset);
}
## mouse end


## helpers
sub x11_start_program($;$) {
	my $program=shift;
	my $options=shift||{};
	sendkey "alt-f2"; sleep 4;
	sendautotype $program; sleep 1;
	if($options->{terminal}) {sendkey "alt-t";sleep 3;}
	sendkey "ret";
	waitidle();
	sleep 1;
}

=head2 script_run

script_run($program, [$wait_seconds])

Run $program (by assuming the console prompt and typing it).
Wait for idle before  and after.

=cut
sub script_run($;$) {
	# start console application
	my $name=shift;
	my $wait=shift || 9;
	waitidle();
	sendautotype("$name\n");
	waitidle($wait);
	sleep 3;
}

=head2 script_sudo

script_sudo($program, [$wait_seconds])

Run $program. Handle the sudo timeout and send password when appropriate.

$wait_seconds
=cut
sub script_sudo($;$) {
        my $prog = shift;
	sendautotype("sudo $prog\n");
	if (checkneedle("sudo-passwordprompt", 3)) {
		sendpassword;
		sendkey "ret";
	}
}

=head2 script_sudo_logout

Reset so that the next sudo will send password

=cut
sub script_sudo_logout() {
	$sudos=0
}

sub ensure_installed {
	my @pkglist=@_;
	#pkcon refresh # once
	#pkcon install @pkglist
	if($ENV{OPENSUSE}) {
		x11_start_program("xdg-su -c 'zypper -n in @pkglist'"); # SUSE-specific
	} elsif($ENV{DEBIAN}) {
		x11_start_program("su -c 'aptitude -y install @pkglist'", {terminal=>1});
	} elsif($ENV{FEDORA}) {
		x11_start_program("su -c 'yum -y install @pkglist'", {terminal=>1});
	} else {
		mydie "TODO: implement package install for your distri $ENV{DISTRI}";
	}
	if($password) { sendpassword; sendkeyw "ret"; }
	waitstillimage(7,90); # wait for install
}

sub clear_console() {
	sendkey "ctrl-c";
	sleep 1;
	sendkey "ctrl-c";
	sendautotype "reset\n";
	sleep 2;
}
## helpers end

#TODO: convert to new bmwqemu
#sub clickimage($;$$$$) {
#	my ($reflist,$button,$bstatus,$flags,$timeout) = @_;
#	$flags||="h";
#	$timeout||=60;
#	my $waitres = waitimage("click/$reflist",$timeout);
#	if(defined $waitres) {
#		diag "Got absolute refimg coordinates: $waitres->[0]x$waitres->[1]";
#		$waitres->[2]=~m/-(-?\d+)-(-?\d+)\.ppm$/;
#		my @relcoor = ($1,$2);
#		#my @relcoor = ($waitres[2],$waitres[2]);
#		#$relcoor[0]=~s/^.*\d-(-?\d+)--?\d+.ppm/$1/;
#		#$relcoor[1]=~s/^.*\d--?\d+-(-?\d+).ppm/$1/;
#		diag "Got relative action coordinates: $relcoor[0]x$relcoor[1]";
#		my @abscoor;
#		for my $i (0..1) { $abscoor[$i] = $waitres->[$i] + $relcoor[$i]; }
#		diag "Got absolute action coordinates: $abscoor[0]x$abscoor[1]";
#		# slide
#		if($flags=~m/s/) {
#			diag "Sliding mouse to $abscoor[0]x$abscoor[1]";
#			for my $pos (Algorithm::Line::Bresenham::line($mouse_position[1],$mouse_position[0] => $abscoor[1],$abscoor[0])) {
#				mousemove($pos->[1],$pos->[0],0.005);
#			}
#		}
#		else {
#			diag "Set mouse position: $abscoor[0]x$abscoor[1]";
#			mousemove($abscoor[0],$abscoor[1]);
#		}
#		sleep(0.25);
#		mousebuttonaction($button, $bstatus);
#		sleep(0.25);
#		# cursor in ninja mode
#		if($flags=~m/h/) {
#			mousemove(800,600);
#		}
#		return @abscoor;
#	}
#	else {
#		diag "Skipping click action!";
#		return undef;
#	}
#}


sub power($) {
	# params: (on), off, acpi, reset
	my $action = shift;
	fctlog('power', "action=$action");
	$backend->power($action);
}


# runtime keyboard/mouse io functions end


# runtime information gathering functions

sub do_take_screenshot() {
        my $ret = $backend->screendump();
	return $ret->scale(1024, 768);
}

sub timeout_screenshot() {
	my $n = ++$timeoutcounter;
	$current_test->take_screenshot(sprintf("timeout-%02i", $n));
}

sub take_screenshot(;$) {
	my $flags = shift || '';
	my $path="qemuscreenshot/";
	mkdir $path;

	my $t=[gettimeofday()];
	my $img = do_take_screenshot();

	# strip first 10 screenshots, if they are too small (was that related to some ffmpeg issues?)
	if(($framecounter++ < 10) && $img->xres()<800) { return; }

	# TODO detect bad needles

	my $filename=$path.sprintf("%s.%06i.png", POSIX::strftime("%Y%m%d_%H%M%S", gmtime($t->[0])), $t->[1]);
        unless($flags=~m/q/) {
                fctlog('screendump', "filename=$filename");
        }

	#print STDERR $filename,"\n";

	# hardlinking identical files saves space

	# 47 is about the similarity of two screenshots with blinking cursor
	if($lastscreenshot && $lastscreenshot->similarity($img) > 47) {
		symlink(basename($lastscreenshotName), $filename);
		$lastscreenshotCount++;
		$prestandstillwarning=($lastscreenshotCount>$standstillthreshold/2);
		if($lastscreenshotCount>$standstillthreshold) {
			timeout_screenshot(); sleep 1;
			my $dir=result_dir;
			sendkey "alt-sysrq-w";
			sendkey "alt-sysrq-l";
			sendkey "alt-sysrq-d"; # only available with CONFIG_LOCKDEP
			do_take_screenshot()->write_optimized("$dir/standstill-1.png");sleep 1;
			mydie "standstill detected. test ended. see $filename\n"; # above 120s of autoreboot
		}
	}
	else { # new
		$img->write($filename) || die "write $filename";
		$screenshotQueue->enqueue($filename);
		$lastscreenshot = $img;
		$lastscreenshotName = $filename;
		$lastscreenshotCount = 0;
		#my $ocr=get_ocr($img);
		#if($ocr) { diag "ocr: $ocr" }
	}
}

sub do_start_audiocapture($) {
	my $filename = shift;
	fctlog('start_audiocapture', $filename);
	$backend->start_audiocapture($filename);
}

sub do_stop_audiocapture($) {
	my $index = shift;
	fctlog('stop_audiocapture', $index);
	$backend->stop_audiocapture($index);
}

sub alive() {
	if(defined $backend) {
		# backend will kill me when
		# backend.run has been deleted
		return $backend->alive();
	}
	return 0;
}

sub set_current_test($) {
	$current_test = shift;
}

sub get_cpu_stat() {
	my($statuser, $statsystem) = $backend->cpu_stat();
	my $statstr = '';
	if ($statuser) {
		for($statuser,$statsystem) {$_/=$clock_ticks}
		$statstr .= "statuser=$statuser ";
		$statstr .= "statsystem=$statsystem ";
	}
	return $statstr;
}


# runtime information gathering functions end


# check functions (runtime and result-checks)

sub get_ocr($) {
	# input: tinycv object
	my $img=shift;
	my $ocr=ocr::get_ocr($img, "-m 2 -s 6", \@ocrrect);
	if(!$ocr) {return ""}
	$ocr=~s/^[_ \t\n]+//;
	$ocr=~s/\n/ --- /g;
	# correct common mis-readings:
	$ocr=~s/nstaII/nstall/g;
	$ocr=~s/l(install|Remaining)/($1/g;
	return " ocr='$ocr'";
}

sub decodewav($) {
	# FIXME: move to multimonNG (multimon fork)
	my $wavfile = shift;
	unless ($wavfile) {
		warn "missing file name";
		return undef;
	}
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

# check functions end


# wait functions

=head2 waitstillimage

waitstillimage([$stilltime_sec [, $timeout_sec [, $similarity_level]]])

Wait until the screen stops changing

=cut
sub waitstillimage(;$$$) {
	my $stilltime=shift||7;
	my $timeout=shift||30;
	my $similarity_level=shift||47;
	my $starttime=time;
	fctlog('waitstillimage', "stilltime=$stilltime", "timeout=$timeout", "simlvl=$similarity_level");
        my $lastchangetime=[gettimeofday];
        my $lastchangeimg = getcurrentscreenshot();
	while(time-$starttime<$timeout) {
	        my $img=getcurrentscreenshot();
		my $sim = $img->similarity($lastchangeimg);
		my $now = [gettimeofday];
		if ($sim < $similarity_level) {
			# a change
			$lastchangetime=$now;
			$lastchangeimg=$img;
		}
		if (($now->[0] - $lastchangetime->[0])+($now->[1] - $lastchangetime->[1])/1000000.>=$stilltime) {
				fctres('waitstillimage', "detected same image for $stilltime seconds");
				return 1;
		}
		sleep(0.5);
	}
	timeout_screenshot();
	fctres('waitstillimage', "waitstillimage timed out after $timeout");
	return 0;
}

sub waitimage($;$$) {
	my $reflist = shift;
	my $timeout = shift || 60;
	my $flags = shift || 'd';
	my $wact = ($flags=~m/s/)?'disappear':'appear';
	fctlog('waitimage', "reflist=$reflist", "timeout=$timeout", "flags=$flags");
	diag "WARNING: waitimage is no longer supported\n";
	for(my $i=0;$i<=$timeout;$i+=2) {
		getcurrentscreenshot();
		sleep 1;
	}
	timeout_screenshot();
	fctres('waitimage', "Waiting for images $reflist ($wact) timed out!");
	return undef;
}

=head2 waitcolor

waitcolor($rgb_minmax [, $timeout_sec])

$rgb_minmax is 	[[red_min,red_max], [green_min,green_max], [blue_min,blue_max]]
eg: [undef, [0.2, 0.7], [0,0.1]]

=cut
sub waitcolor($;$) {
	my $rgb_minmax = shift;
	my $timeout = shift || 30;
	my $starttime = time;
	fctlog('waitcolor', "rgb=".dump(@$rgb_minmax), "timeout=$timeout");
	while(time-$starttime<$timeout) {
                my @lastavgcolor = getcurrentscreenshot()->avgcolor();
		if (check_color(\@lastavgcolor, $rgb_minmax)) {
			fctres('waitcolor', "detected ".dump(@lastavgcolor));
			return 1;
		}
		sleep 1;
	}
	timeout_screenshot();
	fctres('waitcolor', "rgb ".dump(@$rgb_minmax)." timed out after $timeout");
	return 0;
}

=head2 waitserial

waitserial($regex [, $timeout_sec])

Wait for a message to appear on serial output.
You could have sent it there earlier with

C<script_run("echo Hello World E<gt> /dev/$serialdev");>

=cut
sub waitserial($;$) {
	# wait for a message to appear on serial output
	my $regexp=shift;
	my $timeout=shift||90; # seconds
	fctlog('waitserial', "regex=$regexp", "timeout=$timeout");
	for my $n (1..$timeout) {
		my $str=`tail $serialfile`;
		if($str=~m/$regexp/) {fctres('waitserial', "found $regexp"); return 1;}
		if($prestandstillwarning) {return 2}
		sleep 1;
	}
	fctres('waitserial', "$regexp timed out after $timeout");
	return 0;
}

=head2 waitidle

waitidle([$timeout_sec])

Wait until the system becomes idle (as configured by IDLETHESHOLD in env.sh)

=cut
sub waitidle(;$) {
	my $timeout=shift||19;
	my $prev;
	fctlog('waitidle', "timeout=$timeout");
	my $timesidle=0;
	for my $n (1..$timeout) {
		my($stat, $systemstat) = $backend->cpu_stat();
		sleep 1; # sleep before skip to timeout when having no data (hw)
		next unless $stat;
		$stat += $systemstat;
		if($prev) {
			my $diff = $stat - $prev;
			diag("waitidle $timesidle d=$diff");
			if($diff<$idlethreshold) {
				if(++$timesidle > $timesidleneeded) { # idle for $x sec
				#if($diff<2000000) # idle for one sec
					fctres('waitidle', "idle detected");
					return 1;
				}
			}
			else {$timesidle=0}
		}
		$prev = $stat;
	}
	fctres('waitidle', "timed out after $timeout");
	return 0;
}

sub waitinststage($;$$) {
        my $stage = shift;
	my $timeout = shift||30;
	my $extra = shift;
	die "FIXME: what is extra?\n" if $extra;
	return waitforneedle($stage, $timeout);
}

sub save_needle_template($$$)
{
	my ($img, $mustmatch, $tags) = @_;

	my $t = POSIX::strftime("%Y%m%d_%H%M%S", gmtime());

	my $imgfn  = result_dir() . "/template-$mustmatch-$t.png";
	my $jsonfn = result_dir() . "/template-$mustmatch-$t.json";

	my $template = {
		area => [ {
			xpos => 0, ypos => 0,
			width => $img->xres(),
			height => $img->yres(),
			type => 'match' }
		],
		tags => [ @$tags ],
	       };

	$img->write_optimized($imgfn);

	open(my $fd, ">", $jsonfn) or die "$jsonfn: $!\n";
	print $fd JSON->new->pretty->encode( $template );
	close($fd);

	diag("wrote $jsonfn");

	return shared_clone({ img => $jsonfn, needle => $jsonfn, name => $mustmatch });
}

sub _waitforneedle {
	my %args = @_;
	my $mustmatch = $args{'mustmatch'};
	my $timeout = $args{'timeout'} || 30;
	my $checkneedle = $args{'check'};

	die "current_test undefined" unless $current_test;

	$args{'retried'} ||= 0;

	# get the array reference to all matching needles
	my $needles;
	my @tags;
	if (ref($mustmatch) eq "ARRAY") {
		$needles = $mustmatch;
		$mustmatch = '';
		for my $n (@{$needles}) {
			$mustmatch .= $n->{name} . "_";
		}
		@tags = map { $_->{'name'} } @$needles;
	} elsif ($mustmatch) {
		$needles = needle::tags($mustmatch) || [];
		@tags = ($mustmatch);
	}
	fctlog('waitforneedle', "'$mustmatch'", "timeout=$timeout");
	if (!@$needles) {
		diag("NO matching needles for $mustmatch");
	}
	my $img = getcurrentscreenshot();
	my $oldimg;
	my $failed_candidates;
	for my $n (1..$timeout) {
		if ($stop_waitforneedle) {
			$stop_waitforneedle = 0;
			last;
		}
		my $statstr = get_cpu_stat();
		if ($oldimg) {
			sleep 1;
			$img = getcurrentscreenshot();
			if ($oldimg == $img) { # no change, no need to search
				diag(sprintf("no change %d $statstr", $timeout-$n));
				next;
			}
		}
		my $foundneedle;
		($foundneedle, $failed_candidates) = $img->search($needles);
		if ($foundneedle) {
			$current_test->record_screenmatch($img, $foundneedle, \@tags);
			my $lastarea = $foundneedle->{'area'}->[-1];
			fctres(sprintf("found %s, similarity %.2f @ %d/%d",
				$foundneedle->{'needle'}->{'name'},
				$lastarea->{'similarity'},
				$lastarea->{'x'}, $lastarea->{'y'}));
			if ($args{'click'}) {
				my $rx = 1; # $origx / $img->xres();
				my $ry = 1; # $origy / $img->yres();
				my $x = ($lastarea->{'x'} + $lastarea->{'w'}/2)*$rx;
				my $y = ($lastarea->{'y'} + $lastarea->{'h'}/2)*$ry;
				diag ("clicking at $x/$y");
				mouse_set($x, $y);
				mouse_click($args{'click'}, $args{'clicktime'});
			}
			return $foundneedle;
		}
		diag("STAT $statstr");
		$oldimg = $img;
	}
	fctres('waitforneedle', "match=$mustmatch timed out after $timeout");
	for (@{$needles||[]}) {
		diag $_->{'file'};
	}

	# add some known env variables
	for my $key (qw(VIDEOMODE DESKTOP DISTRI INSTLANG LIVECD)) {
		push(@tags, "ENV-$key-" . $ENV{$key}) if $ENV{$key};
	}


	lock($interactive_lock);
	$needle_template = save_needle_template($img, $mustmatch, \@tags);

	if ($interactive_mode) {
		lock($interactive_lock);
		print "interactive mode entered\n";
		freeze_vm();

		$needle_template->{name} .= '-'.$interactive_mode;

		$current_test->record_screenfail(
			img => $img,
			needles => $failed_candidates,
			tags => \@tags,
			result => $checkneedle?'unk':'fail',
			overall => $checkneedle?undef:'fail'
		);

		$waiting_for_new_needle = sprintf("%s/needles/%s-%s.json",
				$ENV{'CASEDIR'}, $mustmatch, $interactive_mode);

		save_results();

		print "waiting for signal\n";
		cond_wait($interactive_lock);
		print "got signal\n";

		$current_test->remove_last_result();

		if ($waiting_for_new_needle && ref $waiting_for_new_needle eq 'HASH') {
			for my $n (needle->all()) {
				if ($n->{'name'} eq $waiting_for_new_needle) {
					$n->unregister();
				}
			}
			diag("creating new needle ".$waiting_for_new_needle->{'name'});
			my $pngfn = join('/', needle::get_needle_dir(), $waiting_for_new_needle->{'name'}.'.png');
			$img->write_optimized($pngfn);
			# create copy of the hash in order to not
			# use the the shared hash
			my $data = {%{$waiting_for_new_needle}};
			my $n = needle->new($data) || mydie "creating needle failed: $!";
			$n->save();
			$waiting_for_new_needle = undef;
			save_results();
			cont_vm();
			return _waitforneedle(mustmatch => $mustmatch, timeout => 3, check => $checkneedle, retried => $args{'retried'}+1);
		}
		$waiting_for_new_needle = undef;
		save_results();
		cont_vm();
	}

	# beware of spaghetti code below
	my $newname;
	my $run_editor = 0;
	if ($ENV{'scaledhack'}) {
		freeze_vm();
		my $needle;
		for my $cand (@{$failed_candidates||[]}) {
			fctres(sprintf("candidate %s, similarity %.2f @ %d/%d",
					$cand->{'needle'}->{'name'},
					$cand->{'area'}->[-1]->{'similarity'},
					$cand->{'area'}->[-1]->{'x'}, $cand->{'area'}->[-1]->{'y'}));
			$needle = $cand->{'needle'};
			last;
		}

		for my $i (1..@{$needles||[]}) {
			printf "%d - %s\n", $i, $needles->[$i-1]->{'name'};
		}
		print "note: called from checkneedle()\n" if $checkneedle;
		print "(E)dit, (N)ew, (Q)uit, (C)ontinue\n";
		my $r = <STDIN>;
		if ($r =~ /^(\d+)/) {
			$r = 'e';
			$needle = $needles->[$1-1];
		}
		if ($r =~ /^e/i) {
			unless ($needle) {
				$needle = $needles->[0] if $needles;
				die "no needle\n" unless $needle;
			}
			$newname = $needle->{'name'};
			$run_editor = 1;
		} elsif ($r =~ /^n/i) {
			$run_editor = 1;
		} elsif ($r =~ /^q/i) {
			$args{'retried'} = 99;
			backend_send("cont");
		} else {
			backend_send("cont");
		}
	} elsif (!$checkneedle && $ENV{'interactive_crop'}) {
		$run_editor = 1;
	}

	if ($run_editor && $args{'retried'} < 3) {
		$newname = $mustmatch.($ENV{'interactive_crop'} || '') unless $newname;
		freeze_vm();
		system("$scriptdir/crop.py", '--new', $newname, $needle_template->{'needle'}) == 0 || mydie;
		backend_send("cont");
		my $fn = sprintf("%s/needles/%s.json", $ENV{'CASEDIR'}, $newname);
		if (-e $fn)
		{
			for my $n (needle->all()) {
				if ($n->{'file'} eq $fn) {
					$n->unregister();
				}
			}
			diag("reading new needle $fn");
			needle->new($fn) || mydie "$!";
			# XXX: recursion!
			return _waitforneedle(mustmatch => $mustmatch, timeout => 3, check => $checkneedle, retried => $args{'retried'}+1);
		}
	}

	$current_test->record_screenfail(
		img => $img,
		needles => $failed_candidates,
		tags => \@tags,
		result => $checkneedle?'unk':'fail',
		overall => $checkneedle?undef:'fail'
	);
	unless ($args{'check'}) {
		mydie "needle(s) '$mustmatch' not found";
	}
	return undef;
}

sub waitforneedle($;$) {
	return _waitforneedle(mustmatch => $_[0], timeout => $_[1]);
}

sub checkneedle($;$) {
	return _waitforneedle(mustmatch => $_[0], timeout => $_[1], check => 1);
}

# warning: will not work due to https://bugs.launchpad.net/qemu/+bug/752476
sub goandclick($;$$$) {
	return _waitforneedle(mustmatch => $_[0],
		click => ($_[1] || 'left'),
		timeout => $_[2],
		clicktime => $_[3]);
}

sub makesnapshot($) {
    my $sname = shift;
    diag("Creating a VM snapshot $sname");
    $backend->do_savevm($sname);
}

sub loadsnapshot($) {
    my $sname = shift;
    diag("Loading a VM snapshot $sname");
    $backend->do_loadvm($sname); sleep(10);
}

# dump all info in one big file. Alternatively each test could write
# one file and we collect only the overall status.
sub save_results(;$$)
{
	$testmodules = shift if @_;
	my $fn = shift || result_dir()."/results.json";
	open(my $fd, ">", $fn) or die "can not write results.json: $!\n";
	fcntl($fd, F_SETLKW, pack('ssqql', F_WRLCK, 0, 0, 0, $$)) or die "cannot lock results.json: $!\n";
	truncate($fd, 0) or die "cannot truncate results.json: $!\n";
	print $fd to_json({
		'jsonrpc' => $ENV{'QEMUPORT'}+2,
		'needledir' => needle::get_needle_dir(),
		'running' => $current_test?ref($current_test):'',
		'testmodules' => $testmodules,
		'interactive' => $interactive_mode?1:0,
		'needinput' => $waiting_for_new_needle?1:0,
		}, { pretty => 1 });
	close($fd);
}


#FIXME: new wait functions
# waitscreenactive - ($backend->screenactive())
# wait-time - like sleep but prints info to log
# wait-screen-(un)-active to catch reboot of hardware

# wait functions end


1;

# Local Variables:
# tab-width: 8
# cperl-indent-level: 8
# End:
