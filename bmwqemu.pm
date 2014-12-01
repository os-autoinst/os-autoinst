$| = 1;

package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep gettimeofday);
use Digest::MD5;
use IO::Socket;
use File::Basename;
use File::Path qw(remove_tree);
use File::Copy qw(cp);

# eval {require Algorithm::Line::Bresenham;};
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

use base 'Exporter';
use Exporter;

our $VERSION;
our @EXPORT = qw(diag fileContent save_vars);

sub mydie;

# shared vars

my $goodimageseen : shared           = 0;
my $screenshotQueue                  = Thread::Queue->new();
my $prestandstillwarning : shared    = 0;
my $numunchangedscreenshots : shared = 0;

my @ocrrect;
share(@ocrrect);
my @extrahashrects;
share(@extrahashrects);

our $interactive_mode;
our $needle_template;
our $waiting_for_new_needle;

# shared vars end

# list of files that are used to control the behavior
our %control_files = (
    "reload_needles_and_retry" => "reload_needles_and_retry",
    "interactive_mode"         => "interactive_mode",
    "stop_waitforneedle"       => "stop_waitforneedle",
);

# global vars

our $testmodules = [];

our $logfd;

our $clock_ticks = POSIX::sysconf(&POSIX::_SC_CLK_TCK);

our $debug               = -t 1;                                                                        # enable debug only when started from a tty
our $timesidleneeded     = 2;
our $standstillthreshold = 600;

our $encoder_pipe;

sub load_vars() {
    my $fn = "vars.json";
    my $ret;
    local $/;
    open(my $fh, '<', $fn) or return 0;
    eval {$ret = decode_json(<$fh>);};
    warn "openQA didn't write proper vars.json" if $@;
    close($fh);
    return $ret;
}

our %vars;

sub save_vars() {
    my $fn = "vars.json";
    unlink "vars.json" if -e "vars.json";
    open( my $fd, ">", $fn ) or die "can not write vars.json: $!\n";
    fcntl( $fd, F_SETLKW, pack( 'ssqql', F_WRLCK, 0, 0, 0, $$ ) ) or die "cannot lock vars.json: $!\n";
    truncate( $fd, 0 ) or die "cannot truncate vars.json: $!\n";

    print $fd to_json( \%vars, { pretty => 1 } );
    close($fd);
}

share( $vars{SCREENSHOTINTERVAL} );    # to adjust at runtime

our $testresults    = "testresults";
our $screenshotpath = "qemuscreenshot";
our $liveresultpath;

our $serialfile     = "serial0";
our $serial_offset  = 0;
our $gocrbin        = "/usr/bin/gocr";

# set from isotovideo during initialization
our $scriptdir;

our $testedversion;

