# Copyright 2018-2019 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::CommandHandler;
use Mojo::Base 'Mojo::EventEmitter', -signatures;

use bmwqemu;
use autotest ();
use log qw(diag fctwarn);
use OpenQA::Isotovideo::Interface;
use OpenQA::Isotovideo::NeedleDownloader;
use OpenQA::Isotovideo::Backend;
use Cpanel::JSON::XS;
use Mojo::File 'path';
use Mojo::UserAgent;
use IO::Select;
use Time::HiRes qw(gettimeofday tv_interval);

use constant AUTOINST_STATUSFILE => 'autoinst-status.json';


# io handles for sending data to command server and backend
has [qw(test_fd cmd_srv_fd backend backend_fd backend_out_fd answer_fd)] => undef;

# the running test process
has test_process => undef;

# the command server process
has [qw(cmd_srv_process cmd_srv_port)] => undef;

# the name of the current test (full name includes category prefix, eg. installation-)
has [qw(current_test_name current_test_full_name)];

# the currently processed test API function
has current_api_function => undef;

# status = ( initial | running | finished )
# set to running when first test starts
has status => 'initial';

# conditions when to pause
has pause_test_name => sub { $bmwqemu::vars{PAUSE_AT} };
# (set to name of a certain test module, with or without category)
has pause_on_screen_mismatch => sub { $bmwqemu::vars{PAUSE_ON_SCREEN_MISMATCH} };
# (set to 'assert_screen' or 'check_screen' where 'check_screen' includes 'assert_screen')
has pause_on_next_command => sub { $bmwqemu::vars{PAUSE_ON_NEXT_COMMAND} // 0 };
# (set to 0 or 1)
has pause_on_failure => sub { $bmwqemu::vars{PAUSE_ON_FAILURE} // 0 };
# (set to 0 or 1)

# the reason why the test execution has paused or 0 if not paused
has reason_for_pause => 0;
# the loop status
has loop => 1;

# when paused, save the command from autotest which has been postponed to be able to resume
has postponed_answer_fd => undef;
has postponed_command => undef;

# properties consumed by isotovideo::check_asserted_screen
#  * timeout for the select (only set for check_screens)
#  * tags received from 'set_tags_to_assert' command
#  * do not wait for timeout if set
has [qw(timeout no_wait tags)];

# set to the socket we have to send replies to when the backend is done
has backend_requester => undef;

# whether the test has already been completed and whether it has died
has [qw(test_completed test_died)] => 0;

# the time of the last asserted screen
has [qw(last_check_seconds last_check_microseconds)] => 0;

sub new ($class, @args) {
    my $self = $class->SUPER::new(@args);
    $self->_update_last_check;
    return $self;
}

sub init ($self) {
    $self->start_process;
    $self->start_backend;
    return $self;
}

sub start_process ($self) {
    my ($test_process, $test_fd) = autotest::start_process;
    $test_process->once(collected => sub { $self->loop(0) if $self->loop });
    $self->test_process($test_process);
    $self->test_fd($test_fd);
}

sub start_backend ($self) {
    my $backend = OpenQA::Isotovideo::Backend->new;
    my $stop_loop = sub (@) { $self->loop(0) if $self->loop; };
    $backend->process->once(collected => $stop_loop);
    $self->backend($backend);
    $self->backend_fd($backend->process->channel_in);
    $self->backend_out_fd($backend->process->channel_out);
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
    $self->stop_autotest;
    $self->emit(signal => $sig);
}

sub stop_autotest ($self) {
    my $test_process = $self->test_process or return;
    diag('stopping autotest process ' . $test_process->pid);
    $test_process->stop() if $test_process->is_running;
    $self->test_process(undef);
    diag('done with autotest process');
}

sub clear_tags_and_timeout ($self) {
    $self->tags(undef);
    $self->timeout(undef);
}

# processes the $response and send the answer back via $answer_fd by invoking one of the subsequent handler methods
# note: To add a new command, create a handler method called "_handle_command_<new_command_name>".
sub process_command ($self, $answer_fd, $command_to_process) {
    my $cmd = $command_to_process->{cmd} or die 'isotovideo: no command specified';
    $self->answer_fd($answer_fd);

    # invoke handler for the command
    if (my $handler = $self->can('_handle_command_' . $cmd)) {
        return $handler->($self, $command_to_process, $cmd);
    }
    if ($cmd =~ m/^backend_(.*)/) {
        return $self->_pass_command_to_backend_unless_paused($command_to_process, $1);
    }

    die 'isotovideo: unknown command ' . $cmd;
}

sub stop_command_processing ($self) { $self->_send_to_cmd_srv({stop_processing_isotovideo_commands => 1}) }

sub stop_server ($self, $reason) {
    return unless defined $self->cmd_srv_process && $self->cmd_srv_process->is_running;
    diag('stopping command server ' . $self->cmd_srv_process->pid() . " because $reason");

    if ($self->cmd_srv_port && $reason && $reason eq 'test execution ended') {
        my $job_token = $bmwqemu::vars{JOBTOKEN};
        my $url = 'http://127.0.0.1:' . $self->cmd_srv_port . "/$job_token/broadcast";
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

sub _postpone_backend_command_until_resumed ($self, $response) {
    my $cmd = $response->{cmd};
    my $reason_for_pause = $self->reason_for_pause;

    # check whether we're supposed to pause on the next command if there's no other reason to pause anyways
    if (!$reason_for_pause && $self->pause_on_next_command) {
        $self->reason_for_pause($reason_for_pause = "reached $cmd and pause on next command enabled");
    }

    return unless $reason_for_pause;

    # emit info
    $self->_send_to_cmd_srv({paused => $response, reason => $reason_for_pause});
    $self->update_status_file;
    diag("isotovideo: paused, so not passing $cmd to backend");

    # postpone execution of command
    $self->postponed_answer_fd($self->answer_fd);
    $self->postponed_command($response);

    # send no reply to autotest, just let it wait
    return 1;
}

sub _send_to_cmd_srv ($self, $data) { myjsonrpc::send_json($self->cmd_srv_fd, $data) }

sub _send_to_backend ($self, $data) { myjsonrpc::send_json($self->backend_fd, $data) }

sub send_to_backend_requester ($self, $data) {
    myjsonrpc::send_json($self->backend_requester, $data);
    $self->backend_requester(undef);
}

sub _respond ($self, $data) { myjsonrpc::send_json($self->answer_fd, $data) }

sub _respond_ok ($self) { $self->_respond({ret => 1}) }

sub _respond_ok_or_postpone_if_paused ($self) {
    return $self->_respond_ok unless my $reason_for_pause = $self->reason_for_pause;
    $self->_send_to_cmd_srv({paused => 1, reason => $reason_for_pause});
    $self->postponed_answer_fd($self->answer_fd)->postponed_command(undef);
}

sub _pass_command_to_backend_unless_paused ($self, $response, $backend_cmd) {
    return if $self->_postpone_backend_command_until_resumed($response);

    die 'isotovideo: we need to implement a backend queue' if $self->backend_requester;
    $self->backend_requester($self->answer_fd);

    $self->_send_to_cmd_srv({
            $backend_cmd => $response,
            current_api_function => $backend_cmd,
    });
    $self->_send_to_backend({cmd => $backend_cmd, arguments => $response});
    $self->current_api_function($backend_cmd);
}

sub _is_configured_to_pause_on_timeout ($self, $response) {
    return 0 unless my $pause_on_screen_mismatch = $self->pause_on_screen_mismatch;

    return 1 if ($pause_on_screen_mismatch eq 'check_screen');
    return $response->{check} ? 0 : 1 if ($pause_on_screen_mismatch eq 'assert_screen');
    return 0;
}

sub _handle_command_report_timeout ($self, $response, @) {
    if (!$self->_is_configured_to_pause_on_timeout($response)) {
        $self->_respond({ret => 0});
        return;
    }

    my $reason_for_pause = $response->{msg};
    $self->reason_for_pause($reason_for_pause);
    $self->_send_to_cmd_srv({paused => $response, reason => $reason_for_pause});
    $self->update_status_file;
    diag('isotovideo: pausing test execution on timeout as requested at ' . $self->current_test_full_name);

    # postpone sending the reply
    $self->postponed_answer_fd($self->answer_fd);
    $self->postponed_command(undef);
}

sub _handle_command_is_configured_to_pause_on_timeout ($self, $response, @) {
    $self->_respond({
            ret => ($self->_is_configured_to_pause_on_timeout($response) ? 1 : 0)
    });
}

sub _handle_command_set_pause_at_test ($self, $response, @) {
    my $pause_test_name = $response->{name};
    if ($pause_test_name) {
        diag('isotovideo: test execution will be paused at test ' . $pause_test_name);
    }
    elsif ($self->pause_test_name) {
        diag('isotovideo: test execution will no longer be paused at a certain test');
    }
    $self->pause_test_name($pause_test_name);
    $self->_send_to_cmd_srv({set_pause_at_test => $pause_test_name});
    $self->_respond_ok();
}

sub _handle_command_set_pause_on_screen_mismatch ($self, $response, @) {
    my $pause_on_screen_mismatch = $response->{pause_on};
    $self->pause_on_screen_mismatch($pause_on_screen_mismatch);
    $self->_send_to_cmd_srv({set_pause_on_screen_mismatch => ($pause_on_screen_mismatch // Mojo::JSON->false)});
    $self->_respond_ok();
}

sub _handle_command_set_pause_on_next_command ($self, $response, @) {
    my $set_pause_on_next_command = ($response->{flag} ? 1 : 0);
    $self->pause_on_next_command($set_pause_on_next_command);
    $self->_send_to_cmd_srv({set_pause_on_next_command => $set_pause_on_next_command});
    $self->_respond_ok();
}

sub _handle_command_set_pause_on_failure ($self, $response, @) {
    my $set_pause_on_failure = ($response->{flag} ? 1 : 0);
    $self->pause_on_failure($set_pause_on_failure);
    $self->_send_to_cmd_srv({set_pause_on_failure => $set_pause_on_failure});
    $self->_respond_ok();
}

sub _handle_command_pause_test_execution ($self, $response, @) {
    return $self->_respond_ok if $self->reason_for_pause;    # do nothing if already paused
    return $self->_respond_ok if $response->{due_to_failure} && !$self->pause_on_failure;
    my $reason_for_pause = $response->{reason} // 'manually paused';
    $self->reason_for_pause($reason_for_pause);
    $self->_send_to_cmd_srv({paused => 1, reason => $reason_for_pause});
    $self->postponed_answer_fd($self->answer_fd)->postponed_command(undef);
}

sub _handle_command_resume_test_execution ($self, $response, @) {
    my $postponed_command = $self->postponed_command;
    my $postponed_answer_fd = $self->postponed_answer_fd;

    diag($self->reason_for_pause ?
          'isotovideo: test execution will be resumed'
        : 'isotovideo: resuming test execution requested but not paused anyways'
    );
    $self->_send_to_cmd_srv({resume_test_execution => $postponed_command});

    # unset paused state to continue passing commands to backend
    $self->reason_for_pause(0);

    $self->update_status_file;
    my $downloader = OpenQA::Isotovideo::NeedleDownloader->new();
    $downloader->download_missing_needles($response->{new_needles} // []);

    # skip resuming last command if receiving a resume command without having previously postponed an answer
    # note: This should normally not be the case. However, the JavaScript client can technically send the command
    #       to resume at any time and that apparently also happens sometimes in the fullstack test (see poo#101734).
    return undef unless defined $postponed_answer_fd;

    # if no command has been postponed (because paused due to timeout or on set_current_test) just return 1
    if (!$postponed_command) {
        myjsonrpc::send_json($postponed_answer_fd, {
                ret => ($response->{options} // 1),
                new_needles => $response->{new_needles},
        });
        $self->postponed_answer_fd(undef);
        return;
    }

    # resume with postponed command so autotest can continue
    my $cmd = $postponed_command->{cmd};
    diag("isotovideo: resuming, continue passing $cmd to backend");

    $self->postponed_command(undef);
    $self->postponed_answer_fd(undef);
    $self->process_command($postponed_answer_fd, $postponed_command);
}

sub _handle_command_set_current_test ($self, $response, @) {
    # Note: It is unclear why we call set_serial_offset here
    $bmwqemu::backend->_send_json({cmd => 'clear_serial_buffer'});

    my ($test_name, $full_test_name) = ($response->{name}, $response->{full_name});
    my $pause_test_name = $self->pause_test_name;
    $self->current_test_name($test_name);
    $self->status('running');
    $self->current_test_full_name($full_test_name);
    $self->_send_to_cmd_srv({
            set_current_test => $test_name,
            current_test_full_name => $full_test_name,
    });

    if ($pause_test_name
        && $test_name
        && $full_test_name
        && ($pause_test_name eq $test_name || $pause_test_name eq $full_test_name))
    {
        diag("isotovideo: pausing test execution of $pause_test_name because we're supposed to pause at this test module");
        $self->reason_for_pause('reached module ' . $pause_test_name);
    }
    $self->update_status_file;
    $self->_respond_ok_or_postpone_if_paused;
}

sub _handle_command_tests_done ($self, $response, @) {
    $self->test_died($response->{died});
    $self->test_completed($response->{completed});
    CORE::close($self->test_fd);
    $self->test_fd(undef);
    $self->stop_autotest;
    $self->emit(tests_done => $response);
    $self->loop(0);
    $self->current_test_name('');
    $self->status('finished');
    $self->update_status_file;
}

sub _handle_command_check_screen ($self, $response, @) {
    $self->no_wait($response->{no_wait} // 0);
    return if $self->_postpone_backend_command_until_resumed($response);

    my %arguments = (
        mustmatch => $response->{mustmatch},
        timeout => $response->{timeout},
        check => $response->{check},
    );
    my $current_api_function = $response->{check} ? 'check_screen' : 'assert_screen';
    $self->_send_to_cmd_srv({
            check_screen => \%arguments,
            current_api_function => $current_api_function,
    });
    $self->tags($bmwqemu::backend->_send_json(
            {
                cmd => 'set_tags_to_assert',
                arguments => \%arguments,
            })->{tags});
    $self->current_api_function($current_api_function);
}

sub _handle_command_set_assert_screen_timeout ($self, $response, @) {
    my $timeout = $response->{timeout};
    $self->_send_to_cmd_srv({set_assert_screen_timeout => $timeout});
    $bmwqemu::backend->_send_json({
            cmd => 'set_assert_screen_timeout',
            arguments => $timeout,
    });
    $self->_respond_ok();
}

sub _handle_command_status ($self, $response, @) {
    $self->_respond({
            tags => $self->tags,
            running => $self->current_test_name,
            current_test_full_name => $self->current_test_full_name,
            current_api_function => $self->current_api_function,
            pause_test_name => $self->pause_test_name,
            pause_on_screen_mismatch => ($self->pause_on_screen_mismatch // Mojo::JSON->false),
            pause_on_next_command => $self->pause_on_next_command,
            pause_on_failure => $self->pause_on_failure,
            test_execution_paused => $self->reason_for_pause,
            devel_mode_major_version => $OpenQA::Isotovideo::Interface::developer_mode_major_version,
            devel_mode_minor_version => $OpenQA::Isotovideo::Interface::developer_mode_minor_version,
    });
}

sub _handle_command_version ($self, $response, @) {
    $self->_respond({
            test_git_hash => $bmwqemu::vars{TEST_GIT_HASH},
            needles_git_hash => $bmwqemu::vars{NEEDLES_GIT_HASH},
            version => $OpenQA::Isotovideo::Interface::version,
    });
}

sub _handle_command_read_serial ($self, $response, @) {
    # This will stop to work if we change the serialfile after the initialization because of the fork
    my ($serial, $pos) = $bmwqemu::backend->{backend}->read_serial($response->{position});
    $self->_respond({serial => $serial, position => $pos});
}

sub _handle_command_send_clients ($self, $response, @) {
    delete $response->{cmd};
    delete $response->{json_cmd_token};
    $self->_send_to_cmd_srv($response);
    $self->_respond_ok();
}

sub update_status_file ($self) {
    my $coder = Cpanel::JSON::XS->new->pretty->canonical;
    my $data = {
        test_execution_paused => $self->reason_for_pause,
        status => $self->status,
        current_test => $self->current_test_name,
    };
    my $json = $coder->encode($data);

    my $tmp = AUTOINST_STATUSFILE . ".$$.tmp";
    path($tmp)->spurt($json);
    rename $tmp, AUTOINST_STATUSFILE or die $!;
}

sub _calc_check_delta ($self) {
    # an estimate of eternity
    my $delta = $self->last_check_seconds ? tv_interval([$self->last_check_seconds, $self->last_check_microseconds]) : 100;
    # sleep the remains of one second if $delta > 0
    my $timeout = $delta > 0 ? 1 - $delta : 0;
    $self->timeout($timeout < 0 ? 0 : $timeout);
    return $delta;
}

sub _update_last_check ($self) {
    my ($last_check_seconds, $last_check_microseconds) = gettimeofday;
    $self->last_check_seconds($last_check_seconds);
    $self->last_check_microseconds($last_check_microseconds);
}

sub check_asserted_screen ($self) {
    if ($self->no_wait) {
        # prevent CPU overload by waiting at least a little bit
        $self->timeout(0.1);
    }
    else {
        $self->_calc_check_delta;
        # come back later, avoid too often called function
        return if $self->timeout > 0.05;
    }
    $self->_update_last_check;
    my $rsp = $bmwqemu::backend->_send_json({cmd => 'check_asserted_screen'}) || {};
    # the test needs that information
    $rsp->{tags} = $self->tags;
    if ($rsp->{found} || $rsp->{timeout}) {
        myjsonrpc::send_json($self->test_fd, {ret => $rsp});
        $self->clear_tags_and_timeout();
    }
    else {
        $self->_calc_check_delta unless $self->no_wait;
    }
}

sub _read_response ($self, $rsp, $fd) {
    if (!defined $rsp) {
        fctwarn sprintf("THERE IS NOTHING TO READ %d %d %d", fileno($fd), fileno($self->test_fd), fileno($self->cmd_srv_fd));
        $self->loop(0);
    } elsif ($fd == $self->backend_out_fd) {
        $self->send_to_backend_requester({ret => $rsp->{rsp}});
    } else {
        $self->process_command($fd, $rsp);
    }
}

sub run ($self) {
    # now we have everything, give the tests a go
    $self->test_fd->write("GO\n");

    my $io_select = IO::Select->new();
    $io_select->add($self->test_fd);
    $io_select->add($self->cmd_srv_fd);
    $io_select->add($self->backend_out_fd);

    while ($self->loop) {
        my ($ready_for_read, $ready_for_write, $exceptions) = IO::Select::select($io_select, undef, $io_select, $self->timeout);
        for my $readable (@$ready_for_read) {
            my $rsp = myjsonrpc::read_json($readable);
            $self->_read_response($rsp, $readable);
            last unless defined $rsp;
        }
        $self->check_asserted_screen if defined($self->tags);
    }
    $self->stop_command_processing;
    return 0;
}

1;
