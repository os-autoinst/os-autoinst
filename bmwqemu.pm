# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package bmwqemu;

use Mojo::Base -strict, -signatures;
use autodie ':all';
use Fcntl ':flock';
use Time::HiRes qw(sleep);
use IO::Socket;
use Carp;
use Mojo::JSON qw(encode_json);
use Cpanel::JSON::XS ();
use File::Path 'remove_tree';
use Data::Dumper;
use Mojo::Log;
use Mojo::File qw(path);
use Term::ANSIColor;

use Exporter 'import';

our $VERSION;
our @EXPORT_OK = qw(diag fctres fctinfo fctwarn modstate save_vars);

require IPC::System::Simple;
use log;

sub mydie;

$| = 1;


our $default_timeout = 30;    # assert timeout, 0 is a valid timeout
our $openqa_default_share = '/var/lib/openqa/share';

my @ocrrect;

our $screenshotpath = "qemuscreenshot";

# global vars

# Known locations of OVMF (UEFI) firmware: first is openSUSE, second is
# the kraxel.org nightly packages, third is Fedora's edk2-ovmf package,
# fourth is Debian's ovmf package.
our @ovmf_locations = (
    '/usr/share/qemu/ovmf-x86_64-ms-code.bin', '/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd',
    '/usr/share/edk2/ovmf/OVMF_CODE.fd', '/usr/share/OVMF/OVMF_CODE.fd'
);

our %vars;
tie %vars, 'bmwqemu::tiedvars', %vars;

sub result_dir () { 'testresults' }

# deprecated functions, moved to log module
{
    no warnings 'once';
    *log_format_callback = \&log::log_format_callback;
    *diag = \&log::diag;
    *fctres = \&log::fctres;
    *fctinfo = \&log::fctinfo;
    *fctwarn = \&log::fctwarn;
    *modstate = \&log::modstate;
    *logger = \&log::logger;
    *init_logger = \&log::init_logger;
}

use constant STATE_FILE => 'base_state.json';

# Write a JSON representation of the process termination to disk
sub serialize_state (%state) {
    bmwqemu::fctwarn($state{msg}) if delete $state{error};
    bmwqemu::diag($state{msg}) if delete $state{log};
    return undef if -e STATE_FILE;
    eval { path(STATE_FILE)->spew(encode_json(\%state)) };
    bmwqemu::diag("Unable to serialize fatal error: $@") if $@;
}

