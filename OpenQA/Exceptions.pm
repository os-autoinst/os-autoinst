# Copyright 2016-2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Exceptions;

use Mojo::Base -strict, -signatures;

use Exception::Class (
    'OpenQA::Exception::InternalException' => {
        description => 'internal errors not for the user'
    },
    'OpenQA::Exception::FailedNeedle' => {
        description => 'assert_screen failed',
        fields => 'tags',
    },
    'OpenQA::Exception::VNCProtocolError' => {
        description => 'VNC Server interrupted connection'
    },
    'OpenQA::Exception::VNCSetupError' => {
        description => 'Failed to connect to VNC Server'
    },
    'OpenQA::Exception::SSHConnectionError' => {
        description => 'Failed to connect to SSH Server'
    },
    'OpenQA::Exception::ConsoleReadError' => {
        description => 'Failed to receive data from console'
    },
);

1;
