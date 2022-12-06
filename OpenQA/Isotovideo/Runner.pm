# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Runner;
use Mojo::Base -base, -signatures;
use autodie ':all';
no autodie 'kill';
use log qw(diag);
use OpenQA::Isotovideo::Utils qw(checkout_git_repo_and_branch checkout_git_refspec checkout_wheels
load_test_schedule);
use OpenQA::Isotovideo::Backend;
use bmwqemu ();
use testapi ();
use autotest ();

has [qw(cmd_srv_process cmd_srv_fd cmd_srv_port)];

has [qw(testprocess testfd)];

sub load_schedule ($self) {
    # set a default distribution if the tests don't have one
    $testapi::distri = distribution->new;

    load_test_schedule;
}

sub start_server ($self) {
    # start the command fork before we get into the backend, the command child
    # is not supposed to talk to the backend directly
    my ($cmd_srv_process, $cmd_srv_fd, $cmd_srv_port);
    ($cmd_srv_process, $cmd_srv_fd) = commands::start_server($cmd_srv_port = $bmwqemu::vars{QEMUPORT} + 1);
    $self->cmd_srv_process($cmd_srv_process);
    $self->cmd_srv_fd($cmd_srv_fd);
    $self->cmd_srv_port($cmd_srv_port);
}

sub start_autotest ($self) {
    my ($testprocess, $testfd) = autotest::start_process();
    $self->testprocess($testprocess);
    $self->testfd($testfd);
}

sub create_backend ($self) {
    my $backend = OpenQA::Isotovideo::Backend->new;
    return $backend;
}

# note: The subsequently defined stop_* functions are used to tear down the process tree.
#       However, the worker also ensures that all processes are being terminated (and
#       eventually killed).

sub stop_commands ($self, $reason) {
    return unless defined $self->cmd_srv_process;
    return unless $self->cmd_srv_process->is_running;

    my $pid = $self->cmd_srv_process->pid;
    diag("stopping command server $pid because $reason");

    if ($self->cmd_srv_port && $reason && $reason eq 'test execution ended') {
        my $job_token = $bmwqemu::vars{JOBTOKEN};
        my $url = "http://127.0.0.1:".$self->cmd_srv_port."/$job_token/broadcast";
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

    $self->cmd_srv_process->stop();
    $self->cmd_srv_process(undef);
    diag('done with command server');
}

sub stop_autotest ($self) {
    return unless defined $self->testprocess;

    diag('stopping autotest process ' . $self->testprocess->pid);
    $self->testprocess->stop() if $self->testprocess->is_running;
    $self->testprocess(undef);
    diag('done with autotest process');
}

sub checkout_code($self) {
    checkout_git_repo_and_branch('CASEDIR');

    # Try to load the main.pm from one of the following in this order:
    #  - product dir
    #  - casedir
    #
    # This allows further structuring the test distribution collections with
    # multiple distributions or flavors in one repository.
    $bmwqemu::vars{PRODUCTDIR} ||= $bmwqemu::vars{CASEDIR};

    # checkout Git repo NEEDLES_DIR refers to (if it is a URL) and re-assign NEEDLES_DIR to contain the checkout path
    checkout_git_repo_and_branch('NEEDLES_DIR');

    bmwqemu::ensure_valid_vars();

    # as we are about to load the test modules checkout the specified git refspec,
    # if specified, or simply store the git hash that has been used. If it is not a
    # git repo fail silently, i.e. store an empty variable

    $bmwqemu::vars{TEST_GIT_HASH} = checkout_git_refspec($bmwqemu::vars{CASEDIR} => 'TEST_GIT_REFSPEC');

    $bmwqemu::vars{WHEELS_DIR} ||= $bmwqemu::vars{CASEDIR};
    checkout_wheels($bmwqemu::vars{WHEELS_DIR});
}

sub _flush_std ($) {
    select(STDERR);
    $| = 1;
    select(STDOUT);    # default
    $| = 1;
}

sub _init_bmwqemu ($, @args) {
    bmwqemu::init();
    for my $arg (@args) {
        if ($arg =~ /^([[:alnum:]_\[\]\.]+)=(.+)/) {
            my $key = uc $1;
            $bmwqemu::vars{$key} = $2;
            diag("Setting forced test parameter $key -> $2");
        }
    }
}


1;
