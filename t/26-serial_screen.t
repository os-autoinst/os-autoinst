#!/usr/bin/perl
# Copyright © 2019 SUSE LLC

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::serial_screen;

my $screen = consoles::serial_screen->new('read', 'write');
is($screen->{fd_write},     'write', 'Check if channel was set for write fd');
is($screen->{fd_read},      'read',  'Check if channel was set for read fd');
is($screen->{carry_buffer}, '',      'Check if channel was set for read fd');

$screen = consoles::serial_screen->new('same', 'same');
is($screen->{fd_read}, 'same',              'Fd read member was set.');
is($screen->{fd_read}, $screen->{fd_write}, 'If only one fd give, read and write are equal');

done_testing;
