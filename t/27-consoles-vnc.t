#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use Test::MockObject;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::VNC;

my $c = consoles::VNC->new;
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $s = Test::MockObject->new->set_true('sockopt', 'print', 'connected');
$s->set_series('mocked_read', 'RFB 003.006', pack('N', 1));
$s->mock('read', sub { $_[1] = $s->mocked_read; 1 });
$inet_mock->redefine(new => $s);
my $vnc_mock = Test::MockModule->new('consoles::VNC');
$vnc_mock->noop('_server_initialization');
is $c->login, '', 'can call login';

done_testing;
