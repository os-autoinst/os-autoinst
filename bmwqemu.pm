# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package bmwqemu;

use Mojo::Base -strict;
use autodie ':all';
use Fcntl ':flock';
use Time::HiRes qw(sleep);
use IO::Socket;
use POSIX;
use Carp;
use Mojo::JSON qw(encode_json);
use Cpanel::JSON::XS ();
use File::Path 'remove_tree';
use Data::Dumper;
use Mojo::Log;
use Mojo::File qw(path);
use Time::Moment;
use Term::ANSIColor;
use YAML::PP;

use Exporter 'import';

our $VERSION;
our @EXPORT_OK = qw(diag fctres fctinfo fctwarn modstate save_vars);

use backend::driver;
require IPC::System::Simple;

sub mydie;

$| = 1;


our $default_timeout = 30;    # assert timeout, 0 is a valid timeout
our $openqa_default_share = '/var/lib/openqa/share';

my @ocrrect;

our $screenshotpath = "qemuscreenshot";

# global vars

our $logger;

our $direct_output;

# Known locations of OVMF (UEFI) firmware: first is openSUSE, second is
# the kraxel.org nightly packages, third is Fedora's edk2-ovmf package,
# fourth is Debian's ovmf package.
our @ovmf_locations = (
    '/usr/share/qemu/ovmf-x86_64-ms-code.bin', '/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd',
    '/usr/share/edk2/ovmf/OVMF_CODE.fd', '/usr/share/OVMF/OVMF_CODE.fd'
);

our %vars;
tie %vars, 'bmwqemu::tiedvars', %vars;

sub result_dir { 'testresults' }

