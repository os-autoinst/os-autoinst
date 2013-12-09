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
use ppm;
use threads;
use threads::shared;
use POSIX; 
use Term::ANSIColor;
use Data::Dump "dump";

our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw($realname $username $password $scriptdir $testresults $serialdev $testedversion %cmd
&diag &modstart &fileContent &qemusend_nolog &qemusend &backend_send_nolog &backend_send &sendkey &sendkeyw &sendautotype &sendpassword &mouse_move &mouse_set &mouse_click &mouse_hide &clickimage &result_dir
&timeout_screenshot &waitidle &waitserial &waitgoodimage &waitimage &waitinststage &waitstillimage &waitcolor &init_backend &start_vm &set_hash_rects &set_ocr_rect &get_ocr
&script_run &script_sudo &script_sudo_logout &x11_start_program &ensure_installed &clear_console &set_std_hash_rects &getcurrentscreenshot &power &mydie);


# shared vars

my $goodimageseen :shared = 0;
my $lastname :shared = 0;
my $lastinststage :shared = "";
my $lastknowninststage :shared = "";
my $prestandstillwarning :shared = 0;
my $timeoutcounter :shared = 0;
share($ENV{SCREENSHOTINTERVAL}); # to adjust at runtime
my @lastavgcolor = (0,0,0); share(@lastavgcolor);
my @ocrrect; share(@ocrrect);
my @extrahashrects; share(@extrahashrects);

# shared vars end


# global vars

our $logfd;

our $clock_ticks = POSIX::sysconf( &POSIX::_SC_CLK_TCK );

our $debug=1;
our $idlethreshold=($ENV{IDLETHRESHOLD}||$ENV{IDLETHESHOLD}||18)*$clock_ticks/100; # % load max for being considered idle
our $timesidleneeded=2;
our $standstillthreshold=530;

our $realname="Bernhard M. Wiedemann";
our $username="bernhard";
our $password="nots3cr3t";

our $testresults="testresults";
our $serialdev="ttyS0"; #FIXME: also backend
our $serialfile="serial0";
our $gocrbin="/usr/bin/gocr";