sub init {
    %vars = %{load_vars() || {}};
    $vars{NAME} ||= 'noname';
    $liveresultpath = "$testresults/$vars{NAME}";
    open( $logfd, ">>", "$liveresultpath/autoinst-log.txt" );
    # set unbuffered so that send_key lines from main thread will be written
    my $oldfh = select($logfd);
    $| = 1;
    select($oldfh);

    our $testedversion = $vars{NAME};
    unless ($testedversion) {
        $testedversion = $vars{ISO} || "";
        $testedversion =~ s{.*/}{};
        $testedversion =~ s/\.iso$//;
        $testedversion =~ s{-Media1?$}{};
    }

    result_dir(); # init testresults dir

    cv::init();
    require tinycv;

    die "DISTRI undefined\n" unless $vars{DISTRI};

    unless ( $vars{CASEDIR} ) {
        my @dirs = ("$scriptdir/distri/$vars{DISTRI}");
        unshift @dirs, $dirs[-1] . "-" . $vars{VERSION} if ( $vars{VERSION} );
        for my $d (@dirs) {
            if ( -d $d ) {
                $vars{CASEDIR} = $d;
                last;
            }
        }
        die "can't determine test directory for $vars{DISTRI}\n" unless $vars{CASEDIR};
    }

    ## env vars
    $vars{UEFI_BIOS} ||= 'ovmf-x86_64-ms.bin';
    if ($vars{UEFI_BIOS} =~ /\/|\.\./) {
        die "invalid characters in UEFI_BIOS\n";
    }
    if ( $vars{UEFI} && !-e '/usr/share/qemu/'.$vars{UEFI_BIOS} ) {
        die "'$vars{UEFI_BIOS}' missing, check UEFI_BIOS\n";
    }

    testapi::init();

    # defaults
    $vars{QEMUPORT}  ||= 15222;
    $vars{VNC}       ||= 90;
    $vars{INSTLANG}  ||= "en_US";
    $vars{IDLETHRESHOLD} ||= 18;

    if ( defined( $vars{DISTRI} ) && $vars{DISTRI} eq 'archlinux' ) {
        $vars{HDDMODEL} = "ide";
    }

    if ( $vars{LAPTOP} ) {
        if ($vars{LAPTOP} =~ /\/|\.\./) {
            die "invalid characters in LAPTOP\n";
        }
        $vars{LAPTOP} = 'dell_e6330' if $vars{LAPTOP} eq '1';
        die "no dmi data for '$vars{LAPTOP}'\n" unless -d "$scriptdir/dmidata/$vars{LAPTOP}";
    }

    save_vars();

    ## env vars end

    ## some var checks
    if ( !-x $gocrbin ) {
        $gocrbin = undef;
    }
    if ( $vars{SUSEMIRROR} && $vars{SUSEMIRROR} =~ s{^(\w+)://}{} ) {    # strip & check proto
        if ( $1 ne "http" ) {
            die "only http mirror URLs are currently supported but found '$1'.";
        }
    }

}

## some var checks end

# global vars end

# local vars

our $backend;    #FIXME: make local after adding frontend-api to bmwqemu

my $framecounter = 0;    # screenshot counter

# local vars end

# global/shared var set functions

sub set_ocr_rect { @ocrrect = @_; }

# global/shared var set functions end

# util and helper functions

sub diag($) {
    $logfd && print $logfd "@_\n";
    return unless $debug;
    print STDERR "@_\n";
}

sub fctlog {
    my $fname   = shift;
    my @fparams = @_;
    $logfd && print $logfd '<<< ' . $fname . '(' . join( ', ', @fparams ) . ")\n";
    return unless $debug;
    print STDERR colored( '<<< ' . $fname . '(' . join( ', ', @fparams ) . ')', 'blue' ) . "\n";
}

sub fctres {
    my $fname   = shift;
    my @fparams = @_;
    $logfd && print $logfd ">>> $fname: @fparams\n";
    return unless $debug;
    print STDERR colored( ">>> $fname: @fparams", 'green' ) . "\n";
}

sub fctinfo {
    my $fname   = shift;
    my @fparams = @_;
    $logfd && print $logfd "::: $fname: @fparams\n";
    return unless $debug;
    print STDERR colored( "::: $fname: @fparams", 'yellow' ) . "\n";
}

sub modstart {
    my @text = @_;
    $logfd && printf $logfd "\n||| %s at %s\n", join( ' ', @text ), POSIX::strftime( "%F %T", gmtime );
    return unless $debug;
    print STDERR colored( "||| @text", 'bold' ) . "\n";
}

sub fileContent($) {
    my ($fn) = @_;
    open( my $fd, $fn ) or return undef;
    local $/;
    my $result = <$fd>;
    close($fd);
    return $result;
}

use autotest qw($current_test);
sub current_test() {
    return $autotest::current_test;
}

sub result_dir() {
    unless ( -e "$testresults/$testedversion" ) {
        mkdir $testresults;
        mkdir "$testresults/$testedversion" or die "mkdir $testresults/$testedversion: $!\n";
    }
    return "$testresults/$testedversion";
}

our $lastscreenshot;
our $lastscreenshotName = '';

sub getcurrentscreenshot(;$) {
    my $undef_on_standstill = shift;
    my $filename;

    # using a queue to get the latest is most likely the least efficient solution,
    # but we need to check the current screenshot not to miss things
    while ( $screenshotQueue->pending() ) {

        # unfortunately passing objects between threads is almost impossible
        $filename = $screenshotQueue->dequeue();
    }

    # if this is the first screenshot, be sure that we have something to return
    if ( !$lastscreenshot && !$filename ) {

        # blocking call
        $filename = $screenshotQueue->dequeue();
    }

    if ($filename && $lastscreenshotName ne $filename ) {
        $lastscreenshot     = tinycv::read($filename);
        $lastscreenshotName = $filename;
    }
    elsif ( !current_test->{post_fail_hook_running} ) {
        $prestandstillwarning = ( $numunchangedscreenshots > $standstillthreshold / 2 );
        if ( $numunchangedscreenshots > $standstillthreshold ) {
            diag "STANDSTILL";
            return undef if $undef_on_standstill;

            current_test->standstill_detected($lastscreenshot);
            mydie "standstill detected. test ended";    # above 120s of autoreboot
        }
    }

    return $lastscreenshot;
}

# util and helper functions end

# backend management

sub init_backend($) {
    my $name = shift;
    require "backend/$name.pm";
    $backend = "backend::$name"->new();
}

sub start_vm() {
    return unless $backend;

    # remove old screenshots
    remove_tree($screenshotpath);
    mkdir $screenshotpath;

    my $cwd = Cwd::getcwd();
    open($encoder_pipe, "|nice $scriptdir/videoencoder $cwd/video.ogv") || die "can't call $scriptdir/videoencoder";
    $backend->start_vm();
}

sub stop_vm() {
    return unless $backend;
    $backend->stop_vm();
    close($encoder_pipe);
    close $logfd;
}

sub freeze_vm() {
    $backend->send("stop");
}

sub cont_vm() {
    $backend->send("cont");
}

sub mydie {
    fctlog( 'mydie', "@_" );

    #	$backend->stop_vm();
    croak "mydie";
}

# to be called from thread
sub enqueue_screenshot($) {
    my $img = shift;

    $framecounter++;

    my $filename = $screenshotpath . sprintf( "/shot-%010d.png", $framecounter );

    #print STDERR $filename,"\n";

    # linking identical files saves space

    # 54 is based on t/data/user-settings-*
    my $sim = 0;
    $sim = $lastscreenshot->similarity($img) if $lastscreenshot;
    #diag "similarity is $sim";
    if ( $sim > 54 ) {
        symlink( basename($lastscreenshotName), $filename ) || warn "failed to create $filename symlink: $!\n";
        $numunchangedscreenshots++;
    }
    else {    # new
        $img->write($filename) || die "write $filename";
        # copy new one to shared directory, remove old one and change symlink
        cp($filename, $liveresultpath);
        unlink($liveresultpath .'/'. basename($lastscreenshotName)) if $lastscreenshot;
        $screenshotQueue->enqueue($filename);
        $lastscreenshot          = $img;
        $lastscreenshotName      = $filename;
        $numunchangedscreenshots = 0;
        unless(symlink(basename($filename), $liveresultpath.'/tmp.png')) {
            # try to unlink file and try again
            unlink($liveresultpath.'/tmp.png');
            symlink(basename($filename), $liveresultpath.'/tmp.png');
        }
        rename($liveresultpath.'/tmp.png', $liveresultpath.'/last.png');

        #my $ocr=get_ocr($img);
        #if($ocr) { diag "ocr: $ocr" }
    }
    if ( $sim > 50 ) { # we ignore smaller differences
        print $encoder_pipe "R\n";
    }
    else {
        print $encoder_pipe "E $lastscreenshotName\n";
    }
    $encoder_pipe->flush();
}

sub do_start_audiocapture($) {
    my $filename = shift;
    fctlog( 'start_audiocapture', $filename );
    $backend->start_audiocapture($filename);
}

sub do_stop_audiocapture($) {
    my $index = shift;
    fctlog( 'stop_audiocapture', $index );
    $backend->stop_audiocapture($index);
}

sub alive() {
    if ( defined $backend ) {

        # backend will kill me when
        # backend.run has been deleted
        return $backend->alive();
    }
    return 0;
}

sub get_cpu_stat() {
    my ( $statuser, $statsystem ) = $backend->cpu_stat();
    my $statstr = '';
    if ($statuser) {
        for ( $statuser, $statsystem ) { $_ /= $clock_ticks }
        $statstr .= "statuser=$statuser ";
        $statstr .= "statsystem=$statsystem ";
    }
    return $statstr;
}

# runtime information gathering functions end

# check functions (runtime and result-checks)

sub decodewav($) {

    # FIXME: move to multimonNG (multimon fork)
    my $wavfile = shift;
    unless ($wavfile) {
        warn "missing file name";
        return undef;
    }
    my $dtmf = '';
    my $mm   = "multimon -a DTMF -t wav $wavfile";
    open M, "$mm |" || return 1;
    while (<M>) {
        next unless /^DTMF: .$/;
        my ( $a, $b ) = split ':';
        $b =~ tr/0-9*#ABCD//csd;    # Allow 0-9 * # A B C D
        $dtmf .= $b;
    }
    close(M);
    return $dtmf;
}

# check functions end

# wait functions

=head2 wait_still_screen

wait_still_screen($stilltime_sec, $timeout_sec, $similarity_level)

Wait until the screen stops changing

=cut

sub wait_still_screen($$$) {

    my ($stilltime, $timeout, $similarity_level) = @_;

    my $starttime = time;
    fctlog( 'wait_still_screen', "stilltime=$stilltime", "timeout=$timeout", "simlvl=$similarity_level" );
    my $lastchangetime = [gettimeofday];
    my $lastchangeimg  = getcurrentscreenshot();
    while ( time - $starttime < $timeout ) {
        my $img = getcurrentscreenshot();
        my $sim = $img->similarity($lastchangeimg);
        my $now = [gettimeofday];
        if ( $sim < $similarity_level ) {

            # a change
            $lastchangetime = $now;
            $lastchangeimg  = $img;
        }
        if ( ( $now->[0] - $lastchangetime->[0] ) + ( $now->[1] - $lastchangetime->[1] ) / 1000000. >= $stilltime ) {
            fctres( 'wait_still_screen', "detected same image for $stilltime seconds" );
            return 1;
        }
        sleep(0.5);
    }
    current_test->timeout_screenshot();
    fctres( 'wait_still_screen', "wait_still_screen timed out after $timeout" );
    return 0;
}

=head2 set_serial_offset

Determines the starting offset within the serial file - so that we do not check the
previous test's serial output. Call this before you start doing something new

=cut

sub set_serial_offset() {
    $serial_offset = -s $serialfile;
}


=head2 serial_text

Returns the output on the serial device since the last call to set_serial_offset

=cut

sub serial_text() {

    open(SERIAL, $serialfile) || die "can't open $serialfile";
    seek(SERIAL, $serial_offset, 0);
    local $/;
    my $data = <SERIAL>;
    close(SERIAL);
    return $data;
}

=head2 wait_serial

wait_serial($regex, $timeout_sec, $expect_not_found)

Wait for a message to appear on serial output.
You could have sent it there earlier with

C<script_run("echo Hello World E<gt> /dev/$serialdev");>

=cut

sub wait_serial($$$) {

    # wait for a message to appear on serial output
    my ($regexp, $timeout, $expect_not_found) = @_;
    fctlog( 'wait_serial', "regex=$regexp", "timeout=$timeout" );
    my $res;
    my $str;
    for my $n ( 1 .. $timeout ) {
        $str = serial_text();
        if ( $str =~ m/$regexp/ ) {
            $res = 'ok';
            last;
        }
        sleep 1;
    }
    if ($expect_not_found) {
        if (defined $res) {
            $res = 'fail';
        }
        else {
            $res ||= 'ok';

        }
    }
    else {
        $res ||= 'fail';
    }
    set_serial_offset();

    current_test->record_serialresult( $regexp, $res );
    fctres( 'wait_serial', "$regexp: $res" );
    return $str if ($res eq "ok");
    return undef; # false
}

=head2 wait_idle

Wait until the system becomes idle

=cut

sub wait_idle($) {
    my $timeout = shift;
    my $prev;
    fctlog( 'wait_idle', "timeout=$timeout" );
    my $timesidle = 0;
    my $idlethreshold  = $vars{IDLETHRESHOLD};
    for my $n ( 1 .. $timeout ) {
        my ( $stat, $systemstat ) = $backend->cpu_stat();
        sleep 1;    # sleep before skip to timeout when having no data (hw)
        next unless $stat;
        $stat += $systemstat;
        if ($prev) {
            my $diff = $stat - $prev;
            diag("wait_idle $timesidle d=$diff");
            if ( $diff < $idlethreshold ) {
                if ( ++$timesidle > $timesidleneeded ) {    # idle for $x sec
                    #if($diff<2000000) # idle for one sec
                    fctres( 'wait_idle', "idle detected" );
                    return 1;
                }
            }
            else { $timesidle = 0 }
        }
        $prev = $stat;
    }
    fctres( 'wait_idle', "timed out after $timeout" );
    return 0;
}

sub save_needle_template($$$) {
    my ( $img, $mustmatch, $tags ) = @_;

    my $t = POSIX::strftime( "%Y%m%d_%H%M%S", gmtime() );

    # limit the filename
    $mustmatch = substr $mustmatch, 0, 30;
    my $imgfn  = result_dir() . "/template-$mustmatch-$t.png";
    my $jsonfn = result_dir() . "/template-$mustmatch-$t.json";

    my $template = {
        area => [
            {
                xpos   => 0,
                ypos   => 0,
                width  => $img->xres(),
                height => $img->yres(),
                type   => 'match',
                margin => 50,    # Search margin for the area.
            }
        ],
        tags => [@$tags],
    };

    $img->write_optimized($imgfn);

    open( my $fd, ">", $jsonfn ) or die "$jsonfn: $!\n";
    print $fd JSON->new->pretty->encode($template);
    close($fd);

    diag("wrote $jsonfn");

    return shared_clone( { img => $jsonfn, needle => $jsonfn, name => $mustmatch } );
}

sub assert_screen {
    my %args         = @_;
    my $mustmatch    = $args{'mustmatch'};
    my $timeout      = $args{'timeout'} || 30;
    my $check_screen = $args{'check'};

    die "current_test undefined" unless current_test;

    $args{'retried'} ||= 0;

    # get the array reference to all matching needles
    my $needles = [];
    my @tags;
    if ( ref($mustmatch) eq "ARRAY" ) {
        my @a = @$mustmatch;
        while ( my $n = shift @a ) {
            if ( ref($n) eq '' ) {
                push @tags, split( / /, $n );
                $n = needle::tags($n);
                push @a, @$n if $n;
                next;
            }
            unless ( ref($n) eq 'needle' && $n->{name} ) {
                warn "invalid needle passed <" . ref($n) . "> " . dump($n);
                next;
            }
            push @$needles, $n;
            push @tags, $n->{name};
        }
    }
    elsif ($mustmatch) {
        $needles = needle::tags($mustmatch) || [];
        @tags = ($mustmatch);
    }

    {    # remove duplicates
        my %h = map { $_ => 1 } @tags;
        @tags = sort keys %h;
    }
    $mustmatch = join('_', @tags);

    fctlog( 'assert_screen', "'$mustmatch'", "timeout=$timeout" );
    if ( !@$needles ) {
        diag("NO matching needles for $mustmatch");
    }
    my $img = getcurrentscreenshot();
    my $oldimg;
    my $old_search_ratio = 0;
    my $failed_candidates;
    for ( my $n = 0 ; $n < $timeout ; $n++ ) {
        my $search_ratio = 0.02;
        $search_ratio = 1 if ($n % 6 == 5) || ($n == $timeout - 1);

        if ( -e $control_files{"interactive_mode"} ) {
            $interactive_mode = 1;
        }
        if ( -e $control_files{"stop_waitforneedle"} ) {
            last;
        }
        my $statstr = get_cpu_stat();
        if ($oldimg) {
            sleep 1;
            $img = getcurrentscreenshot(1);
            if ( !$img ) {    # standstill. Save fail needle.
                $img = $oldimg;

                # not using last here so we search the
                # standstill image too, in case we
                # are in the post fail hook
                $n = $timeout;
            }
            elsif ( $oldimg == $img && $search_ratio <= $old_search_ratio) {    # no change, no need to search
                diag( sprintf( "no change %d $statstr", $timeout - $n ) );
                next;
            }
        }
        my $foundneedle;
        ( $foundneedle, $failed_candidates ) = $img->search($needles, 0, $search_ratio);
        if ($foundneedle) {
            current_test->record_screenmatch( $img, $foundneedle, \@tags );
            my $lastarea = $foundneedle->{'area'}->[-1];
            fctres( sprintf( "found %s, similarity %.2f @ %d/%d", $foundneedle->{'needle'}->{'name'}, $lastarea->{'similarity'}, $lastarea->{'x'}, $lastarea->{'y'} ) );
            return $foundneedle;
        }
        diag("STAT $statstr");
        $oldimg = $img;
        $old_search_ratio = $search_ratio;
    }

    fctres( 'assert_screen', "match=$mustmatch timed out after $timeout" );
    for ( @{ $needles || [] } ) {
        diag $_->{'file'};
    }

    my @save_tags = @tags;

    # add some known env variables
    for my $key (qw(VIDEOMODE DESKTOP DISTRI INSTLANG LIVECD LIVETEST OFW UEFI NETBOOT PROMO FLAVOR)) {
        push( @save_tags, "ENV-$key-" . $vars{$key} ) if $vars{$key};
    }

    if ( -e $control_files{"interactive_mode"} ) {
        $interactive_mode = 1;
        if ( !-e $control_files{'stop_waitforneedle'} ) {
            open( my $fd, '>', $control_files{'stop_waitforneedle'} );
            close $fd;
        }
    }
    else {
        $interactive_mode = 0;
    }
    $needle_template = save_needle_template( $img, $mustmatch, \@save_tags );

    if ($interactive_mode) {
        print "interactive mode entered\n";
        freeze_vm();

        current_test->record_screenfail(
            img     => $img,
            needles => $failed_candidates,
            tags    => \@save_tags,
            result  => $check_screen ? 'unk' : 'fail',
            # do not set overall here as the result will be removed later
        );

        $waiting_for_new_needle = 1;

        save_results();

        diag("$$: waiting for continuation");
        while ( -e $control_files{'stop_waitforneedle'} ) {
            if ( -e $control_files{'reload_needles_and_retry'} ) {
                unlink( $control_files{'stop_waitforneedle'} );
                last;
            }
            sleep 1;
        }
        diag("continuing");

        current_test->remove_last_result();

        if ( -e $control_files{'reload_needles_and_retry'} ) {
            unlink( $control_files{'reload_needles_and_retry'} );
            for my $n ( needle->all() ) {
                $n->unregister();
            }
            needle::init();
            $waiting_for_new_needle = undef;
            save_results();
            cont_vm();
            return assert_screen( mustmatch => \@tags, timeout => 3, check => $check_screen, retried => $args{'retried'} + 1 );
        }
        $waiting_for_new_needle = undef;
        save_results();
        cont_vm();
    }
    unlink( $control_files{'stop_waitforneedle'} )       if -e $control_files{'stop_waitforneedle'};
    unlink( $control_files{'reload_needles_and_retry'} ) if -e $control_files{'reload_needles_and_retry'};

    # beware of spaghetti code below
    my $newname;
    my $run_editor = 0;
    if ( $vars{'scaledhack'} ) {
        freeze_vm();
        my $needle;
        for my $cand ( @{ $failed_candidates || [] } ) {
            fctres( sprintf( "candidate %s, similarity %.2f @ %d/%d", $cand->{'needle'}->{'name'}, $cand->{'area'}->[-1]->{'similarity'}, $cand->{'area'}->[-1]->{'x'}, $cand->{'area'}->[-1]->{'y'} ) );
            $needle = $cand->{'needle'};
            last;
        }

        for my $i ( 1 .. @{ $needles || [] } ) {
            printf "%d - %s\n", $i, $needles->[ $i - 1 ]->{'name'};
        }
        print "note: called from check_screen()\n" if $check_screen;
        print "(E)dit, (N)ew, (Q)uit, (C)ontinue\n";
        my $r = <STDIN>;
        if ( $r =~ /^(\d+)/ ) {
            $r      = 'e';
            $needle = $needles->[ $1 - 1 ];
        }
        if ( $r =~ /^e/i ) {
            unless ($needle) {
                $needle = $needles->[0] if $needles;
                die "no needle\n" unless $needle;
            }
            $newname    = $needle->{'name'};
            $run_editor = 1;
        }
        elsif ( $r =~ /^n/i ) {
            $run_editor = 1;
        }
        elsif ( $r =~ /^q/i ) {
            $args{'retried'} = 99;
            $backend->send('cont');
        }
        else {
            $backend->send("cont");
        }
    }
    elsif ( !$check_screen && $vars{'interactive_crop'} ) {
        $run_editor = 1;
    }

    if ( $run_editor && $args{'retried'} < 3 ) {
        $newname = $mustmatch . ( $vars{'interactive_crop'} || '' ) unless $newname;
        freeze_vm();
        system( "$scriptdir/crop.py", '--new', $newname, $needle_template->{'needle'} ) == 0 || mydie;
        $backend->send("cont");
        my $fn = sprintf( "%s/needles/%s.json", $vars{'CASEDIR'}, $newname );
        if ( -e $fn ) {
            for my $n ( needle->all() ) {
                if ( $n->{'file'} eq $fn ) {
                    $n->unregister();
                }
            }
            diag("reading new needle $fn");
            needle->new($fn) || mydie "$!";

            # XXX: recursion!
            return assert_screen( mustmatch => \@tags, timeout => 3, check => $check_screen, retried => $args{'retried'} + 1 );
        }
    }

    current_test->record_screenfail(
        img     => $img,
        needles => $failed_candidates,
        tags    => \@save_tags,
        result  => $check_screen ? 'unk' : 'fail',
        overall => $check_screen ? undef : 'fail'
    );
    unless ( $args{'check'} ) {
        mydie "needle(s) '$mustmatch' not found";
    }
    return undef;
}

sub make_snapshot($) {
    my $sname = shift;
    diag("Creating a VM snapshot $sname");
    $backend->do_savevm($sname);
}

sub load_snapshot($) {
    my $sname = shift;
    diag("Loading a VM snapshot $sname");
    $backend->do_loadvm($sname);
    sleep(10);
}

# dump all info in one big file. Alternatively each test could write
# one file and we collect only the overall status.
sub save_results(;$$) {
    $testmodules = shift if @_;
    my $fn = shift || result_dir() . "/results.json";
    open( my $fd, ">", $fn ) or die "can not write results.json: $!\n";
    fcntl( $fd, F_SETLKW, pack( 'ssqql', F_WRLCK, 0, 0, 0, $$ ) ) or die "cannot lock results.json: $!\n";
    truncate( $fd, 0 ) or die "cannot truncate results.json: $!\n";
    my $result = {
        'distribution' => $vars{'DISTRI'},
        'version'      => $vars{'VERSION'} || '',
        'testmodules'  => $testmodules,
        'dents'        => 0,
    };
    if ( $ENV{'WORKERID'} ) {
        $result->{workerid}    = $ENV{WORKERID};
        $result->{interactive} = $interactive_mode ? 1 : 0;
        $result->{needinput}   = $waiting_for_new_needle ? 1 : 0;
        $result->{running}     = current_test ? ref(current_test) : '';
    }
    else {
        # if there are any important module only consider the
        # results of those.
        my @modules = grep { $_->{flags}->{important} } @$testmodules;
        # no important ones? => use all.
        @modules = @$testmodules unless @modules;
        for my $tr (@modules) {
            if ( $tr->{result} eq "ok" ) {
                $result->{overall} ||= 'ok';
            }
            else {
                $result->{overall} = 'fail';
            }
            $result->{dents}++ if $tr->{dents};
        }
        $result->{overall} ||= 'fail';
    }
    if ($backend) {
        $result->{backend} = $backend->get_info();
    }

    print $fd to_json( $result, { pretty => 1 } );
    close($fd);
}

#FIXME: new wait functions
# waitscreenactive - ($backend->screenactive())
# wait-time - like sleep but prints info to log
# wait-screen-(un)-active to catch reboot of hardware

# wait functions end

sub clean_control_files {
    for my $file ( values %control_files ) {
        unlink($file);
    }
}

1;

# vim: set sw=4 et:
