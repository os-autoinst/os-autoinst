# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
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

use strictures;
use autodie ':all';
use Time::HiRes qw(sleep);
use Fcntl ':flock';
use common 'result_dir';
use log;

use Exporter 'import';

our $VERSION;
our @EXPORT_OK = qw(save_vars);

$| = 1;

our $default_timeout      = 30;                        # assert timeout, 0 is a valid timeout
our $openqa_default_share = '/var/lib/openqa/share';

my @ocrrect;

our $screenshotpath = "qemuscreenshot";

# global vars

# Known locations of OVMF (UEFI) firmware: first is openSUSE, second is
# the kraxel.org nightly packages, third is Fedora's edk2-ovmf package,
# fourth is Debian's ovmf package.
our @ovmf_locations = (
    '/usr/share/qemu/ovmf-x86_64-ms-code.bin', '/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd',
    '/usr/share/edk2/ovmf/OVMF_CODE.fd',       '/usr/share/OVMF/OVMF_CODE.fd'
);

our %vars;

use constant STATE_FILE => 'base_state.json';

# Write a JSON representation of the process termination to disk
sub serialize_state {
    my $state = {@_};
    log::diag($state->{msg}) if delete $state->{log};
    return undef             if -e STATE_FILE;
    eval { Mojo::File->new(STATE_FILE)->spurt(encode_json($state)); };
    log::diag("Unable to serialize fatal error: $@") if $@;
}

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

our $gocrbin = "/usr/bin/gocr";

# set from isotovideo during initialization
our $scriptdir;

sub init {
    load_vars();

    $vars{BACKEND} ||= "qemu";

    # remove directories for asset upload
    remove_tree("assets_public");
    remove_tree("assets_private");

    remove_tree(common::result_dir);
    mkdir common::result_dir;
    mkdir join('/', common::result_dir, 'ulogs');

    log::init_logger;
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

our $backend;

# local vars end

# backend management

sub stop_vm {
    return unless $backend;
    my $ret = $backend->stop();
    return $ret;
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

sub wait_for_one_more_screenshot {
    # sleeping for one second should ensure that one more screenshot is taken
    # uncoverable subroutine
    # uncoverable statement
    sleep 1;
}

1;
