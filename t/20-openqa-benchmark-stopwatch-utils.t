#!/usr/bin/perl
# Do not add to makefile.am

use strict;
use warnings;
use Test::More;
use Test::Warnings;
use Time::HiRes 'sleep';


BEGIN {
    unshift @INC, '..';
}

use OpenQA::Benchmark::Stopwatch;

my $watch = OpenQA::Benchmark::Stopwatch->new();
$watch->start();

sleep 0.001;
$watch->lap("Lap 0.001s");
sleep 0.002;
$watch->lap("Lap 0.002s");
$watch->stop();

ok($watch->as_data()->{total_time} gt 0.002,    "Pass summary as data");
ok($watch->as_data()->{laps}[0]{time} gt 0.001, "Pass first lap");
ok($watch->as_data()->{laps}[1]{time} gt 0.002 && $watch->as_data()->{laps}[1]{time} lt 3, "Pass second lap");
print $watch->summary();

done_testing();

# vim: set sw=4 et:
