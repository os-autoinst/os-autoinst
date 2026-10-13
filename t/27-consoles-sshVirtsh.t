#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use Test::Warnings qw(:all :report_warnings);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::sshVirtsh;

my $c = consoles::sshVirtsh->new('sut', {});
is $c->ssh_port({}), 22, 'hypervisor SSH port defaults to 22';
{
    local $bmwqemu::vars{SUT_SSH_PORT} = 10022;
    is $c->ssh_port({}), 22, 'hypervisor SSH port ignores SUT_SSH_PORT';
    is $c->ssh_port({port => 2222}), 2222, 'explicit hypervisor port from args wins';
}

done_testing;
