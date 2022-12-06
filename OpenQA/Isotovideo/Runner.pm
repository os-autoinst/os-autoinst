# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Runner;
use Mojo::Base -base, -signatures;
use autodie ':all';
no autodie 'kill';
use log qw(diag);

sub stop_commands ($self, $reason, $cmd_srv_process, $cmd_srv_port) {
    return unless defined $$cmd_srv_process;
    return unless $$cmd_srv_process->is_running;

    my $pid = $$cmd_srv_process->pid;
    diag("stopping command server $pid because $reason");

    if ($$cmd_srv_port && $reason && $reason eq 'test execution ended') {
        my $job_token = $bmwqemu::vars{JOBTOKEN};
        my $url = "http://127.0.0.1:$$cmd_srv_port/$job_token/broadcast";
        diag('isotovideo: informing websocket clients before stopping command server: ' . $url);

        # note: If the job is stopped by the worker because it has been
        # aborted, the worker will send this command on its own to the command
        # server and also stop the command server. So this is only done in the
        # case the test execution just ends.

        my $timeout = 15;
        # The command server might have already been stopped by the worker
        # after the user has aborted the job or the job timeout has been
        # exceeded so no checks for failure done.
        Mojo::UserAgent->new(request_timeout => $timeout)->post($url, json => {stopping_test_execution => $reason});
    }

    $$cmd_srv_process->stop();
    $$cmd_srv_process = undef;
    diag('done with command server');
}



sub _flush_std ($) {
    select(STDERR);
    $| = 1;
    select(STDOUT);    # default
    $| = 1;
}

sub _init_vars ($, @args) {
    for my $arg (@args) {
        if ($arg =~ /^([[:alnum:]_\[\]\.]+)=(.+)/) {
            my $key = uc $1;
            $bmwqemu::vars{$key} = $2;
            diag("Setting forced test parameter $key -> $2");
        }
    }
}


1;