sub logger { $logger //= Mojo::Log->new(level => 'debug', format => \&log_format_callback) }

sub init_logger { logger->path(path(result_dir, 'autoinst-log.txt')) unless $direct_output }

use constant STATE_FILE => 'base_state.json';

# Write a JSON representation of the process termination to disk
sub serialize_state {
    my $state = {@_};
    bmwqemu::fctwarn($state->{msg}) if delete $state->{error};
    bmwqemu::diag($state->{msg}) if delete $state->{log};
    return undef if -e STATE_FILE;
    eval { Mojo::File->new(STATE_FILE)->spurt(encode_json($state)); };
    bmwqemu::diag("Unable to serialize fatal error: $@") if $@;
}

sub load_vars {
    my $fn = "vars.json";
    my $ret = {};
    local $/;
    my $fh;
    eval { open($fh, '<', $fn) };
    return 0 if $@;
    eval { $ret = Cpanel::JSON::XS->new->relaxed->decode(<$fh>); };
    die "parse error in vars.json:\n$@" if $@;
    close($fh);
    %vars = %{$ret};
    return;
}

sub save_vars {
    my (%args) = @_;
    my $fn = "vars.json";
    unlink "vars.json" if -e "vars.json";
    open(my $fd, ">", $fn);
    flock($fd, LOCK_EX) or die "cannot lock vars.json: $!\n";
    truncate($fd, 0) or die "cannot truncate vars.json: $!\n";

    my $write_vars = \%vars;
    if ($args{no_secret}) {
        $write_vars = {};
        $write_vars->{$_} = $vars{$_} for (grep !/^_SECRET_/, keys(%vars));
    }

    # make sure the JSON is sorted
    my $json = Cpanel::JSON::XS->new->pretty->canonical;
    print $fd $json->encode($write_vars);
    close($fd);
    return;
}

our $gocrbin = "/usr/bin/gocr";

# set from isotovideo during initialization
our $scriptdir;

sub init {
    load_vars();

    $vars{BACKEND} ||= "qemu";

    # remove directories for asset upload
    remove_tree("assets_public");
    remove_tree("assets_private");

    remove_tree(result_dir);
    mkdir result_dir;
    mkdir join('/', result_dir, 'ulogs');

    init_logger;
}

sub _check_publish_vars {
    return 0 unless my $nd = $vars{NUMDISKS};
    my @hdds = map { $vars{"HDD_$_"} } 1 .. $nd;
    for my $i (1 .. $nd) {
        for my $type (qw(STORE PUBLISH FORCE_PUBLISH)) {
            my $name = $type . "_HDD_$i";
            next unless my $out = $vars{$name};
            die "HDD_$i also specified in $name. This is not supported" if grep { $_ && $_ eq $out } @hdds;
        }
    }
    return 1;
}

sub ensure_valid_vars {
    # defaults
    $vars{QEMUPORT} ||= 15222;
    $vars{VNC} ||= 90;
    # openQA already sets a random string we can reuse
    $vars{JOBTOKEN} ||= random_string(10);

    if ($gocrbin && !-x $gocrbin) {
        $gocrbin = undef;
    }

    die "CASEDIR variable not set, unknown test case directory" if !defined $vars{CASEDIR};
    die "No scripts in $vars{CASEDIR}" if !-e "$vars{CASEDIR}";
    _check_publish_vars();
    save_vars();
}

## some var checks end

# global vars end

# local vars

our $backend;

# local vars end

# util and helper functions

sub log_format_callback {
    my ($time, $level, @items) = @_;

    my $lines = join("\n", @items, '');

    # ensure indentation for multi-line output
    $lines =~ s/(?<!\A)^/  /gm;

    return '[' . Time::Moment->now . "] [$level] " . $lines;
}

sub diag {
    my ($args) = @_;
    confess "missing input" unless $_[0];
    logger->append(color('white'));
    logger->debug(@_)->append(color('reset'));
    return;
}

sub fctres {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    logger->append(color('green'));
    logger->debug(">>> $fname: $text")->append(color('reset'));
    return;
}

sub fctinfo {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    logger->append(color('yellow'));
    logger->info("::: $fname: $text")->append(color('reset'));
    return;
}

sub fctwarn {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    logger->append(color('red'));
    logger->warn("!!! $fname: $text")->append(color('reset'));
    return;
}

sub modstate {
    logger->append(color('bold blue'));
    logger->debug("||| @{[join(' ', @_)]}")->append(color('reset'));
    return;
}

sub current_test {
    require autotest;
    return $autotest::current_test;
}

sub update_line_number {
    return unless current_test;
    return unless current_test->{script};
    my @out;
    my $casedir = $vars{CASEDIR} // '';
    for (my $i = 10; $i > 0; $i--) {
        my ($package, $filename, $line, $subroutine) = caller($i);
        next unless $filename && $filename =~ /\Q$casedir/;
        $filename =~ s@$casedir/?@@;
        push @out, "$filename:$line called $subroutine";
    }
    $logger->debug(join(' -> ', @out));
    return;
}

# pretty print like Data::Dumper but without the "VAR1 = " prefix
sub pp {
    # FTR, I actually hate Data::Dumper.
    my $value_with_trailing_newline = Data::Dumper->new(\@_)->Terse(1)->Useqq(1)->Dump();
    chomp($value_with_trailing_newline);
    return $value_with_trailing_newline;
}

sub log_call {
    my $fname = (caller(1))[3];
    update_line_number();
    my $params;
    if (@_ == 1) {
        $params = pp($_[0]);
    }
    else {
        # key/value pairs
        my @result;
        while (my ($key, $value) = splice(@_, 0, 2)) {
            if ($key =~ tr/0-9a-zA-Z_//c) {
                # only quote if needed
                $key = pp($key);
            }
            push @result, join("=", $key, pp($value));
        }
        $params = join(", ", @result);
    }
    logger->debug('<<< ' . $fname . "($params)");
    return;
}

# util and helper functions end

# backend management

sub stop_vm {
    return unless $backend;
    my $ret = $backend->stop();
    return $ret;
}

sub mydie {
    my ($cause_of_death) = @_;
    log_call(cause_of_death => $cause_of_death);
    croak "mydie";
}

# runtime information gathering functions end

# store the obj as json into the given filename
sub save_json_file {
    my ($result, $fn) = @_;
    open(my $fd, ">", "$fn.new");
    my $json = Cpanel::JSON::XS->new->pretty->canonical->encode($result);
    print $fd $json;
    close($fd);
    return rename("$fn.new", $fn);
}

=head2 save_yaml_file

  save_yaml_file($yaml, $filename);

Load YAML string and save the data as YAML into the given filename.
Also validate YAML string.

=cut

sub save_yaml_file {
    my ($yaml, $filename) = @_;
    my $yp = YAML::PP->new;
    my $data = $yp->load_string($yaml);
    $yp->dump_file("$filename.new", $data);
    return rename("$filename.new", $filename);
}

sub scale_timeout {
    my ($timeout) = @_;
    return $timeout * ($vars{TIMEOUT_SCALE} // 1);
}

=head2 random_string

  random_string([$count]);

Just a random string useful for pseudo security or temporary files.
=cut
sub random_string {
    my ($count) = @_;
    $count //= 4;
    my $string;
    my @chars = ('a' .. 'z', 'A' .. 'Z');
    $string .= $chars[rand @chars] for 1 .. $count;
    return $string;
}

sub wait_for_one_more_screenshot {
    # sleeping for one second should ensure that one more screenshot is taken
    # uncoverable subroutine
    # uncoverable statement
    sleep 1;
}

package bmwqemu::tiedvars;
use Tie::Hash;
use base qw/ Tie::StdHash /;
use Carp ();

sub TIEHASH {
    my ($class, %args) = @_;
    my $self = bless {
        data => {%args},
    }, $class;
}

sub STORE {
    my ($self, $key, $val) = @_;
    warn Carp::longmess "Settings key '$key' is invalid" unless $key =~ m/^(?:[A-Z0-9_]+)\z/;
    $self->{data}->{$key} = $val;
}

sub FIRSTKEY {
    my ($self) = @_;
    my $data = $self->{data};
    my @k = keys %$data;    # reset
    my $next = each %$data;
}

sub NEXTKEY {
    my ($self, $last) = @_;
    my $data = $self->{data};
    my $next = each %$data;
}

sub FETCH {
    my ($self, $key) = @_;
    my $val = $self->{data}->{$key};
}

sub DELETE {
    my ($self, $key) = @_;
    delete $self->{data}->{$key};
}

sub EXISTS {
    my ($self, $key) = @_;
    return exists $self->{data}->{$key};
}

sub CLEAR {
    my ($self) = @_;
    $self->{data} = {};
}

sub SCALAR {
    my ($self) = @_;
    return scalar %{$self->{data}};
}

1;
