#!/usr/bin/perl

# Copyright (C) 2021 SUSE LLC
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

use Test::Most;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal qw(lives_ok);
use Test::MockModule;

subtest 'script_run' => sub {
    require distribution;
    my $d            = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(type_string => undef);
    $mock_testapi->redefine(wait_serial => undef);
    like(warning { $d->script_run }->[0],   qr/^Use of uninitialized.*\$cmd/,     'Warning on incorrect usage');
    like(warning { $d->script_run('foo') }, qr/^Use of uninitialized.*serialdev/, 'Warning on undefined serialdev');
    {
        no warnings 'once';
        $testapi::serialdev = 'my_serial';
    }
    my $typed_string = '';
    $mock_testapi->redefine(type_string => sub { $typed_string .= $_[0] });
    lives_ok { $d->script_run('foo') } 'script_run succeeds with trivial command';
    like $typed_string, qr/foo; echo .* > .*serial/, 'command is typed plus marker and redirection';
    $typed_string = '';
    lives_ok { $d->script_run('foo &') } 'script_run with valid terminator ends';
    like $typed_string, qr/foo & echo .* > .*serial/, 'command with already included terminator handled correctly';
};

done_testing;

1;
