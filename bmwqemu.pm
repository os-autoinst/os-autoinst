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

our $default_timeout = 30;    # assert timeout, 0 is a valid timeout
our $idle_timeout    = 19;    # wait_idle 0 makes no sense
my $prestandstillwarning : shared = 0;

my @ocrrect;
share(@ocrrect);

our $interactive_mode;
our $waiting_for_new_needle;
our $screenshotpath = "qemuscreenshot";

# shared vars end

# list of files that are used to control the behavior
our %control_files = (
    reload_needles_and_retry => "reload_needles_and_retry",
    interactive_mode         => "interactive_mode",
    stop_waitforneedle       => "stop_waitforneedle",
);

# global vars

our $logfd;

our $istty;
our $direct_output;
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
    $vars{QEMUPORT} ||= 15222;
    $vars{VNC}      ||= 90;
    $vars{INSTLANG} ||= "en_US";
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

sub update_line_number {
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


# runtime information gathering functions end


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
