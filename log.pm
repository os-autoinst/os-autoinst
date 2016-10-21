# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2016 SUSE LLC
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

package log;
use strict;
use warnings;
use Time::HiRes qw(sleep gettimeofday);
use autotest qw($current_test);
use POSIX;
use Carp;
use bmwqemu qw(result_dir);

use base 'Exporter';
use Exporter;

our $VERSION;
our @EXPORT = qw(diag);


# global vars

our $logfd;
our $istty;
our $direct_output;


sub init {
    if ($direct_output) {
        open($logfd, '>&STDERR');
    }
    else {
        open($logfd, ">", bmwqemu::result_dir() . "/autoinst-log.txt");
    }
    # set unbuffered so that send_key lines from main thread will be written
    my $oldfh = select($logfd);
    $| = 1;
    select($oldfh);
}

sub shutdown {
    if (!$direct_output && $logfd) {
        close $logfd;
        $logfd = undef;
    }
}

sub get_timestamp {
    my $t = gettimeofday;
    return sprintf "%s.%04d ", (POSIX::strftime "%H:%M:%S", gmtime($t)), 10000 * ($t - int($t));
}

sub print_possibly_colored {
    my ($text, $color) = @_;

    if (($direct_output && !$istty) || !$direct_output) {
        $logfd && print $logfd get_timestamp() . "$text\n";
    }
    if ($istty || !$logfd) {
        if ($color) {
            print STDERR colored(get_timestamp() . $text, $color) . "\n";
        }
        else {
            print STDERR get_timestamp() . "$text\n";
        }
    }
    return;
}

sub diag {
    print_possibly_colored("@_");
    return;
}

sub fctres {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    print_possibly_colored(">>> $fname: $text", 'green');
    return;
}

sub fctinfo {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    print_possibly_colored("::: $fname: $text", 'yellow');
    return;
}

sub fctwarn {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    print_possibly_colored("!!! $fname: $text", 'red');
    return;
}

sub modstart {
    my $text = sprintf "||| %s at %s", join(' ', @_), POSIX::strftime("%F %T", gmtime);
    print_possibly_colored($text, 'bold');
    return;
}

sub update_line_number {
    return unless $autotest::current_test;
    my $out    = "";
    my $ending = quotemeta($autotest::current_test->{script});
    for my $i (1 .. 10) {
        my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller($i);
        last unless $filename;
        next unless $filename =~ m/$ending$/;
        print get_timestamp() . "Debug: $filename:$line called $subroutine\n";
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
    my $fname = (caller(1))[3];
    update_line_number();
    my @result;
    while (my ($key, $value) = splice(@_, 0, 2)) {
        push @result, join("=", $key, pp($value));
    }
    my $params = join(", ", @result);

    print_possibly_colored('<<< ' . $fname . "($params)", 'blue');
    return;
}

sub mydie {
    my ($cause_of_death) = @_;
    log_call(cause_of_death => $cause_of_death);
    croak "mydie";
}

1;

# vim: set sw=4 et:
