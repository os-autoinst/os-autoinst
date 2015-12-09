package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep gettimeofday);
use Digest::MD5;
use IO::Socket;

use ocr;
use cv;
use needle;
use threads;
use threads::shared;
use Thread::Queue;
use POSIX;
use Term::ANSIColor;
use Carp;
use JSON;
use File::Path qw(remove_tree);
use Data::Dumper;

use base 'Exporter';
use Exporter;

our $VERSION;
our @EXPORT = qw(diag fileContent save_vars);

use backend::driver;
require IPC::System::Simple;
use autodie qw(:all);

use distribution;

sub mydie;

$| = 1;

# shared vars

our $screenshotQueue = Thread::Queue->new();
our $default_timeout = 30;                     # assert timeout, 0 is a valid timeout
our $idle_timeout    = 19;                     # wait_idle 0 makes no sense
my $prestandstillwarning : shared = 0;

my @ocrrect;
share(@ocrrect);

our $interactive_mode;
our $needle_template;
our $waiting_for_new_needle;
our $screenshotpath = "qemuscreenshot";

# shared vars end

# list of files that are used to control the behavior
our %control_files = (
    "reload_needles_and_retry" => "reload_needles_and_retry",
    "interactive_mode"         => "interactive_mode",
    "stop_waitforneedle"       => "stop_waitforneedle",
);

# global vars

our $logfd;

our $clock_ticks = POSIX::sysconf(&POSIX::_SC_CLK_TCK);

our $istty;
our $direct_output;
our $timesidleneeded     = 1;
our $standstillthreshold = scale_timeout(600);

our %vars;

sub load_vars() {
    my $fn  = "vars.json";
    my $ret = {};
    local $/;
    open(my $fh, '<', $fn) or return 0;
    eval { $ret = JSON->new->relaxed->decode(<$fh>); };
    die                                  #
      "parse error in vars.json:\n" .    #
      "$@" if $@;
    close($fh);
    %vars = %{$ret};
    return;
}

sub save_vars() {
    my $fn = "vars.json";
    unlink "vars.json" if -e "vars.json";
    open(my $fd, ">", $fn);
    fcntl($fd, F_SETLKW, pack('ssqql', F_WRLCK, 0, 0, 0, $$)) or die "cannot lock vars.json: $!\n";
    truncate($fd, 0) or die "cannot truncate vars.json: $!\n";

    # make sure the JSON is sorted
    my $json = JSON->new->pretty->canonical;
    print $fd $json->encode(\%vars);
    close($fd);
    return;
}

share($vars{SCREENSHOTINTERVAL});    # to adjust at runtime

sub result_dir() {
    return "testresults";
}

our $gocrbin = "/usr/bin/gocr";

# set from isotovideo during initialization
our $scriptdir;

