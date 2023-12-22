# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Runner;
use Mojo::Base -base, -signatures;
use autodie ':all';
no autodie 'kill';
use POSIX qw(:sys_wait_h _exit);
use Mojo::UserAgent;
use IO::Select;
use log qw(diag fctwarn);
use OpenQA::Isotovideo::Utils qw(checkout_git_repo_and_branch checkout_git_refspec checkout_wheels
  load_test_schedule);
use OpenQA::Isotovideo::Backend;
use OpenQA::Isotovideo::CommandHandler;
use bmwqemu ();
use testapi ();
use autotest ();
use needle ();
use commands ();
use distribution ();

has [qw(cmd_srv_process cmd_srv_fd cmd_srv_port)];

has [qw(testprocess testfd)];

has [qw(backend command_handler)];

# the loop status
has loop => 1;

sub run ($self) {
    # now we have everything, give the tests a go
    $self->testfd->write("GO\n");

    my $ch = $self->command_handler;
    my $io_select = IO::Select->new();
    $io_select->add($self->testfd);
    $io_select->add($ch->cmd_srv_fd);
    $io_select->add($ch->backend_out_fd);

    while ($self->loop) {
        my ($ready_for_read, $ready_for_write, $exceptions) = IO::Select::select($io_select, undef, $io_select, $ch->timeout);
        for my $readable (@$ready_for_read) {
            my $rsp = myjsonrpc::read_json($readable);
            $self->_read_response($rsp, $readable);
            last unless defined $rsp;
        }
        $ch->check_asserted_screen if defined($ch->tags);
    }
    $ch->stop_command_processing;
    return 0;
}

sub _read_response ($self, $rsp, $fd) {
    if (!defined $rsp) {
        fctwarn sprintf("THERE IS NOTHING TO READ %d %d %d", fileno($fd), fileno($self->testfd), fileno($self->cmd_srv_fd));
        $self->loop(0);
    } elsif ($fd == $self->command_handler->backend_out_fd) {
        $self->command_handler->send_to_backend_requester({ret => $rsp->{rsp}});
    } else {
        $self->command_handler->process_command($fd, $rsp);
    }
}

sub prepare ($self) {
    $self->_flush_std;
    $self->checkout_code;
    $self->load_schedule;
    $self->start_server;
    testapi::init();
    needle::init();
    bmwqemu::save_vars();
}

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
    $self->backend($backend);
}

sub handle_commands ($self) {
    my $command_handler;
    # stop main loop as soon as one of the child processes terminates
    my $stop_loop = sub (@) { $self->loop(0) if $self->loop; };
    $self->testprocess->once(collected => $stop_loop);
    $self->backend->process->once(collected => $stop_loop);
    $self->cmd_srv_process->once(collected => $stop_loop);

    $command_handler = OpenQA::Isotovideo::CommandHandler->new(
        cmd_srv_fd => $self->cmd_srv_fd,
        test_fd => $self->testfd,
        backend_fd => $self->backend->process->channel_in,
        backend_out_fd => $self->backend->process->channel_out,
    );
    $command_handler->on(tests_done => sub (@) {
            CORE::close($self->testfd);
            $self->testfd(undef);
            $self->stop_autotest();
            $self->loop(0);
    });
    # uncoverable statement count:1
    # uncoverable statement count:2
    # uncoverable statement count:3
    # uncoverable statement count:4
    $command_handler->on(signal => sub ($event, $sig) {
            $self->backend->stop if defined $self->backend;    # uncoverable statement
            $self->stop_commands("received signal $sig");    # uncoverable statement
            $self->stop_autotest();    # uncoverable statement
            _exit(1);    # uncoverable statement
    });
    $self->setup_signal_handler;

    $self->command_handler($command_handler);
}

sub setup_signal_handler ($self) {
    my $signal_handler = sub ($sig) { $self->_signal_handler($sig) };
    $SIG{TERM} = $signal_handler;
    $SIG{INT} = $signal_handler;
    $SIG{HUP} = $signal_handler;
}

sub _signal_handler ($self, $sig) {
    bmwqemu::serialize_state(component => 'isotovideo', msg => "isotovideo received signal $sig", log => 1);
    return $self->loop(0) if $self->loop;
    $self->command_handler->emit(signal => $sig);
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
        my $url = "http://127.0.0.1:" . $self->cmd_srv_port . "/$job_token/broadcast";
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

sub checkout_code ($self) {
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

    ($bmwqemu::vars{TEST_GIT_URL}, $bmwqemu::vars{TEST_GIT_HASH}) = checkout_git_refspec($bmwqemu::vars{CASEDIR} => 'TEST_GIT_REFSPEC');

    checkout_wheels($bmwqemu::vars{CASEDIR}, $bmwqemu::vars{WHEELS_DIR});
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

sub handle_shutdown ($self, $return_code) {
    return undef if $$return_code;
    my $clean_shutdown;
    eval {
        $clean_shutdown = $bmwqemu::backend->_send_json({cmd => 'is_shutdown'});
        diag('backend shutdown state: ' . ($clean_shutdown // '?'));
    };

    # don't rely on the backend to be in a sane state if we failed - just stop it later
    eval { bmwqemu::stop_vm() };
    if ($@) {
        bmwqemu::serialize_state(component => 'backend', msg => "unable to stop VM: $@", error => 1);
        $$return_code = 1;
    }
    return $clean_shutdown;
}


1;