our $scriptdir=$0; $scriptdir=~s{/[^/]+$}{};
our $testedversion=$ENV{ISO}||""; $testedversion=~s{.*/}{};$testedversion=~s/\.iso$//; $testedversion=~s{-Media1?$}{};
if(!$ENV{DISTRI}) {
	if($testedversion=~m/^(debian|openSUSE|Fedora|SLE[SD]-1\d|oi|FreeBSD|archlinux|Mageia)-/) {$ENV{DISTRI}=lc($1)}
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

## set good-foo vars
our %md5goodlist = qw();
our %md5badlist = qw();
our %md5inststage = qw();
do "goodimage.pm"; # fill above vars
my %goodsizes=(1440015=>1, 1437615=>1, 2359312=>1, 864015=>1, 3686416=>1);
# set good-foo vars end

## some var checks
if(!-x $gocrbin) {$gocrbin=undef}
if($ENV{SUSEMIRROR} && $ENV{SUSEMIRROR}=~s{^(\w+)://}{}) { # strip & check proto
	if($1 ne "http") {die "only http mirror URLs are currently supported but found '$1'."}
}
## some var checks end

# global vars end


# local vars

my %md5file; # for symlinking identical screenshots

our $backend; #FIXME: make local after adding frontend-api to bmwqemu

my $framecounter = 0; # screenshot counter

## sudo stuff
my $sudotimeout=298; # 5 mins
my $lastsudotime;
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

sub set_hash_rects {
	# sharing nested structure does not work, so turn arrayref into string
	@extrahashrects = map {join(",", @$_)} @_;
}

sub set_std_hash_rects() {
	set_hash_rects(
		[30,30,100,100], # where most applications pop up
		[630,30,100,100], # where some applications pop up
		[0,579,100,10 ], # bottom line (KDE/GNOME bar)
		[0,750,90,10 ], # bottom line (KDE/GNOME bar) in 1024
	);
}

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

sub fileContent($) {
	my($fn)=@_;
	open(my $fd, $fn) or return undef;
	local $/;
	my $result=<$fd>;
	close($fd);
	return $result;
}

sub hashrect($$$) {
	my ($ppm,$rect,$flags)=@_;
	my $ppm2=$ppm->copyrect(@$rect);
	my @result;
	return unless $ppm2;
	if($flags=~m/r/) {$ppm2->replacerect(0,137,13,15);} # mask out text
	if($flags=~m/c/) {push(@result, [Digest::MD5::md5_hex($ppm2->{data}),$rect,$flags])} # extra coloured version hash
	if($flags=~m/t/) {$ppm2->threshold(0x80);} # black/white => drop most background
	return (@result,[Digest::MD5::md5_hex($ppm2->{data}),$rect,$flags]);
}

sub result_dir() {
	if(dirname(__FILE__) ne ".") {
		mkdir $testresults;
		mkdir "$testresults/$testedversion";
	}
	return "$testresults/$testedversion"
}

sub getcurrentscreenshot() {
	my $mylastname = $lastname;
	sleep 0.4; # time to write the file
	return fileContent($mylastname);
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
	open($logfd, ">>", "currentautoinst-log.txt");
	# set unbuffered so that sendkey lines from main thread will be written
	my $oldfh=select($logfd); $|=1; select($oldfh);
}

sub start_vm() {
	$backend->start_vm();
}

sub mydie {
	fctlog('mydie', "@_");
	$backend->stop_vm();
	close $logfd;
	sleep 1;
	exit 1;
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
	sleep(0.15);
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
	my $maxinterval=shift||13;
	my $typedchars=0;
	fctlog('sendautotype', "string='$string'");
	foreach my $letter (split("", $string)) {
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
	my ($prog,$wait)=@_;
	sendautotype("sudo $prog\n");
	if(!$lastsudotime||$lastsudotime+$sudotimeout<time()) {$sudos=0}
	if($password && !$sudos++) {
		waitidle();
		sendpassword;
		sendkey "ret";
	}
	$lastsudotime=time();
	waitidle($wait);
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
	waitstillimage(6,90); # wait for install
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

sub do_take_screenshot($;$) {
	my $filename = shift;
	my $flags = shift || '';
	unless($flags=~m/q/) {
		fctlog('screendump', "filename=$filename");
	}
	$backend->screendump($filename);
}

sub timeout_screenshot() {
	my $n = ++$timeoutcounter;
	my $dir=result_dir;
	my $n2=sprintf("%02i",$n);
	do_take_screenshot("$dir/timeout-$n2.ppm");
}

sub take_screenshot(;$) {
	my $flags = shift || '';
	my $path="qemuscreenshot/";
	mkdir $path;
	if($lastname && -e $lastname) { # processing previous image, because saving takes time
		# symlinking identical files saves space
		my $data=fileContent($lastname);
		my $md5=Digest::MD5::md5_hex($data);
		if($md5badlist{$md5}) {diag "error condition detected. test failed. see $lastname"; sleep 1; mydie "bad image seen"}
		my($statuser, $statsystem) = $backend->cpu_stat();
		my $statstr = '';
		if ($statuser) {
			for($statuser,$statsystem) {$_/=$clock_ticks}
			$statstr .= "statuser=$statuser ";
			$statstr .= "statsystem=$statsystem ";
		}
		if (defined $data and length($data) gt 0) {
			@lastavgcolor = ppm->new($data)->avgcolor();
		}
		my $filevar = "file=".basename($lastname)." ";
		my $laststgvar = ($ENV{HW})?"laststage=$lastinststage ":'';
		my $md5var = ($ENV{HW})?'':"md5=$md5 ";
		my $avgvar = "avgcolor=".join(',', map(sprintf("%.3f", $_), @lastavgcolor));
		diag($md5var.$filevar.$laststgvar.$statstr.$avgvar);

		if($md5goodlist{$md5}) {$goodimageseen=1; diag "good image"}

		# ignore bottom 15 lines (blinking cursor, animated mouse-pointer)
		if(length($data)==1440015) {$md5=Digest::MD5::md5(substr($data,15,800*3*(600-15)))}
		if($md5file{$md5}) { # old
			unlink($lastname); # warning: will break if FS does not support symlinking
			symlink(basename($md5file{$md5}->[0]), $lastname);
			my $linkcount=$md5file{$md5}->[1]++;
			$prestandstillwarning=($linkcount>$standstillthreshold/2);
			if($linkcount>$standstillthreshold) {
				timeout_screenshot(); sleep 1;
				my $dir=result_dir;
				sendkey "alt-sysrq-w";
				sendkey "alt-sysrq-l";
				sendkey "alt-sysrq-d"; # only available with CONFIG_LOCKDEP
				do_take_screenshot("$dir/standstill-1.ppm", $flags);sleep 1;
				mydie "standstill detected. test ended. see $lastname\n"; # above 120s of autoreboot
			}
		}
		else { # new
			$md5file{$md5}=[$lastname,1];
			my $ocr=get_ocr(\$data);
			if($ocr) { diag "ocr: $ocr" }
			inststagedetect(\$data);
		}
		# strip first 10 screenshots, if they are too small (was that related to some ffmpeg issues?)
		if(($framecounter++ < 10) && length($data)<800*600*3) {unlink($lastname)}
	}
	my $t=[gettimeofday()];
	my $filename=$path.sprintf("%i.%06i.ppm", $t->[0], $t->[1]);
	#print STDERR $filename,"\n";
	do_take_screenshot($filename, $flags);
	$lastname=$filename;
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

# runtime information gathering functions end


# check functions (runtime and result-checks)

sub checkrefimgs($$$) {
	my ($screenimg, $refimg, $flags) = @_;
	my $screenppm = ppm->new(fileContent($screenimg));
	my $refppm = ppm->new(fileContent($refimg));
	if (!$screenppm || !$refppm) {
		return undef;
	}
	if ($flags=~m/t/) {
		# black/white => drop most background
		$screenppm->threshold(0x80);
		$refppm->threshold(0x80);
	}
	if ($flags=~m/f/) {
		# perform vector-based fuzzy matching using opencv
		return $screenppm->search_fuzzy($refppm);
	}
	elsif ($flags=~m/d/) {
		# allow difference of 40 per byte
		return $screenppm->search($refppm, 40);
	}
	else {
		return $screenppm->search($refppm, 0);
	}
}

sub get_ocr($) {
	# input: ref on PPM data
	my $dataref=shift;
	my $ocr=ocr::get_ocr($dataref, "-m 2 -s 6", \@ocrrect);
	if(!$ocr) {return ""}
	$ocr=~s/^[_ \t\n]+//;
	$ocr=~s/\n/ --- /g;
	# correct common mis-readings:
	$ocr=~s/nstaII/nstall/g;
	$ocr=~s/l(install|Remaining)/($1/g;
	return " ocr='$ocr'";
}

sub inststagedetect($) {
	# input: ref on PPM data
	my $dataref=shift;
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
	# left side for 12.3-grub2 logo
	push(@md5, hashrect($ppm, [100,100, 100,300], ""));
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
		unless($ENV{'HW'}) {
			# useless due to analog VGA
			diag "stage=$currentinststage $md5 ".join(",",@$rect)." $flags";
		}
		next if $found;
		if($currentinststage) { $lastknowninststage=$lastinststage=$currentinststage }
		if($currentinststage){$found=1}; # stop on first match - so must put most specific tests first
	}
	if($found) {return}
	$lastinststage="unknown";
}

sub decodewav($) {
	# FIXME: move to multimonNG (multimon fork)
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

# check functions end


# wait functions

=head2 waitstillimage

waitstillimage([$stilltime_sec [, $timeout_sec [, $maxdiff_bytes]]])

Wait until the screen stops changing

=cut
sub waitstillimage(;$$$) {
	my $stilltime=shift||7;
	my $timeout=shift||30;
	my $maxdiff=shift||20;
	my $starttime=time;
	my @recentimages; # fifo
	fctlog('waitstillimage', "stilltime=$stilltime", "timeout=$timeout", "maxdiff=$maxdiff");
	while(time-$starttime<$timeout) {
		my $mylastname = $lastname;
		sleep 1;
		my $data=fileContent($mylastname);
		next unless $data; # this must stay to get only valid imgs to fifo
		push(@recentimages, $mylastname);
		if(@recentimages  > $stilltime) {
			my $e = shift @recentimages;
			if (ppm->new($data)->maxbytediff(ppm->new(fileContent($e)), $maxdiff)) {
				fctres('waitstillimage', "detected same image for $stilltime seconds");
				return 1;
			}
		}
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
	$reflist =~s/\.ppm$//;
	my @refimgs = <$scriptdir/waitimgs/$reflist.ppm>;
	diag "WARNING: No refimgs with name '$reflist' found!" unless(@refimgs);
	my ($lastmd5,$thismd5) = (0,0);
	for(my $i=0;$i<=$timeout;$i+=2) {
		# prevent reading while screendump is not finished
		my $mylastname = $lastname;
		sleep 2;
		$thismd5 = Digest::MD5::md5_hex(fileContent($mylastname));
		# image is equal with previous one
		unless($lastmd5 eq $thismd5) {
			foreach my $refimg (@refimgs) {
				my $refimg_print = basename($refimg);
				my $mylastname_print = basename($mylastname);
				fctinfo('waitimage', "checking $refimg_print against $mylastname_print");
				my @a=checkrefimgs($mylastname,$refimg,$flags);
				if($flags=~m/s/) {
					if (!defined $a[0]) {
						fctres('waitimage', "$refimg_print disappeared in $mylastname_print");
						$refimg=~s/^.*waitimgs\/(.*)$/$1/;
						return 1;
					}
				}
				elsif(defined $a[0]) {
					fctres('waitimage', "found $refimg_print in $mylastname_print");
					$refimg=~s/^.*waitimgs\/(.*)$/$1/;
					push(@a, $refimg);
					return \@a;
				}
			}
		}
		$lastmd5 = $thismd5;
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

sub waitgoodimage(;$) {
	my $timeout=shift||10;
	$goodimageseen=0;
	fctlog('waitgoodimage', "timeout=$timeout");
	for my $n (1..$timeout) {
		if($goodimageseen) {fctres('waitgoodimage', "seen good image... continuing execution"); return 1;}
		sleep 1;
	}
	timeout_screenshot();
	fctres('waitgoodimage', "timed out after $timeout");
	return 0;
}

sub waitinststage($;$$) {
	my $stage=shift;
	my $timeout=shift||30;
	my $extradelay=shift||3;
	fctlog('waitinststage', "stage=$stage", "timeout=$timeout", "extradelay=$extradelay");
	if($prestandstillwarning) { sleep 3 }
	for my $n (1..$timeout) {
		if($lastinststage=~m/$stage/) {fctres('waitinststage', "detected stage=$stage ... continuing execution"); sleep $extradelay; return 1;}
		if($prestandstillwarning) {
			timeout_screenshot();
			diag "WARNING: waited too long for stage=$stage";
			$prestandstillwarning=0;
			return 2;
		}
		sleep 1;
	}
	timeout_screenshot() if($timeout>1);
	fctres('waitinststage', "stage=$stage timed out after $timeout");
	return 0;
}

#FIXME: new wait functions
# waitscreenactive - ($backend->screenactive())
# wait-time - like sleep but prints info to log
# wait-screen-(un)-active to catch reboot of hardware

# wait functions end


1;