sub init {
    load_vars();

    # remove directories for asset upload
    remove_tree("assets_public");
    remove_tree("assets_private");

    remove_tree(result_dir);
    mkdir result_dir;
    mkdir join('/', result_dir, 'ulogs');

    if ($direct_output) {
        open($logfd, '>&STDERR');
    }
    else {
        open($logfd, ">", result_dir . "/autoinst-log.txt");
    }
    # set unbuffered so that send_key lines from main thread will be written
    my $oldfh = select($logfd);
    $| = 1;
    select($oldfh);

    cv::init();
    require tinycv;

    die "DISTRI undefined\n" . pp(\%vars) . "\n" unless $vars{DISTRI};

    unless ($vars{CASEDIR}) {
        my @dirs = ("$scriptdir/distri/$vars{DISTRI}");
        unshift @dirs, $dirs[-1] . "-" . $vars{VERSION} if ($vars{VERSION});
        for my $d (@dirs) {
            if (-d $d) {
                $vars{CASEDIR} = $d;
                last;
            }
        }
        die "can't determine test directory for $vars{DISTRI}\n" unless $vars{CASEDIR};
    }

    testapi::init();
    # set a default distribution if the tests don't have one
    $testapi::distri = distribution->new unless $testapi::distri;

    # defaults
    $vars{QEMUPORT}      ||= 15222;
    $vars{VNC}           ||= 90;
    $vars{INSTLANG}      ||= "en_US";
    $vars{IDLETHRESHOLD} ||= 18;
    # openQA already sets a random string we can reuse
    $vars{JOBTOKEN} ||= random_string(10);

    # FIXME: does not belong here
    if (defined($vars{DISTRI}) && $vars{DISTRI} eq 'archlinux') {
        $vars{HDDMODEL} = "ide";
    }

    save_vars();

    ## env vars end

    ## some var checks
    if (!-x $gocrbin) {
        $gocrbin = undef;
    }
    if ($vars{SUSEMIRROR} && $vars{SUSEMIRROR} =~ s{^(\w+)://}{}) {    # strip & check proto
        if ($1 ne "http") {
            die "only http mirror URLs are currently supported but found '$1'.";
        }
    }

}

## some var checks end

# global vars end

# local vars

our $backend;    #FIXME: make local after adding frontend-api to bmwqemu

# local vars end

# global/shared var set functions

sub set_ocr_rect {
    @ocrrect = @_;
    return;
}

# global/shared var set functions end

# util and helper functions

sub print_possibly_colored {
    my ($text, $color) = @_;

    if (($direct_output && !$istty) || !$direct_output) {
        $logfd && print $logfd "$text\n";
    }
    if ($istty || !$logfd) {
        if ($color) {
            print STDERR colored($text, $color) . "\n";
        }
        else {
            print STDERR "$text\n";
        }
    }
    return;
}

sub diag {
    print_possibly_colored "@_";
    return;
}

sub fctres {
    my $fname   = shift;
    my @fparams = @_;
    print_possibly_colored ">>> $fname: @fparams", 'green';
    return;
}

sub fctinfo {
    my $fname   = shift;
    my @fparams = @_;

    print_possibly_colored "::: $fname: @fparams", 'yellow';
    return;
}

sub fctwarn {
    my $fname   = shift;
    my @fparams = @_;

    print_possibly_colored "!!! $fname: @fparams", 'red';
    return;
}

sub modstart {
    my $text = sprintf "\n||| %s at %s", join(' ', @_), POSIX::strftime("%F %T", gmtime);
    print_possibly_colored $text, 'bold';
    return;
}

use autotest qw($current_test);
sub current_test() {
    return $autotest::current_test;
}

sub update_line_number() {
    return unless current_test;
    my $out    = "";
    my $ending = quotemeta(current_test->{script});
    for my $i (1 .. 10) {
        my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller($i);
        last unless $filename;
        next unless $filename =~ m/$ending$/;
        print "Debug: $filename:$line called $subroutine\n";
        last;
    }
    return;
}

# pretty print like Data::Dumper but without the "VAR1 = " prefix
sub pp {
    # FTR, I actually hate Data::Dumper.
    my $value_with_trailing_newline = Data::Dumper->new(\@_)->Terse(1)->Dump();
    chomp($value_with_trailing_newline);
    return $value_with_trailing_newline;
}

sub log_call {
    my $fname = shift;
    update_line_number();
    my @result;
    while (my ($key, $value) = splice(@_, 0, 2)) {
        push @result, join("=", $key, pp($value));
    }
    my $params = join(", ", @result);

    print_possibly_colored '<<< ' . $fname . "($params)", 'blue';
    return;
}

sub fileContent {
    my ($fn) = @_;
    no autodie qw(open);
    open(my $fd, "<", $fn) or return;
    local $/;
    my $result = <$fd>;
    close($fd);
    return $result;
}

our $lastscreenshot;
our $lastscreenshotName = '';
our $lastscreenshotTime;

sub getcurrentscreenshot {
    my ($undef_on_standstill) = @_;
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

    if ($filename && $lastscreenshotName ne $filename) {
        $lastscreenshot     = tinycv::read($filename);
        $lastscreenshotName = $filename;
        $lastscreenshotTime = time;
    }
    elsif (!$interactive_mode && !current_test->{post_fail_hook_running}) {
        my $numunchangedscreenshots = time - $lastscreenshotTime;
        $prestandstillwarning = ($numunchangedscreenshots > $standstillthreshold / 2);
        if ($numunchangedscreenshots > $standstillthreshold) {
            diag "STANDSTILL";
            return if $undef_on_standstill;

            current_test->standstill_detected($lastscreenshot);
            mydie "standstill detected. test ended";    # above 120s of autoreboot
        }
    }

    return $lastscreenshot;
}

# util and helper functions end

# backend management

sub init_backend {
    my ($name) = @_;
    $backend = backend::driver->new($name);
    return $backend;
}

sub start_vm() {
    return unless $backend;
    return $backend->start_vm();
}

sub stop_vm() {
    return unless $backend;
    my $ret = $backend->stop();
    if (!$direct_output && $logfd) {
        close $logfd;
        $logfd = undef;
    }
    return $ret;
}

sub freeze_vm() {
    # qemu specific - all other backends will crash
    return $backend->handle_qmp_command({"execute" => "stop"});
}

sub cont_vm() {
    return $backend->handle_qmp_command({"execute" => "cont"});
}

sub mydie {
    log_call('mydie', cause_of_death => \@_);
    croak "mydie";
}

sub alive() {
    if (defined $backend) {

        # backend will kill me when
        # backend.run has been deleted
        return $backend->alive();
    }
    return 0;
}

sub get_cpu_stat() {
    my $cpustats = $backend->cpu_stat();
    return 'unk' unless $cpustats;
    my ($statuser, $statsystem) = @$cpustats;
    my $statstr = '';
    if ($statuser) {
        for ($statuser, $statsystem) { $_ /= $clock_ticks }
        $statstr .= "statuser=$statuser ";
        $statstr .= "statsystem=$statsystem ";
    }
    return $statstr;
}

# runtime information gathering functions end


=head2 wait_idle

Wait until the system becomes idle

=cut

sub wait_idle {
    my ($timeout) = @_;
    $timeout ||= $idle_timeout;
    my $prev;
    my $timesidle     = 0;
    my $idlethreshold = $vars{IDLETHRESHOLD};

    $timeout = scale_timeout($timeout);

    for my $n (1 .. $timeout) {
        my ($stat, $systemstat) = @{$backend->cpu_stat()};
        sleep 1;    # sleep before skip to timeout when having no data (hw)
        next unless $stat;
        $stat += $systemstat;
        if ($prev) {
            my $diff = $stat - $prev;
            diag("wait_idle $timesidle d=$diff");
            if ($diff < $idlethreshold) {
                if (++$timesidle > $timesidleneeded) {    # idle for $x sec
                                                          #if($diff<2000000) # idle for one sec
                    fctres('wait_idle', "idle detected");
                    return 1;
                }
            }
            else { $timesidle = 0 }
        }
        $prev = $stat;
    }
    fctres('wait_idle', "timed out after $timeout");
    return 0;
}

sub save_needle_template {
    my ($img, $mustmatch, $tags) = @_;

    my $t = POSIX::strftime("%Y%m%d_%H%M%S", gmtime());

    # limit the filename
    $mustmatch = substr $mustmatch, 0, 30;
    my $imgfn  = result_dir . "/template-$mustmatch-$t.png";
    my $jsonfn = result_dir . "/template-$mustmatch-$t.json";

    my $template = {
        area => [
            {
                xpos   => 0,
                ypos   => 0,
                width  => $img->xres(),
                height => $img->yres(),
                type   => 'match',
                margin => 50,             # Search margin for the area.
            }
        ],
        tags       => [@$tags],
        properties => [],
    };

    $img->write($imgfn);

    open(my $fd, ">", $jsonfn);
    print $fd JSON->new->pretty->encode($template);
    close($fd);

    diag("wrote $jsonfn");

    return shared_clone({img => $jsonfn, needle => $jsonfn, name => $mustmatch});
}

sub assert_screen {
    my %args         = @_;
    my $mustmatch    = $args{mustmatch};
    my $timeout      = $args{timeout} // $default_timeout;
    my $check_screen = $args{check};

    $timeout = scale_timeout($timeout);

    die "current_test undefined" unless current_test;

    # get the array reference to all matching needles
    my $needles = [];
    my @tags;
    if (ref($mustmatch) eq "ARRAY") {
        my @a = @$mustmatch;
        while (my $n = shift @a) {
            if (ref($n) eq '') {
                push @tags, split(/ /, $n);
                $n = needle::tags($n);
                push @a, @$n if $n;
                next;
            }
            unless (ref($n) eq 'needle' && $n->{name}) {
                warn "invalid needle passed <" . ref($n) . "> " . pp($n);
                next;
            }
            push @$needles, $n;
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

    if (!@$needles) {
        diag("NO matching needles for $mustmatch");
    }

    # we keep a collection of mismatched screens
    my $failed_screens = [];

    my $img = getcurrentscreenshot();
    my $oldimg;
    my $old_search_ratio = 0;
    my $failed_candidates;
    for (my $n = $timeout; $n >= 0; $n--) {
        my $search_ratio = 0.02;
        $search_ratio = 1 if ($n % 6 == 5) || ($n == 0);

        if (-e $control_files{"interactive_mode"}) {
            if (!$interactive_mode) {
                diag("interactive mode enabled");
                $interactive_mode = 1;
                save_status();
            }
        }
        elsif ($interactive_mode) {
            diag("interactive mode disabled");
            $interactive_mode = 0;
            save_status();
        }
        if (-e $control_files{stop_waitforneedle}) {
            last;
        }
        my $statstr = get_cpu_stat();
        if ($oldimg) {
            sleep 1;
            $img = getcurrentscreenshot(1);
            if (!$img) {    # standstill. Save fail needle.
                $img = $oldimg;

                # not using last here so we search the
                # standstill image too, in case we
                # are in the post fail hook
                $n = -1;
            }
            elsif ($oldimg == $img && $search_ratio <= $old_search_ratio) {    # no change, no need to search
                diag(sprintf("no change %d $statstr", $n));
                next;
            }
        }
        my $foundneedle;
        ($foundneedle, $failed_candidates) = $img->search($needles, 0, $search_ratio);
        if ($foundneedle) {
            current_test->record_screenmatch($img, $foundneedle, \@tags, $failed_candidates);
            my $lastarea = $foundneedle->{area}->[-1];
            fctres(sprintf("found %s, similarity %.2f @ %d/%d", $foundneedle->{needle}->{name}, $lastarea->{similarity}, $lastarea->{x}, $lastarea->{y}));
            return $foundneedle;
        }

        if ($search_ratio == 1) {
            # save only failures where the whole screen has been searched
            # results of partial searching are rather confusing

            # as the images create memory pressure, we only save quite different images
            # the last screen is handled automatically and the first needle is only interesting
            # if there are no others
            my $sim = 29;
            if ($failed_screens->[-1] && $n > 0) {
                $sim = $failed_screens->[-1]->[0]->similarity($img);
            }
            if ($sim < 30) {
                push(@$failed_screens, [$img, $failed_candidates, $n, $sim]);
            }
            # clean up every once in a while to avoid excessive memory consumption.
            # The value here is an arbitrary limit.
            if (@$failed_screens > 60) {
                _reduce_to_biggest_changes($failed_screens, 20);
            }
            diag("STAT $n $statstr - similarity: $sim");
        }
        $oldimg           = $img;
        $old_search_ratio = $search_ratio;
    }

    fctres('assert_screen', "match=$mustmatch timed out after $timeout");
    for (@{$needles || []}) {
        diag $_->{file};
    }

    if (-e $control_files{"interactive_mode"}) {
        $interactive_mode = 1;
        if (!-e $control_files{stop_waitforneedle}) {
            open(my $fd, '>', $control_files{stop_waitforneedle});
            close $fd;
        }
    }
    else {
        $interactive_mode = 0;
    }
    $needle_template = save_needle_template($img, $mustmatch, \@tags);

    if ($interactive_mode) {
        freeze_vm();

        current_test->record_screenfail(
            img     => $img,
            needles => $failed_candidates,
            tags    => \@tags,
            result  => $check_screen ? 'unk' : 'fail',
            # do not set overall here as the result will be removed later
        );

        $waiting_for_new_needle = 1;

        save_status();
        current_test->save_test_result();

        diag("interactive mode waiting for continuation");
        while (-e $control_files{stop_waitforneedle}) {
            if (-e $control_files{reload_needles_and_retry}) {
                unlink($control_files{stop_waitforneedle});
                last;
            }
            sleep 1;
        }
        diag("continuing");

        current_test->remove_last_result();

        if (-e $control_files{reload_needles_and_retry}) {
            unlink($control_files{reload_needles_and_retry});
            for my $n (needle->all()) {
                $n->unregister();
            }
            needle::init();
            $waiting_for_new_needle = undef;
            save_status();
            cont_vm();
            return assert_screen(mustmatch => \@tags, timeout => 3, check => $check_screen);
        }
        $waiting_for_new_needle = undef;
        save_status();
        cont_vm();
    }
    unlink($control_files{stop_waitforneedle})       if -e $control_files{stop_waitforneedle};
    unlink($control_files{reload_needles_and_retry}) if -e $control_files{reload_needles_and_retry};

    my $final_mismatch = $failed_screens->[-1];
    if (!$check_screen) {
        _reduce_to_biggest_changes($failed_screens, 20);
        # only append the last mismatch if it's different to the last one in the reduced list
        my $new_final = $failed_screens->[-1];
        if ($new_final != $final_mismatch) {
            my $sim = $new_final->[0]->similarity($final_mismatch->[0]);
            print "FINAL SIM $sim\n";
            push(@$failed_screens, $final_mismatch) if ($sim < 50);
        }
    }
    else {
        $failed_screens = [$final_mismatch];
    }

    for my $l (@$failed_screens) {
        my ($img, $failed_candidates, $testtime, $similarity) = @$l;
        print "SAVING $testtime $similarity\n";
        my $result = $check_screen ? 'unk' : 'fail';
        $result = 'unk' if ($l != $final_mismatch);
        current_test->record_screenfail(
            img     => $img,
            needles => $failed_candidates,
            tags    => \@tags,
            result  => $result,
            overall => $check_screen ? undef : 'fail'
        );
    }

    unless ($args{check}) {
        mydie "needle(s) '$mustmatch' not found";
    }
    return;
}

sub _reduce_to_biggest_changes {
    my ($imglist, $limit) = @_;

    return if @$imglist <= $limit;

    diag("shrinking imglist " . $#$imglist);
    diag("sim " . join(' ', map { sprintf("%4.2f", $_->[3]) } @$imglist));

    my $first = shift @$imglist;
    @$imglist = (sort { $b->[3] <=> $a->[3] } @$imglist)[0 .. (@$imglist > $limit ? $limit - 1 : $#$imglist)];
    unshift @$imglist, $first;

    diag("imglist now " . $#$imglist);

    # now sort for test time
    @$imglist = sort { $b->[2] <=> $a->[2] } @$imglist;

    # recalculate similarity
    for (my $i = 1; $i < @$imglist; ++$i) {
        $imglist->[$i]->[3] = $imglist->[$i - 1]->[0]->similarity($imglist->[$i]->[0]);
    }

    diag("sim " . join(' ', map { sprintf("%4.2f", $_->[3]) } @$imglist));
    return;
}

sub make_snapshot {
    my ($sname) = @_;
    diag("Creating a VM snapshot $sname");
    return $backend->do_savevm({name => $sname});
}

sub load_snapshot {
    my ($sname) = @_;
    diag("Loading a VM snapshot $sname");
    return $backend->do_loadvm({name => $sname});
}

# store the obj as json into the given filename
sub save_json_file {
    my ($result, $fn) = @_;

    open(my $fd, ">", "$fn.new");
    print $fd to_json($result, {pretty => 1});
    close($fd);
    return rename("$fn.new", $fn);
}

sub save_status {
    my $result = {};
    $result->{interactive} = $interactive_mode       ? 1                 : 0;
    $result->{needinput}   = $waiting_for_new_needle ? 1                 : 0;
    $result->{running}     = current_test            ? ref(current_test) : '';
    $result->{backend} = $backend->get_info() if $backend;

    return save_json_file($result, result_dir . "/status.json");
}

#FIXME: new wait functions
# wait-time - like sleep but prints info to log
# wait-screen-(un)-active to catch reboot of hardware

# wait functions end

sub clean_control_files {
    no autodie qw(unlink);    # control files might not exist
    for my $file (values %control_files) {
        unlink($file);
    }
    return;
}

sub scale_timeout {
    my ($timeout) = @_;
    return $timeout * ($vars{TIMEOUT_SCALE} // 1);
}

# just a random string useful for pseudo security or temporary files
sub random_string {
    my ($count) = @_;
    $count //= 4;
    my $string;
    my @chars = ('a' .. 'z', 'A' .. 'Z');
    $string .= $chars[rand @chars] for 1 .. $count;
    return $string;
}

1;

# vim: set sw=4 et:
