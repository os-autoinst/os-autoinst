# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package testdistribution;

use Mojo::Base 'distribution', -signatures;

sub init ($self) {
    $self->SUPER::init();
    $self->init_consoles();
}

sub init_consoles ($self) {
    $self->add_console(
        'brokenvnc',
        'vnc-base',
        {
            hostname => 'novnc.nowhere',
            port => 5901,
            password => $testapi::password
        });
    $self->add_console(
        'brokeniucv',
        'ssh-iucvconn',
        {
            hostname => 'noIucvconn.nowhere',
            password => $testapi::password
        });
}

1;
