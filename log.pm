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

package log;

use strictures;
use Carp;
use File::Spec::Functions qw(catfile);
use Mojo::Log;
use POSIX 'strftime';
use Time::HiRes qw(gettimeofday);
use Term::ANSIColor;
use common qw(result_dir);
use Exporter 'import';
our @EXPORT_OK = qw(logger init_logger update_line_number pp log_call);

our $logger;
our $direct_output;


sub logger { $logger //= Mojo::Log->new(level => 'debug', format => \&log_format_callback) }

sub init_logger { logger->path(catfile(common::result_dir, 'autoinst-log.txt')) unless $direct_output }

sub update_line_number {
    return unless $autotest::current_test;
    return unless $autotest::current_test->{script};
    my @out;
    my $casedir = $bmwqemu::vars{CASEDIR} // '';
    for (my $i = 10; $i > 0; $i--) {
        my ($package, $filename, $line, $subroutine) = caller($i);
        next unless $filename && $filename =~ /\Q$casedir/;
        $filename =~ s@$casedir/?@@;
        push @out, "$filename:$line called $subroutine";
    }
    $log::logger->debug(join(' -> ', @out));
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

sub log_format_callback {
    my ($time, $level, @lines) = @_;
    # Unfortunately $time doesn't have the precision we want. So we need to use Time::HiRes
    $time = gettimeofday;
    return sprintf(strftime("[%FT%T.%%03d %Z] [$level] ", localtime($time)), 1000 * ($time - int($time))) . join("\n", @lines, '');
}

sub diag {
    my ($args) = @_;
    confess "missing input" unless $args;
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

sub modstart {
    logger->append(color('bold blue'));
    logger->debug("||| @{[join(' ', @_)]}")->append(color('reset'));
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

sub mydie {
    my ($cause_of_death) = @_;
    log::log_call(cause_of_death => $cause_of_death);
    croak "mydie";
}

1;
