#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings ':report_warnings';
use Test::MockModule;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';
use OpenQA::Isotovideo::Utils qw(spawn_debuggers);

subtest debuggers => sub {
    $bmwqemu::scriptdir = "$Bin/..";
    $bmwqemu::vars{VNC} = '1234';
    my $vncviewer_called = 0;
    my $debugviewer_called = 0;
    my $ipc_run_mock = Test::MockModule->new('IPC::Run');
    $ipc_run_mock->redefine(run => sub ($cmd, $stdin, $stdout, $stderr) {
            $vncviewer_called++ if $cmd->[0] =~ /vncviewer/;
            $debugviewer_called++ if $cmd->[0] =~ /debugviewer/;
    });
    delete $ENV{RUN_VNCVIEWER};
    delete $ENV{RUN_DEBUGVIEWER};

    $vncviewer_called = 0;
    $debugviewer_called = 0;
    spawn_debuggers;
    is($vncviewer_called, 0, 'vncviewer was not executed');
    is($debugviewer_called, 0, 'debugviewer was not executed');

    $ENV{RUN_VNCVIEWER} = 1;
    $ENV{RUN_DEBUGVIEWER} = 1;
    spawn_debuggers;
    is($vncviewer_called, 1, 'vncviewer was executed');
    is($debugviewer_called, 1, 'debugviewer was executed');
};

done_testing();
