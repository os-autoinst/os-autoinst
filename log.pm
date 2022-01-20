# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package log;

use Mojo::Base -strict;
use Carp;
use Mojo::File qw(path);
use Mojo::Log;
use POSIX 'strftime';
use Time::HiRes qw(gettimeofday);
use Time::Moment;
use Term::ANSIColor;
use Exporter 'import';
our @EXPORT_OK = qw(logger init_logger diag fctres fctinfo fctwarn modstate);

our $logger;
our $direct_output;

sub logger { $logger //= Mojo::Log->new(level => 'debug', format => \&log_format_callback) }

sub init_logger { logger->path(path('testresults', 'autoinst-log.txt')) unless $direct_output }

sub log_format_callback {
    my ($time, $level, @items) = @_;

    my $lines = join("\n", @items, '');

    # ensure indentation for multi-line output
    $lines =~ s/(?<!\A)^/  /gm;

    return '[' . Time::Moment->now . "] [$level] $lines";
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

sub modstate {
    logger->append(color('bold blue'));
    logger->debug("||| @{[join(' ', @_)]}")->append(color('reset'));
    return;
}

1;
