#!/usr/bin/perl
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later


use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings qw(warnings :report_warnings);
use OpenQA::Qemu::BlockDev;
use OpenQA::Qemu::DriveDevice;
use OpenQA::Qemu::DrivePath;
use OpenQA::Qemu::Snapshot;

my $string;

my $blockdev = OpenQA::Qemu::BlockDev->new(node_name => 'foo');
$string = $blockdev->CARP_TRACE;
is $string, 'OpenQA::Qemu::BlockDev(foo)', 'OpenQA::Qemu::BlockDev';

my $drivedevice = OpenQA::Qemu::DriveDevice->new(id => 'foo');
$string = $drivedevice->CARP_TRACE;
is $string, 'OpenQA::Qemu::DriveDevice(foo)', 'OpenQA::Qemu::DriveDevice';

my $drivepath = OpenQA::Qemu::DrivePath->new(id => 'foo');
$string = $drivepath->CARP_TRACE;
is $string, 'OpenQA::Qemu::DrivePath(foo)', 'OpenQA::Qemu::DrivePath';

my $snapshot = OpenQA::Qemu::Snapshot->new(sequence => '23', name => 'foo');
$string = $snapshot->CARP_TRACE;
is $string, 'OpenQA::Qemu::Snapshot(23|foo)', 'OpenQA::Qemu::Snapshot';

done_testing;
