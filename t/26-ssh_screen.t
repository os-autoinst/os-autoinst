#!/usr/bin/perl
# Copyright © 2019 SUSE LLC

use Test::Most;
use consoles::ssh_screen;

my $screen = consoles::ssh_screen->new(ssh_connection => 'My_Con', ssh_channel => 'My_Chan');
is($screen->{fd_read},  'My_Chan', 'SSH channel is used for reading');
is($screen->{fd_write}, 'My_Chan', 'SSH channel is used for writing');

done_testing;
