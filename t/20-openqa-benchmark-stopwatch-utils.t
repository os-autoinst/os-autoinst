#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings ':report_warnings';
use Time::HiRes 'sleep';


use OpenQA::Benchmark::Stopwatch;

my $watch = OpenQA::Benchmark::Stopwatch->new();
$watch->start();

sleep 0.001;
$watch->lap("Lap 0.001s");
sleep 0.002;
$watch->lap("Lap 0.002s");
$watch->stop();

ok($watch->as_data()->{total_time} gt 0.002,                                               "Pass summary as data");
ok($watch->as_data()->{laps}[0]{time} gt 0.001,                                            "Pass first lap");
ok($watch->as_data()->{laps}[1]{time} gt 0.002 && $watch->as_data()->{laps}[1]{time} lt 3, "Pass second lap");
print $watch->summary();

done_testing();
