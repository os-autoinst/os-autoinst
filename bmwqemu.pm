# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package bmwqemu;

use strict;
use warnings;
use autodie ':all';

use Time::HiRes qw(sleep gettimeofday);
use IO::Socket;
use Fcntl ':flock';
use POSIX;
use Carp;
use Mojo::JSON;    # booleans
use Cpanel::JSON::XS ();
use File::Path 'remove_tree';
use Data::Dumper;
use Mojo::Log;
use File::Spec::Functions;
use Exporter 'import';
use POSIX 'strftime';
use Time::HiRes 'gettimeofday';

our $VERSION;
our @EXPORT    = qw(fileContent save_vars);
our @EXPORT_OK = qw(diag);

use backend::driver;
require IPC::System::Simple;

sub mydie;

$| = 1;


our $default_timeout      = 30;                        # assert timeout, 0 is a valid timeout
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
    '/usr/share/edk2/ovmf/OVMF_CODE.fd',       '/usr/share/OVMF/OVMF_CODE.fd'
);

our %vars;

sub load_vars {
    my $fn  = "vars.json";
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
    truncate($fd, 0)    or die "cannot truncate vars.json: $!\n";

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

sub result_dir {
    return "testresults";
}

our $gocrbin = "/usr/bin/gocr";

# set from isotovideo during initialization
our $scriptdir;

sub init_logger {
    if ($direct_output) {
        $logger = Mojo::Log->new(level => 'debug');
    }
    else {
        $logger = Mojo::Log->new(level => 'debug', path => catfile(result_dir, 'autoinst-log.txt'));
    }

    $logger->format(
        sub {
            my ($time, $level, @lines) = @_;
            # Unfortunately $time doesn't have the precision we want. So we need to use Time::HiRes
            $time = gettimeofday;
            return sprintf(strftime("[%FT%T.%%03d %Z] [$level] ", localtime($time)), 1000 * ($time - int($time))) . join("\n", @lines, '');

        });
}

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
    $vars{VNC}      ||= 90;
    # openQA already sets a random string we can reuse
    $vars{JOBTOKEN} ||= random_string(10);

    if ($gocrbin && !-x $gocrbin) {
        $gocrbin = undef;
    }
    if ($vars{SUSEMIRROR} && $vars{SUSEMIRROR} =~ s{^(\w+)://}{}) {    # strip & check proto
        if ($1 ne "http") {
            die "only http mirror URLs are currently supported but found '$1'.";
        }
    }

    die "CASEDIR variable not set, unknown test case directory" if !defined $vars{CASEDIR};
    die "No scripts in $vars{CASEDIR}"                          if !-e "$vars{CASEDIR}";
    _check_publish_vars();
    save_vars();
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

sub log_format_callback {
    my ($time, $level, @lines) = @_;
    # Unfortunately $time doesn't have the precision we want. So we need to use Time::HiRes
    $time = gettimeofday;
    return sprintf(strftime("[%FT%T.%%03d %Z] [$level] ", localtime($time)), 1000 * ($time - int($time))) . join("\n", @lines, '');
}

sub diag {
    my ($args) = @_;
    $logger = Mojo::Log->new(level => 'debug', format => \&log_format_callback) unless $logger;
    confess "missing input" unless $_[0];
    $logger->debug("@_");
    return;
}

sub fctres {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    $logger = Mojo::Log->new(level => 'debug', format => \&log_format_callback) unless $logger;
    $logger->debug(">>> $fname: $text");
    return;
}

sub fctinfo {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    $logger = Mojo::Log->new(level => 'debug', format => \&log_format_callback) unless $logger;
    $logger->info("::: $fname: $text");
    return;
}

sub fctwarn {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    $logger = Mojo::Log->new(level => 'debug', format => \&log_format_callback) unless $logger;
    $logger->warn("!!! $fname: $text");
    return;
}

sub modstart {
    $logger = Mojo::Log->new(level => 'debug', format => \&log_format_callback) unless $logger;
    $logger->debug("||| @{[join(' ', @_)]}");
    return;
}

use autotest '$current_test';
sub current_test {
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
    $logger = Mojo::Log->new(level => 'debug', format => \&log_format_callback) unless $logger;
    $logger->debug('<<< ' . $fname . "($params)");
    return;
}

sub fileContent {
    my ($fn) = @_;
    no autodie 'open';
    open(my $fd, "<", $fn) or return;
    local $/;
    my $result = <$fd>;
    close($fd);
    return $result;
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

sub hashed_string {
    fctwarn '@DEPRECATED: Use testapi::hashed_string instead';
    return testapi::hashed_string(@_);
}

sub wait_for_one_more_screenshot {
    # sleeping for one second should ensure that one more screenshot is taken
    # uncoverable subroutine
    # uncoverable statement
    sleep 1;
}

1;
