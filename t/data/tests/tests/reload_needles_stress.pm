# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Regression test for poo#205302 (see note-7 of poo#205206): set_var(...,
# reload_needles => 1) sends 'backend_reload_needles' to the backend
# asynchronously -- isotovideo does not block on its reply.
# CommandHandler::_handle_command_set_current_test (fired for every module
# transition) makes its own synchronous 'clear_serial_buffer' exchange with the
# backend via driver::_send_json immediately afterwards. If the backend's
# reload_needles reply lands on backend_out_fd while that synchronous exchange
# is waiting for its own token, isotovideo used to confess "the token does not
# match". Scheduling this module many times in a row (see t/14-isotovideo.t)
# lines up an async reload_needles fire with the very next module's automatic
# synchronous exchange on every transition, making a single-run race reliably
# observable instead of depending on incidental process-scheduling luck --
# without needing real needle matching, which backend=null cannot provide.

use base 'basetest';
use testapi;

sub run ($) {
    set_var('VERSION', 1 + int(rand(2)), reload_needles => 1);
}

1;
