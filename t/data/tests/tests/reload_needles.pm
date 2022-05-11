# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($) {
    # this is the default, but to test set_var without argument
    set_var('VERSION', '1');
    enter_cmd 'echo HALLO';
    my $ret = assert_screen 'no-importa';
    die 'Should see v1' unless $ret->{needle}->{name} eq 'no-importa-v1';

    set_var('VERSION', '2', reload_needles => 1);
    $ret = assert_screen 'no-importa';
    die 'Should see v2' unless $ret->{needle}->{name} eq 'no-importa-v2';
}

1;