sub load_vars () {
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

sub save_vars (%args) {
    my $fn = "vars.json";
    unlink "vars.json" if -e "vars.json";
    open(my $fd, ">", $fn);
    flock($fd, LOCK_EX) or die "cannot lock vars.json: $!\n";
    truncate($fd, 0) or die "cannot truncate vars.json: $!\n";

    my $write_vars = \%vars;
    if ($args{no_secret}) {
        $write_vars = {};
        $write_vars->{$_} = $vars{$_} for (grep !/(^_SECRET_|_PASSWORD)/, keys(%vars));
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

sub init () {
    load_vars();

    $vars{BACKEND} ||= "qemu";

    # remove directories for asset upload
    remove_tree("assets_public");
    remove_tree("assets_private");

    remove_tree(result_dir);
    mkdir result_dir;
    mkdir join('/', result_dir, 'ulogs');

    log::init_logger;
}

sub _check_publish_vars () {
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

sub ensure_valid_vars () {
    # defaults
    $vars{QEMUPORT} ||= 15222;
    $vars{VNC} ||= 90;
    # openQA already sets a random string we can reuse
    $vars{JOBTOKEN} ||= random_string(10);

    if ($gocrbin && !-x $gocrbin) {
        $gocrbin = undef;
    }

    die "CASEDIR variable not set, unknown test case directory" if !defined $vars{CASEDIR};
    die "No scripts in CASEDIR '$vars{CASEDIR}'\n" unless -e $vars{CASEDIR};
    die "WHEELS_DIR '$vars{WHEELS_DIR}' does not exist" if defined $vars{WHEELS_DIR} && !-d $vars{WHEELS_DIR};
    _check_publish_vars();
    save_vars();
}

## some var checks end

# global vars end

# local vars

our $backend;

# local vars end

# util and helper functions

sub current_test () {
    require autotest;
    no warnings 'once';
    return $autotest::current_test;
}

sub update_line_number () {
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
    log::logger->debug(join(' -> ', @out));
    return;
}

# pretty print like Data::Dumper but without the "VAR1 = " prefix
sub pp (@args) {
    # FTR, I actually hate Data::Dumper.
    my $value_with_trailing_newline = Data::Dumper->new(\@args)->Terse(1)->Useqq(1)->Dump();
    chomp($value_with_trailing_newline);
    return $value_with_trailing_newline;
}

# Use special argument `-masked` to hide the given value in log output.
# It can be specified multiple times and or the value can be a ARRAY_REF or
# scalar.
sub log_call (@args) {
    my $fname = (caller(1))[3];
    update_line_number();

    # extract -masked parameter out of argument list
    my @masked;
    my @effective_args;
    while (@args) {
        my $v = shift @args;
        if (defined($v) && $v eq '-masked' && @args) {
            my $mval = shift @args;
            push @masked, ref($mval) eq 'ARRAY' ? @$mval : $mval;
        } else {
            push @effective_args, $v;
        }
    }

    my $params;
    if (@effective_args == 1) {
        $params = pp($effective_args[0]);
    }
    else {
        # key/value pairs
        my @result;
        while (my ($key, $value) = splice(@effective_args, 0, 2)) {
            if ($key =~ tr/0-9a-zA-Z_//c) {
                # only quote if needed
                $key = pp($key);
            }
            push @result, join("=", $key, pp($value));
        }
        $params = join(", ", @result);
    }

    foreach (@masked) {
        my $mask = pp($_);
        $mask =~ s/^"(.*)"$/$1/;
        $params =~ s/\Q$mask\E/[masked]/g;
    }

    log::logger->debug('<<< ' . $fname . "($params)");
    return;
}

# util and helper functions end

# backend management

sub stop_vm () {
    return unless $backend;
    my $ret = $backend->stop();
    return $ret;
}

sub mydie ($cause_of_death) {
    log_call(cause_of_death => $cause_of_death);
    croak "mydie";
}

# runtime information gathering functions end


# store the obj as json into the given filename
sub save_json_file ($result, $fn) {
    open(my $fd, ">", "$fn.new");
    my $json = eval { Cpanel::JSON::XS->new->utf8->pretty->canonical->encode($result) };
    if (my $err = $@) {
        my $dump = Data::Dumper->Dump([$result], ['result']);
        croak "Cannot encode input: $@\n$dump";
    }
    print $fd $json;
    close($fd);
    return rename("$fn.new", $fn);
}

sub scale_timeout ($timeout) {
    return $timeout * ($vars{TIMEOUT_SCALE} // 1);
}

=head2 random_string

  random_string([$count]);

Just a random string useful for pseudo security or temporary files.
=cut
sub random_string ($count) {
    $count //= 4;
    my $string;
    my @chars = ('a' .. 'z', 'A' .. 'Z');
    $string .= $chars[rand @chars] for 1 .. $count;
    return $string;
}

# sleeping for one second should ensure that one more screenshot is taken
sub wait_for_one_more_screenshot () { sleep 1 }

package bmwqemu::tiedvars;
use Tie::Hash;
use base qw/ Tie::StdHash /;    # no:style prevent style warning regarding use of Mojo::Base and base in this file
use Carp 'croak';

sub TIEHASH ($class, %args) {
    my $self = bless {
        data => {%args},
    }, $class;
}

sub STORE ($self, $key, $val) {
    croak("Settings key '$key' is invalid (check your test settings)") unless $key =~ m/^(?:[A-Z0-9_]+)\z/;
    $self->{data}->{$key} = $val;
}

sub FIRSTKEY ($self) {
    my $data = $self->{data};
    my @k = keys %$data;    # reset
    my $next = each %$data;
}

sub NEXTKEY ($self, $last) {
    my $data = $self->{data};
    my $next = each %$data;
}

sub FETCH ($self, $key) {
    my $val = $self->{data}->{$key};
}

sub DELETE ($self, $key) { delete $self->{data}->{$key} }

sub EXISTS ($self, $key) { exists $self->{data}->{$key} }

sub CLEAR ($self) { $self->{data} = {} }

sub SCALAR ($self) { scalar %{$self->{data}} }

1;
