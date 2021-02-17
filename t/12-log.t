#!/usr/bin/perl

# Copyright (C) 2017-2021 SUSE LLC
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
use Test::Output 'stderr_like';
use log;


subtest 'log_call' => sub {
    sub log_call_test {
        log::log_call(foo => "bar\tbaz\rboo\n");
    }
    stderr_like(\&log_call_test, qr{\Q<<< main::log_call_test(foo="bar\tbaz\rboo\n")}, 'log_call escapes special characters');

    sub log_call_test_escape_key {
        log::log_call("foo\nbar" => "bar\tbaz\rboo\n");
    }
    stderr_like(\&log_call_test_escape_key, qr{\Q<<< main::log_call_test_escape_key("foo\nbar"="bar\tbaz\rboo\n")}, 'log_call escapes special characters');

    sub log_call_test_single {
        log::log_call("bar\tbaz\rboo\n");
    }
    stderr_like(\&log_call_test_single, qr{\Q<<< main::log_call_test_single("bar\tbaz\rboo\n")}, 'log_call escapes special characters');
};

subtest 'update_line_number' => sub {
    {
        no warnings 'once';
        $log::direct_output = 1;
    }
    log::init_logger();
    ok !log::update_line_number(), 'update_line_number needs current_test defined';
    {
        no warnings 'once';
        $autotest::current_test = {script => 'my/module.pm'};
    }
    stderr_like { log::update_line_number() } qr{log.t.*called.*subtest}, 'update_line_number identifies caller scope';
};

done_testing;

END {
    unlink 'vars.json';
}

1;

