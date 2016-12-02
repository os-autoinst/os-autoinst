#!/usr/bin/perl
# Do not add to makefile.am

use strict;
use warnings;
use Test::More;


BEGIN {
    unshift @INC, '..';
}

use OpenQA::Benchmark::Stopwatch;

my $watch = OpenQA::Benchmark::Stopwatch->new();
$watch->start();

sleep 1;
$watch->lap("Lap 1 sec");
sleep 2;
$watch->lap("Lap 2 sec");
$watch->stop();

ok($watch->as_data()->{total_time} gt 2,"Pass summary as data");
ok($watch->as_data()->{laps}[0]{time} gt 1,"Pass 1sec lap");
ok($watch->as_data()->{laps}[1]{time} gt 2 && $watch->as_data()->{laps}[1]{time} lt 3 ,"Pass 2sec lap");
print $watch->summary();

done_testing();

# vim: set sw=4 et:
