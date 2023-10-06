#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin qw($Bin $Script);
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Exception;
use Test::Mock::Time;
use Test::MockModule;
use Test::MockObject;
use Test::Output;
use Test::Warnings qw(:all :report_warnings);
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';
use Mojo::File qw(path tempfile);
use Mojo::JSON 'decode_json';
use backend::baseclass;
use POSIX qw(tzset pause _exit);
use Mojo::File qw(tempdir path);
use Mojo::Util qw(scope_guard);
use IO::Pipe;
use bmwqemu ();
use cv;
use log();

cv::init;
require tinycv;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

# make the test time-zone neutral
$ENV{TZ} = 'UTC';
tzset;

log::init_logger;

my $baseclass_mock = Test::MockModule->new('backend::baseclass');
my @requested_screen_updates;
$baseclass_mock->redefine(run_capture_loop => sub {
        sleep 5;    # simulate that time passes (mocked via Test::Mock::Time)
        $baseclass_mock->original('run_capture_loop')->(@_);
});
$baseclass_mock->redefine(request_screen_update => sub ($self, $args) {
        is $args->{incremental}, 0, 'screen update is always expected to be non-incremental within this test';
        push @requested_screen_updates, [$args];
});

my $baseclass = backend::baseclass->new();

subtest 'format_vtt_timestamp' => sub {
    my $timestamp = 1543917024.24791;
    $baseclass->{video_frame_number} = 0;
    is($baseclass->format_vtt_timestamp($timestamp),
        "\n0\n00:00:00.000 --> 00:00:00.041\n[2018-12-04T09:50:24.247]\n",
        'frame number 0'
    );

    $timestamp += .1;
    $baseclass->{video_frame_number} = 1;
    is($baseclass->format_vtt_timestamp($timestamp),
        "\n1\n00:00:00.041 --> 00:00:00.083\n[2018-12-04T09:50:24.347]\n",
        'frame number 1'
    );
};

subtest 'not implemented' => sub {
    local @dummy::ISA = ('backend::baseclass');
    my $dummy = bless {}, 'dummy';
    my @tests = (
        [power => 23],
        [insert_cd =>],
        [eject_cd =>],
        [eject_cd => 23],
        [do_start_vm => 23,],
        [do_start_vm => 23, 42],
        [do_stop_vm => 23,],
        [do_stop_vm => 23, 42],
        [stop =>],
        [cont =>],
        [do_extract_assets => 23],
        [switch_network => 23],
        [save_memory_dump => 23],
        [save_storage => 23]
    );
    for my $test (@tests) {
        my ($m, @args) = @$test;
        eval { $dummy->$m(@args) };
        my $err = $@;
        like $err, qr{backend method '$m' not implemented for class 'dummy'}, "notimplemented() works for '\$self->$m(@args)'";
    }
};

is $baseclass->can_handle, undef, 'can_handle returns false by default';
is $baseclass->is_shutdown, -1, 'can call is_shutdown default implementation';
is_deeply $baseclass->cpu_stat, [], 'can call cpu_stat empty default implementation';
throws_ok { $baseclass->handle_command({cmd => 'power'}) } qr/not implemented/, 'handle_command executes specified command';

subtest 'SSH utilities' => sub {
    my $ssh_expect = {username => 'root', password => 'password', hostname => 'foo.bar', port => undef};
    my $fail_on_channel_call = undef;
    my $ssh_auth_ok = 1;
    my $ssh_obj_data = {};    # used to store Net::SSH2 fake data per object
    my $ssh_connect_error;
    my @net_ssh2_error = ();
    my $net_ssh2 = Test::MockModule->new('Net::SSH2');
    my @agent;
    $net_ssh2->redefine(new => sub {
            my ($class, %opts) = @_;
            my $self = Test::MockObject->new();
            my $id = $self->{my_custom_id} = bmwqemu::random_string(32);
            die 'Identifier not unique' if exists $ssh_obj_data->{$id};
            $ssh_obj_data->{$id} = $self;

            $self->mock(connect => sub {
                    my ($self, $hostname, $port) = @_;
                    return 0 if $ssh_connect_error;
                    is($hostname, $ssh_expect->{hostname}, 'Connect to correct hostname');
                    # if unspecified, default to port 22
                    is($port, $ssh_expect->{port} // 22, 'Connect to correct port');
                    $self->{hostname} = $hostname;
                    $self->{port} = $port;
                    $self->{blocking} = 0;
                    return 1;
            });
            $self->mock(hostname => sub { return $ssh_obj_data->{refaddr(shift)}->{hostname} });
            $self->mock(auth => sub {
                    my ($self, %args) = @_;
                    is($args{username}, $ssh_expect->{username}, 'Correct username for ssh connection');
                    is($args{password}, $ssh_expect->{password}, 'Correct password for ssh connection');
                    return 1;
            });
            $self->mock(auth_agent => sub { push @agent, [@_]; return 1 });
            $self->mock(auth_ok => sub {
                    my $self = shift;
                    $self->{connected} = !!$ssh_auth_ok;
                    return $ssh_auth_ok;
            });
            $self->mock(blocking => sub {
                    my ($self, $v) = @_;
                    $self->{blocking} = $v if defined($v);
                    return $self->{blocking};
            });
            $self->mock(disconnect => sub {
                    shift->{connected} = 0;
                    return 1;
            });
            $self->mock(error => sub { return @net_ssh2_error; });
            $self->mock(sock => sub {
                    my $self = shift;
                    unless ($self->{sock}) {
                        my $mock_sock = Test::MockObject->new();
                        $mock_sock->{ssh} = $self;
                        $self->{sock} = $mock_sock;
                    }
                    return $self->{sock};
            });
            $self->mock(channel => sub {
                    my $self = shift;
                    die("Not connected") unless ($self->{connected});
                    return $fail_on_channel_call = undef if $fail_on_channel_call;
                    my $mock_channel = Test::MockObject->new();
                    $mock_channel->{ssh} = $self;
                    $mock_channel->mock(exec => sub {
                            my ($self, $cmd) = @_;
                            $self->{cmd} = $cmd;
                            $self->{eof} = 0;
                            if ($cmd =~ /^(echo|test)/) {
                                $self->{stdout} = qx{$cmd};
                                $self->{exit_status} = $?;
                                $self->{stderr} = '';
                            }
                            return 1;
                    });
                    $mock_channel->mock(read2 => sub {
                            my ($self) = @_;
                            $self->{eof} = 1;
                            return ($self->{stdout}, $self->{stderr});
                    });
                    $mock_channel->mock(eof => sub { return shift->{eof}; });
                    $mock_channel->mock(blocking => sub { return shift->{ssh}->blocking(shift) });
                    $mock_channel->mock(pty => sub { return 1; });
                    $mock_channel->mock(send_eof => sub { return 1; });
                    $mock_channel->mock(exit_status => sub { shift->{exit_status}; });
                    $mock_channel->mock(ext_data => sub { my ($self, $v) = @_; $self->{ext_data} = $v; });
                    $mock_channel->mock(close => sub { return 1; });
                    return $mock_channel;
            });

            return $self;
    });
    sub refaddr ($host) { $host->{my_custom_id} }

    my ($ssh1, $ssh2, $ssh3, $ssh4, $ssh5, $ssh6, $ssh7, $ssh8, $ssh9);
    my %ssh_creds = (username => 'root', password => 'password', hostname => 'foo.bar');
    my $exp_log_new = qr/SSH connection to root\@foo\.bar established/;
    my $exp_log_existing = qr/Using existing SSH connection/;
    my $exp_log_renew = qr/Closing broken SSH connection[\s\S]+SSH connection to root\@foo\.bar established/;
    my $default_logger = $log::logger;
    $log::logger = Mojo::Log->new(level => 'debug');

    # 1st SSH instance
    stderr_like { $ssh1 = $baseclass->new_ssh_connection(%ssh_creds) } $exp_log_new, 'New SSH connection announced in logs 1';
    # 2nd SSH instance
    stderr_like { $ssh2 = $baseclass->new_ssh_connection(%ssh_creds) } $exp_log_new, 'New SSH connection announced in logs 2';
    # 3rd SSH instance
    stderr_like { $ssh3 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds) } $exp_log_new, 'New SSH connection announced in logs (first keep_open=>1)';
    stderr_unlike { $ssh4 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds) } $exp_log_new, 'No new SSH connection announced in logs';
    stderr_like { $ssh5 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds) } $exp_log_existing, 'Existing SSH connection announced in logs';

    # New connection for different username
    $ssh_expect->{username} = 'foo911';
    $exp_log_new = qr/SSH connection to foo911\@foo\.bar established/;
    # 4th SSH instance
    stderr_like { $ssh6 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds, username => 'foo911') } $exp_log_new, 'New SSH connection announced in logs -- username=foo911';

    # New connection using agent (instead of password)
    $exp_log_new = qr/SSH connection to foo912\@foo\.bar established/;
    stderr_like { $ssh9 = $baseclass->new_ssh_connection(keep_open => 0, %ssh_creds, username => 'foo912', password => undef) } $exp_log_new, 'New SSH connection announced in logs -- username=foo912';
    is scalar @agent, 1, 'auth agent called once' or diag explain \@agent;

    $ssh_expect->{username} = 'root';

    # New connection if keeped connection is broken
    $fail_on_channel_call = 1;
    # 5th SSH instance but 3rd get closed
    stderr_like { $ssh7 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds) } $exp_log_renew, 'Existing SSH connection announced in logs';

    # New connection using a different port
    $ssh_expect->{port} = 2222;
    $exp_log_new = qr/SSH connection to root\@foo\.bar:2222 established/;
    stderr_like { $ssh8 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds, port => 2222) } $exp_log_new, 'New SSH connection announced in logs -- port=2222';
    $ssh_expect->{port} = undef;

    $log::logger = $default_logger;

    # Double check references
    isnt(refaddr($ssh1), refaddr($ssh2), "Got new connection each call");
    is(refaddr($ssh3), refaddr($ssh4), "Got same connection with keep_open");
    is(refaddr($ssh4), refaddr($ssh5), "Got same connection with keep_open");
    isnt(refaddr($ssh5), refaddr($ssh6), "Got new connection with different credentials");
    isnt(refaddr($ssh5), refaddr($ssh7), "Got new connection, when SSH session got broke");
    isnt(refaddr($ssh4), refaddr($ssh8), "Got same connection with different ports");

    $ssh_auth_ok = 0;
    throws_ok(sub { $baseclass->new_ssh_connection(%ssh_creds) }, qr/Error connecting to/, 'Got exception on connection error');

    $ssh_auth_ok = 1;
    $ssh_expect->{password} = '';
    @agent = ();
    $baseclass->new_ssh_connection(%ssh_creds, password => '');
    is scalar @agent, 0, 'Empty password also accepted, auth_agent not called';

    $baseclass->new_ssh_connection(%ssh_creds, password => '', use_ssh_agent => 1);
    is scalar @agent, 1, 'auth_agent called via "use_ssh_agent" despite empty password';

    # check run_ssh_cmd() usage
    is($baseclass->run_ssh_cmd('echo -n "foo"', %ssh_creds), 0, 'Command successful exit');
    isnt($baseclass->run_ssh_cmd('test 23 -eq 42', %ssh_creds), 0, 'Command failed exit');
    my @output = $baseclass->run_ssh_cmd('echo -n "foo"', wantarray => 1, %ssh_creds);
    is_deeply(\@output, [0, 'foo', ''], 'Command successful exit with output');

    # Create a SSH session implecit with `run_ssh_cmd()`
    $ssh_expect->{password} = '2+3=5';
    is($baseclass->run_ssh_cmd('echo -n "foo"', %ssh_creds, password => '2+3=5'), 0, 'Allow SSH credentials per run_ssh_cmd() call');

    my $num_ssh_connect = scalar(keys(%{$ssh_obj_data}));
    $baseclass->run_ssh_cmd('echo -n "foo"', %ssh_creds, password => '2+3=5', keep_open => 0);
    is($num_ssh_connect + 1, scalar(keys(%{$ssh_obj_data})), 'Ensure run_ssh_cmd(keep_open => 0) uses a new SSH connection');

    my @connected_ssh = grep { $_->{connected} } values(%$ssh_obj_data);
    my @disconnected_ssh = grep { !$_->{connected} } values(%$ssh_obj_data);

    is(scalar(@connected_ssh), 8, "Expect 8 connected SSH connections");
    is($ssh1->{connected}, 1, "SSH connection ssh1 connected");
    is($ssh2->{connected}, 1, "SSH connection ssh2 connected");
    is($ssh7->{connected}, 1, "SSH connection ssh7 connected");
    is($ssh8->{connected}, 1, "SSH connection ssh8 connected");
    is($ssh9->{connected}, 1, "SSH connection ssh9 connected");
    # +1 unnamed connection form implicit run_ssh_cmd()

    is(scalar(@disconnected_ssh), 3, "Expect 3 disconnected SSH connections");
    is($ssh3->{connected}, 0, "SSH connection ssh3 disconnected");
    # +1 from auth failure
    # +1 run_ssh_cmd(keep_open => 0)

    $baseclass->close_ssh_connections();
    @connected_ssh = grep { $_->{connected} } values(%$ssh_obj_data);
    is scalar @connected_ssh, 5, 'Expect 5 connected SSH connections (ssh1, ssh2 and ssh9)';
    is($ssh1->{connected}, 1, "SSH connection ssh1 connected");
    is($ssh2->{connected}, 1, "SSH connection ssh2 connected");
    is($ssh9->{connected}, 1, "SSH connection ssh9 connected (user agent auth)");

    subtest 'Serial SSH' => sub {
        my $io_select_mock = Test::MockModule->new('IO::Select');
        $io_select_mock->redefine('add');
        $io_select_mock->redefine('remove');
        $baseclass->{select_read} = IO::Select->new;

        $ssh_expect = {username => 'serial', password => 'XXX', hostname => 'serial.host'};
        $num_ssh_connect = scalar(keys(%{$ssh_obj_data}));
        my ($ssh, $chan) = $baseclass->start_ssh_serial(username => 'serial', password => 'XXX', hostname => 'serial.host');
        is($num_ssh_connect + 1, scalar(keys(%{$ssh_obj_data})), 'Ensure start_ssh_serial() uses a new SSH connection');
        is($chan->{ext_data}, 'merge', 'STDOUT and STDERR are merged');
        is($ssh->blocking(), 0, 'We run SSH in none blocking mode');

        $baseclass->truncate_serial_file();
        my $expect_output = "FOO$/" x 4096;
        my $channel_read_string = $expect_output;
        $chan->mock(read => sub {
                my ($self, undef, $max) = @_;
                return unless (defined($channel_read_string));
                $max //= 4096;
                $_[1] = substr($channel_read_string, 0, $max);
                my $ret = length($_[1]);
                $channel_read_string = substr($channel_read_string, $ret);
                return $ret;
        });
        my $exit_value;
        stdout_is { $exit_value = $baseclass->check_ssh_serial($ssh->sock()) } $expect_output, 'Serial output is printed to STDOUT';
        is(path($baseclass->{serialfile})->slurp(), $expect_output, 'Serial output is written to serial file');
        is($exit_value, 1, 'Check return value on success');

        $channel_read_string = undef;
        @net_ssh2_error = (LIBSSH2_ERROR_EAGAIN, 'EAGAIN', 'Try later');
        stdout_is { $exit_value = $baseclass->check_ssh_serial($ssh->sock()) } '', 'No output on EAGAIN only';
        is($exit_value, 1, 'Check return value on EAGAIN');
        is($baseclass->{serial}, $ssh, 'Serial SSH exists after EGAIN');

        is($baseclass->check_ssh_serial(42), 0, 'Return 0 when called with wrong socket');
        is $baseclass->check_ssh_serial($ssh->sock, 1), 1, 'early return if $write is set';

        @net_ssh2_error = (666, 'UNKNOWN', 'OHA');
        stdout_is { $exit_value = $baseclass->check_ssh_serial($ssh->sock()) } '', 'No output on ERROR only';
        is($exit_value, 1, 'Check return value on EAGAIN');
        is($baseclass->{serial}, undef, 'SSH serial get disconnected on unknown read ERROR');

        is($baseclass->check_ssh_serial(23), 0, 'Return 0 if SSH serial isn\'t connected');
    };

    subtest 'handling connection error' => sub {
        my $mockbmw = Test::MockModule->new('bmwqemu');
        my $diag = '';
        $mockbmw->redefine(diag => sub { $diag .= $_[0] });
        $bmwqemu::vars{SSH_CONNECT_RETRY} = 2;
        $ssh_connect_error = 1;
        $exp_log_new = qr/Could not connect to serial\@foo, Retrying/;
        $baseclass->new_ssh_connection(keep_open => 0, hostname => 'foo', username => 'serial', password => 'XXX');
        like $diag, qr/Could not connect to serial\@foo, Retrying/, 'connection error logged';
    };
};

sub _prepare_video_encoder ($baseclass) {
    my @pipes;
    for (1 .. 3) {
        my $pipe = IO::Pipe->new;
        my $pid = fork;
        if ($pid) { $pipe->writer }
        elsif (defined $pid) {
            $pipe->reader;
            my @lines = <$pipe>;
            exit;
        }    # uncoverable statement
        else { die "Couldn't fork" }    # uncoverable statement
        push @pipes, [$pid => $pipe];
    }
    my $pipe = $pipes[2]->[1];
    my $pid = $pipes[2]->[0];
    my $encoder = {name => 'foo', pipe => $pipe};
    $baseclass->{video_encoders} = {$pid => $encoder};

    my $encoder_pipe = $pipes[0]->[1];
    $baseclass->{encoder_pipe} = $encoder_pipe;
    my $external_video_encoder_cmd_pipe = $pipes[1]->[1];
    $baseclass->{external_video_encoder_cmd_pipe} = $external_video_encoder_cmd_pipe;
    $baseclass->{select_read} = OpenQA::NamedIOSelect->new;
    $baseclass->{select_write} = OpenQA::NamedIOSelect->new;
    $baseclass->{select_read}->add($encoder_pipe, 'baseclass::encoder_pipe');
    $baseclass->{select_write}->add($encoder_pipe, 'baseclass::encoder_pipe');
    $baseclass->{select_read}->add($external_video_encoder_cmd_pipe, 'baseclass::external_video_encoder_cmd_pipe');
    $baseclass->{select_write}->add($external_video_encoder_cmd_pipe, 'baseclass::external_video_encoder_cmd_pipe');
    $baseclass->{video_frame_data} = [5 .. 10];
    $baseclass->{external_video_encoder_image_data} = [55 .. 60];
}

subtest 'video-encoder' => sub {
    my $baseclass = backend::baseclass->new();
    _prepare_video_encoder($baseclass);
    $baseclass->stop_vm;
    is scalar @{$baseclass->{video_frame_data}}, 0, 'video_frame_data array is empty';
    is scalar @{$baseclass->{external_video_encoder_image_data}}, 0, 'external_video_encoder_image_data array is empty';
    is $baseclass->{video_encoders}, undef, 'video_encoders entry was deleted';

    my $mock = Test::MockModule->new('backend::baseclass');
    $mock->redefine(_write_buffered_data_to_file_handle => sub { die "FAIL!" });
    my $mockbmw = Test::MockModule->new('bmwqemu');
    my @diag;
    $mockbmw->redefine(diag => sub { push @diag, @_ });
    _prepare_video_encoder($baseclass);
    $baseclass->stop_vm;
    like "@diag", qr{Unable to pass remaining frames to video encoder}, 'catch block called like expected';
};

subtest 'running test' => sub {
    my $base_state = path(bmwqemu::STATE_FILE);
    $base_state->remove;
    throws_ok { $baseclass->run(my $channel_in, my $channel_out) } qr/fdopen Invalid argument/, 'error logged';
    my $state = decode_json($base_state->slurp);
    if (is(ref $state, 'HASH', 'state file contains object')) {
        is($state->{component}, 'backend', 'state file contains component message');
        like($state->{msg}, qr/fdopen Invalid argument/, 'state file contains error message');
    }
};

subtest 'wait_serial' => sub {
    #mock console settings
    my $current_console = Test::MockObject->new();
    $current_console->set_false('is_serial_terminal');
    $baseclass->{current_console} = $current_console;

    #mock content of serial0.txt
    path($baseclass->{serialfile})->spew(<<EOT);
Just a simple text
Just a simple another text that will disappear
Welcome to GRUB2
BdsDxe: loading Boot0001 "UEFI Misc Device" from PciRoot(0x0)/Pci(0x8,0x0)
Some leftover
UUID=2e41327c-ca46-4c5c-93a2-b41933d40ca8 btrfs 24G 589.7M 21.4G 2% /
UUID=2e41327c-ca46-4c5c-93a2-b41933d40ca8 btrfs 24G 589.7M 21.4G 2% /opt
BdsDxe: starting Boot0001 "UEFI Misc Device" from PciRoot(0x0)/Pci(0x8,0x0)
Welcome to GRUB!
EOT

    # set default arguments for wait_serial set by testapi.pm
    my %dargs = (timeout => 90, expect_not_found => 0, quiet => undef, no_regex => 0, buffer_size => undef, record_output => undef);

    is_deeply($baseclass->wait_serial({%dargs, regexp => 'simple', no_regex => 1}), {matched => 1, string => 'Just a simple'}, 'Test string literal on the first line');
    is_deeply($baseclass->wait_serial({%dargs, regexp => 'GRUB2', no_regex => 1}), {matched => 1, string => " text\nJust a simple another text that will disappear\nWelcome to GRUB2"}, 'Multiline literal string match');
    is_deeply($baseclass->wait_serial({%dargs, regexp => qr/loading\s+Boot\d{4}\s+.*\)/}), {matched => 1, string => qq[\nBdsDxe: loading Boot0001 "UEFI Misc Device" from PciRoot(0x0)/Pci(0x8,0x0)]}, 'One line regex match');
    is_deeply($baseclass->wait_serial({%dargs, regexp => qr/\(0x8,0x0\)/}), {matched => 1, string => '
Some leftover
UUID=2e41327c-ca46-4c5c-93a2-b41933d40ca8 btrfs 24G 589.7M 21.4G 2% /
UUID=2e41327c-ca46-4c5c-93a2-b41933d40ca8 btrfs 24G 589.7M 21.4G 2% /opt
BdsDxe: starting Boot0001 "UEFI Misc Device" from PciRoot(0x0)/Pci(0x8,0x0)'}, 'Test regex match multiline leftover');
    is_deeply($baseclass->wait_serial({%dargs, regexp => qr/welcome$/, timeout => 1}), {matched => 0, string => "\nWelcome to GRUB!\n"}, "Test regex mismatch");
    is_deeply($baseclass->wait_serial({%dargs, regexp => 'something wrong', timeout => 1, no_regex => 1}), {matched => 0, string => "\nWelcome to GRUB!\n"}, "Test string literal mismatch");

    subtest 'waiting for serial terminal' => sub {
        my $fake_screen = $baseclass->{current_screen} = Test::MockObject->new->set_true('read_until');
        $current_console->set_true('is_serial_terminal');
        is_deeply $baseclass->is_serial_terminal({}), {yesorno => 1}, 'is_serial_terminal returns expected result';
        $baseclass->wait_serial({});
        $fake_screen->called_ok('read_until', 'read_until is called');
        $baseclass->{current_screen} = undef;
    };
};

subtest 'waiting for screen change or still screen' => sub {
    my @sent_json;
    my $rpc_mock = Test::MockModule->new('myjsonrpc')->redefine(send_json => sub (@args) { push @sent_json, [@args] });
    my %expected_response = (json_cmd_token => 'faketoken', rsp => {sim => 10_000, elapsed => 10, timed_out => !!0});
    $baseclass->{rsppipe} = 41;
    $baseclass->{_postponed_cmd_token} = 'faketoken';

    subtest 'enqueuing waiting for screen change' => sub {
        is_deeply $baseclass->wait_screen_change({similarity_level => 10_000, timeout => 10}), {postponed => 1}, 'reply is postponed';
        is ref $baseclass->{_wait_screen_change}, 'HASH', 'check for screen change enqueued';
    };
    subtest 'screen has not changed and timeout has not been exceeded' => sub {
        $baseclass->{_wait_screen_change}->{starttime} = 20;
        ok !$baseclass->_check_for_screen_change(30), 'falsy return';    # assume time difference of 10 seconds, exactly within timeout
        is ref $baseclass->{_wait_screen_change}, 'HASH', 'still waiting for screen change';
        is_deeply \@sent_json, [], 'no response sent' or diag explain \@sent_json;
    };
    subtest 'screen has changed' => sub {
        $baseclass->{_wait_screen_change}->{starttime} = 20;
        $baseclass->{_wait_screen_change}->{similarity_level} += 1;    # let's just be satisfied with a higher similarity
        ok $baseclass->_check_for_screen_change(30), 'truthy return';    # assume time difference of 10 seconds, exactly within timeout
        ok !$baseclass->{_wait_screen_change}, 'no longer waiting for screen change';
        is_deeply \@sent_json, [[$baseclass->{rsppipe}, \%expected_response]], 'response sent' or diag explain \@sent_json;
    };
    subtest 'timeout exceeded' => sub {
        is_deeply $baseclass->wait_screen_change({similarity_level => 10, timeout => 4}), {postponed => 1}, 'reply is postponed';
        $baseclass->{_wait_screen_change}->{starttime} = 20;
        @sent_json = ();
        ok $baseclass->_check_for_screen_change(25), 'truthy return';    # time difference of 5 seconds, exactly one second passed the timeout
        $expected_response{rsp}->{timed_out} = 1;
        $expected_response{rsp}->{elapsed} = 5;
        ok !$baseclass->{_wait_screen_change}, 'no longer waiting for screen change';
        is_deeply \@sent_json, [[$baseclass->{rsppipe}, \%expected_response]], 'response sent' or diag explain \@sent_json;
    };

    my ($starttime, $set_reference_screenshot_called);
    @sent_json = ();
    subtest 'enqueuing waiting for still screen' => sub {
        $baseclass->reference_screenshot(undef)->last_image('fake image');
        is_deeply $baseclass->wait_still_screen({similarity_level => 50, timeout => 11, stilltime => 11}), {postponed => 1}, 'reply is postponed';
        is ref $baseclass->{_wait_still_screen}, 'HASH', 'check for still screen enqueued';
        is $baseclass->reference_screenshot, $baseclass->last_image, 'reference screenshot set';
        ok $starttime = $baseclass->{_wait_still_screen}->{starttime}, 'starttime initialized';
    };
    subtest 'screen has not changed and timeout has not been exceeded but screen is not still long enough' => sub {
        $baseclass->reference_screenshot(undef)->last_image(undef);
        $baseclass_mock->redefine(set_reference_screenshot => sub ($self, $args) { $set_reference_screenshot_called = 1 });
        ok !$baseclass->_check_for_still_screen($starttime + 10), 'falsy return';    # assume time difference of 10 seconds, exactly one second before stilltime
        is ref $baseclass->{_wait_still_screen}, 'HASH', 'still checking for still screen as it is not still for long enough';
        is $baseclass->{_wait_still_screen}->{lastchangetime}, $starttime, 'still "streak" continues';
        ok !$set_reference_screenshot_called, 'reference screenshot has not been updated';
        is_deeply \@sent_json, [], 'no response sent' or diag explain \@sent_json;
    };
    subtest 'screen has changed and timeout has not been exceeded' => sub {
        $baseclass_mock->redefine(similiarity_to_reference => {sim => 49});    # exactly one "level" below the set similarity level
        ok !$baseclass->_check_for_still_screen($starttime + 10), 'falsy return';    # assume time difference of 10 seconds, exactly one second before stilltime
        is ref $baseclass->{_wait_still_screen}, 'HASH', 'still checking for still screen as the streak has ended but timeout not exceeded';
        is $baseclass->{_wait_still_screen}->{lastchangetime}, $starttime + 10, 'still "streak" has ended';
        ok $set_reference_screenshot_called, 'reference screenshot has been updated';
        is_deeply \@sent_json, [], 'no response sent' or diag explain \@sent_json;
    };
    subtest 'broken streak means stilltime needs to be awaited again from the start' => sub {
        $baseclass_mock->redefine(similiarity_to_reference => {sim => 50});    # exactly "still" enough by the set similarity level
        ok !$baseclass->_check_for_still_screen($starttime + 11), 'falsy return'; # assume time difference of 11 seconds since start, exactly matching stilltime, exactly within timeout
        is ref $baseclass->{_wait_still_screen}, 'HASH', 'still waiting for still screen even screen is still and stilltime has passed as streak was interrupted';
    };
    subtest 'screen is still long enough and timeout has not been exceeded' => sub {
        $baseclass_mock->redefine(similiarity_to_reference => {sim => 50});    # exactly "still" enough by the set similarity level
        ok $baseclass->_check_for_still_screen($baseclass->{_wait_still_screen}->{lastchangetime} + 11), 'truthy return'; # assume time difference of 11 seconds since last change, exactly matching stilltime
        is $baseclass->{_wait_still_screen}, undef, 'no longer checking for still screen' or diag explain $baseclass->{_wait_still_screen};
        $expected_response{rsp} = {timed_out => 0, elapsed => 21, sim => 50};
        is_deeply \@sent_json, [[$baseclass->{rsppipe}, \%expected_response]], 'response sent' or diag explain \@sent_json;

        # note: Here we waited actually 21 seconds (1st streak broke after 10 s, 2st streak long enough after 11 s) which exceeds the timeout but it is
        # still not considered a timeout. That is ok because we have pretended that the _check_for_still_screen invocation happened after the timeout which
        # could also happen in reality if the backend's loop is for some reason busy with something else and can therefore not run the next check in time.
        # Supposedly we still want to consider this a success then.
    };
    subtest 'timeout has been exceeded before screen is still long enough' => sub {
        @sent_json = ();
        is_deeply $baseclass->wait_still_screen({similarity_level => 50, timeout => 11, stilltime => 11}), {postponed => 1}, 'enqueued a new still screen wait';
        ok $baseclass_mock->redefine(similiarity_to_reference => {sim => 49}), 'truthy return';    # exactly one "level" below the set similarity level
        $baseclass->_check_for_still_screen($starttime + 12);    # assume time difference of 11 seconds since last change, just exceeding timeout
        is $baseclass->{_wait_still_screen}, undef, 'no longer checking for still screen' or diag explain $baseclass->{_wait_still_screen};
        $expected_response{rsp} = {timed_out => 1, elapsed => 12, sim => 49};
        is_deeply \@sent_json, [[$baseclass->{rsppipe}, \%expected_response]], 'response sent' or diag explain \@sent_json;
    };

    $baseclass_mock->noop('similarity_to_reference');
    $baseclass->{rsppipe} = undef;
};

subtest check_select_rate => sub {
    my $time_limit = 3;    # _CHKSEL_RATE_WAIT_TIME
    my $hit_limit = 10;    # _CHKSEL_RATE_HITS

    subtest recover_if_not_all_hit_the_limit => sub {
        my $buckets = {};
        for my $loop (1 .. ($hit_limit - 1)) {
            for my $fd (42 .. 45) {
                is(backend::baseclass::check_select_rate($buckets, $time_limit, $hit_limit, $fd, 0), 0, "$loop hit on $fd return 0");
            }
        }
        is(backend::baseclass::check_select_rate($buckets, $time_limit, $hit_limit, 42, 0), 0, "The fd 42 does not hit the limit, as time isn't up");
        is(backend::baseclass::check_select_rate($buckets, $time_limit, $hit_limit, 42, $time_limit + 1), 0, "The fd 42 does not hit the limit, cause not all fd's hit it!");
        is($buckets->{BUCKET}->{42}, 1, "The counter of fd 42 was reset to 1");
    };

    subtest single_fd_hit_the_limit => sub {
        my $buckets = {};
        for my $loop (1 .. ($hit_limit)) {
            is(backend::baseclass::check_select_rate($buckets, $time_limit, $hit_limit, 42, 0), 0, "$loop hit on fd 42 after reset.");
        }
        is(backend::baseclass::check_select_rate($buckets, $time_limit, $hit_limit, 42, $time_limit + 1), 1, "The fd 42 hit now the limit.");
    };

    subtest all_fds_hit_the_limit => sub {
        my $buckets = {};
        for my $loop (1 .. ($hit_limit)) {
            for my $fd (42 .. 45) {
                is(backend::baseclass::check_select_rate($buckets, $time_limit, $hit_limit, $fd, 0), 0, "$loop hit on $fd return 0");
            }
        }
        is(backend::baseclass::check_select_rate($buckets, $time_limit, $hit_limit, 42, $time_limit + 1), 1, "Hit the limit, as all fds hit it!");
    };
};

subtest 'requesting full screen update' => sub {
    is scalar @requested_screen_updates, 0, 'no screen update requested so far';
    $baseclass->last_image(Test::MockObject->new->set_list(search => 0, []));
    $baseclass->assert_screen_tags(['foo']);
    $baseclass->assert_screen_needles([{}]);
    $baseclass_mock->redefine(_time_to_assert_screen_deadline => 41);
    $baseclass->screenshot_interval(20);
    $baseclass->check_asserted_screen({});
    is scalar @requested_screen_updates, 0, 'no screen update requested';
    $baseclass_mock->redefine(_time_to_assert_screen_deadline => 40);
    $baseclass->check_asserted_screen({});
    is scalar @requested_screen_updates, 1, 'screen update requested as deadline nearing end';
    is scalar @requested_screen_updates, 1, 'no further screen update requested';
    $baseclass_mock->redefine(_time_to_assert_screen_deadline => 2 * backend::baseclass::FULL_UPDATE_REQUEST_FREQUENCY);
    $baseclass->check_asserted_screen({});
    is scalar @requested_screen_updates, 2, 'screen update triggered periodically';
};

is($baseclass->get_wait_still_screen_on_here_doc_input({}), 0, 'wait_still_screen on here doc is off by default!');

subtest 'corner cases of do_capture/run_capture_loop' => sub {
    # note: This test covers a few corner cases of do_capture that are not otherwise covered anyways:
    #       using external video encoder, stall detection, screen update request, unresponsive console

    # prepare file handle to have something to read from
    open my $file_fh, '<', "$Bin/$Script";    # just open this Perl script itself
    my $file_no = fileno $file_fh;

    # mock IO::Select to return external video encoder fh and other fh as ready-to-write and the prepare file handle read-to-read
    # note: The "other" file handle is ignored by the current implementation so when writing this test I assume
    #       this is the intended behavior - although the condition in the code looks a bit odd.
    my $video_encoder_fh = 41;
    my $external_video_encoder_fh = 42;
    my $other_fh = 43;
    my $fake_pipe = IO::Handle->new_from_fd(fileno(STDOUT), "w");    # create *some* handle to use as cmdpipe
    my $io_select_mock = Test::MockModule->new('IO::Select');
    my $io_select_timeout;
    my @io_select_res = ([$file_fh], [$external_video_encoder_fh, $other_fh]);
    $io_select_mock->redefine(select => sub ($self, $read_select, $write_select, $exception, $timeout) {
            $io_select_timeout = $timeout;
            return @io_select_res;
    });

    # prepare test $baseclass with data to be passed to external video encoder and timeout triggering stall detection
    $baseclass->{current_console}->{testapi_console} = 'fake-console';
    $baseclass->{select_read} = OpenQA::NamedIOSelect->new;
    $baseclass->{select_write} = OpenQA::NamedIOSelect->new;
    $baseclass->{encoder_pipe} = $video_encoder_fh;
    $baseclass->{external_video_encoder_cmd_pipe} = $external_video_encoder_fh;
    $baseclass->{external_video_encoder_image_data} = 'data for external encoder';
    $baseclass->{cmdpipe} = $fake_pipe;
    $baseclass->assert_screen_last_check(1);
    $baseclass->last_screenshot(1);    # should set stall_detected flag
    $baseclass->update_request_interval(0);    # always exercise the update request here
    $baseclass->screenshot_interval(20);    # set some arbitrarily high value here, supposed to be passed as select timeout
    $baseclass->last_update_request(0);
    $baseclass_mock->redefine(request_screen_update => sub ($self, $args = undef) {
            $self->{cmdpipe} = undef;    # ensure we'll exit the while loop after one iteration
    });
    $baseclass_mock->redefine(_write_buffered_data_to_file_handle => sub ($self, @args) {
            push @{$self->{writes}}, \@args;
    });
    $baseclass_mock->redefine(check_select_rate => sub ($buckets, @args) {
            $buckets->{BUCKET}->{$file_no} = 'some count';
            return 1;    # pretend console is not responding
    });
    ok !$baseclass->stall_detected, 'no stall detected so far';

    # actually run the loop
    $log::logger = Mojo::Log->new(level => 'debug');
    combined_like { $baseclass->run_capture_loop } qr/file descriptor $file_no.*not responding/, 'loop aborted due to unresponsive console';
    ok $baseclass->stall_detected, 'stall detected';
    is $io_select_timeout, 20, 'set screenshot_interval used as select timeout';
    is_deeply $baseclass->{writes},
      [['External encoder', 'data for external encoder', $external_video_encoder_fh]],
      'data written to external video encoder'
      or diag explain $baseclass->{writes};

    # run again, this time assuming no handles are ready and we're waiting for a screen change with no_wait
    @io_select_res = ([], []);
    $baseclass->{cmdpipe} = $fake_pipe;
    $baseclass->{_wait_screen_change} = {no_wait => 1, starttime => 0, elapsed => 0, timeout => 10, similarity_level => 50};
    $baseclass->do_capture;
    is $io_select_timeout, 0.1, 'very low timeout used as select timeout for wait_screen_change with no_wait parameter';
};

subtest 'auto-detection of external video encoder' => sub {
    ok defined backend::baseclass::_ffmpeg_banner, 'ffmpeg banner is always defined (might be an empty string, though)';
    $baseclass_mock->redefine(_ffmpeg_banner => "--enable-encoder='libsvtav1,libvpx_vp9'");    # not supposed to match
    ok !$baseclass->_start_external_video_encoder_if_configured, 'external video encoder not used if SVT-AV1/VP9 not available';
    $baseclass_mock->redefine(_ffmpeg_banner => '--enable-libsvtav1 --enable-libvpx');
    like $baseclass->_auto_detect_external_video_encoder, qr/^ffmpeg.*ppm.*yuv420p.*libsvtav1/, 'SVT-AV1 preferably used if available';
    $baseclass_mock->redefine(_ffmpeg_banner => '--enable-libvpx');
    like $baseclass->_auto_detect_external_video_encoder, qr/^ffmpeg.*ppm.*yuv420p.*libvpx-vp9/, 'VP9 used as 2nd option if available';
};

subtest 'starting external video encoder and enqueuing screenshot data for it' => sub {
    my $video_encoders = $baseclass->{video_encoders} = {};
    $bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_CMD} = 'true -o %OUTPUT_FILE_NAME% "trailing arg"';
    $log::logger->level('info');
    ok $baseclass->_start_external_video_encoder_if_configured, 'video encoder started';
    my @video_encoder_pids = keys %$video_encoders;
    is scalar @video_encoder_pids, 1, 'one video encoder started';
    my $launched_video_encoder = $video_encoders->{$video_encoder_pids[0]};
    subtest 'params passed as expected' => sub {
        is $launched_video_encoder->{name}, 'external video encoder', 'name set';
        like $launched_video_encoder->{cmd}, qr/true -o video\.webm "trailing arg"/, 'command correct, %OUTPUT_FILE_NAME% substituted';
    } or diag explain $video_encoders;

    # launch again without %OUTPUT_FILE_NAME%
    $video_encoders = $baseclass->{video_encoders} = {};
    $bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_CMD} = 'true "trailing arg"';
    ok $baseclass->_start_external_video_encoder_if_configured, 'video encoder started';
    @video_encoder_pids = keys %$video_encoders;
    is scalar @video_encoder_pids, 1, 'one video encoder started (without %OUTPUT_FILE_NAME%)';
    like $video_encoders->{$video_encoder_pids[0]}->{cmd}, qr/true "trailing arg" 'video\.webm'/, 'command correct, output file appended'
      or diag explain $video_encoders;

    # now enqueue image data
    my $image_data = $baseclass->{external_video_encoder_image_data} = [];
    my $vtt_caption_file = tempfile;
    open $baseclass->{vtt_caption_file}, '>', $vtt_caption_file;
    $baseclass->screenshot_interval(-1);    # provoke warning about enqueueing screenshot taking too long to cover this as well
    $baseclass->last_image(tinycv::new(1, 1));
    $log::logger = Mojo::Log->new(level => 'debug');
    combined_like { $baseclass->enqueue_screenshot(tinycv::new(1, 1)) } qr/enqueue_screenshot took/, 'warning about time (1)';
    is substr($baseclass->{video_frame_data}->[-2], 0, 2), 'E ', 'new image passed to built-in video encoder (to make png)';
    is scalar @$image_data, 1, 'image data enqueued for external encoder';

    # enqueue the same image again
    combined_like { $baseclass->enqueue_screenshot(tinycv::new(1, 1)) } qr/enqueue_screenshot took/, 'warning about time (2)';
    close $baseclass->{vtt_caption_file};
    like $vtt_caption_file->slurp, qr/\d\d:.* --> \d\d:/, 'vtt caption written';
    is $baseclass->{video_frame_data}->[-1], "R\n", 'last frame just repeated, no new image passed to built-in video encoder';
    is scalar @$image_data, 2, 'further image data enqueued for external encoder';
};

subtest 'console functions' => sub {
    my $consoles = $testapi::distri->{consoles} = {};
    my @console_func = qw(reset disable activate);
    my $foo_console = $consoles->{foo} = Test::MockObject->new->set_true(@console_func, 'load_snapshot');
    my $bar_console = $consoles->{bar} = Test::MockObject->new->set_true(@console_func, 'save_snapshot');
    my $baz_console = $consoles->{baz} = Test::MockObject->new->set_true(@console_func);
    $foo_console->{activated} = 1;
    $baz_console->{args}->{persistent} = 1;

    $baseclass->reset_consoles({});
    $consoles->{$_}->called_pos_ok(1, 'reset', "$_ reset") for qw(foo bar);
    ok !$baz_console->called('reset'), 'persistent console not reset';
    $baseclass->deactivate_console({testapi_console => 'foo'});
    $consoles->{$_}->called_pos_ok(2, 'disable', "$_ disabled via deactivate_console") for qw(foo);

    $_->clear for values %$consoles;
    $consoles->{cannot_disable} = Test::MockObject->new;    # ok if consoles cannot be disabled
    $baseclass->disable_consoles;
    $consoles->{$_}->called_pos_ok(1, 'disable', "$_ disabled via disable_consoles") for qw(foo bar baz);
    $_->clear for values %$consoles;

    $baseclass->reenable_consoles;
    $consoles->{$_}->called_pos_ok(1, 'activate', "$_ activated") for qw(foo);
    ok !$consoles->{$_}->called('activate'), "$_ skipped (activated not set / cannot disable)" for qw(bar baz cannot_disable);

    $_->clear for values %$consoles;
    $baseclass->save_console_snapshots('foo');
    $consoles->{$_}->called_pos_ok(1, 'save_snapshot', "$_ saved") for qw(bar);
    ok !$consoles->{$_}->called('save_snapshot'), "$_ skipped (cannot save)" for qw(foo baz cannot_disable);

    $_->clear for values %$consoles;
    $baseclass->load_console_snapshots('bar');
    $consoles->{$_}->called_pos_ok(1, 'load_snapshot', "$_ loaded") for qw(foo);
    ok !$consoles->{$_}->called('load_snapshot'), "$_ skipped (cannot load)" for qw(bar baz cannot_disable);
};

subtest 'bouncer functions' => sub {
    my @bouncer_functions = qw(hold_key release_key type_string mouse_set mouse_hide mouse_button get_last_mouse_set);
    my $fake_screen = $baseclass->{current_screen} = Test::MockObject->new->set_true(@bouncer_functions);
    $baseclass->$_({}) for @bouncer_functions;
    $fake_screen->called_ok($_, "function '$_' bounced") for @bouncer_functions;
};

subtest 'reduce to biggest changes' => sub {
    my $dummy_img = tinycv::new(1, 1);
    my @imglist = (
        # image, failed candidates (not used by this function so we just assign string), test time, similarity, frame (also not used)
        [$dummy_img, 'img 1', 5, 500, $dummy_img],
        [$dummy_img, 'img 2', 6, 900, $dummy_img],
        [$dummy_img, 'img 3', 7, 800, $dummy_img],
        [$dummy_img, 'img 4', 8, 950, $dummy_img],
        [$dummy_img, 'img 5', 1, 700, $dummy_img],
        [$dummy_img, 'img 6', 2, 950, $dummy_img],
        [$dummy_img, 'img 7', 3, 850, $dummy_img],
    );
    my @expected = (
        [$dummy_img, 'img 4', 8, 950, $dummy_img],    # images sorted by test time and similarity (as 2nd criteria) in descending order
        [$dummy_img, 'img 3', 7, 1_000_000, $dummy_img],    # similarity of images (after the top one) recomputes (so we just get 1000000 for our dummies)
        [$dummy_img, 'img 2', 6, 1_000_000, $dummy_img],
        [$dummy_img, 'img 1', 5, 1_000_000, $dummy_img],    # first image preserved despite lowest similarity (so 2nd lowest is removed instead)
        [$dummy_img, 'img 7', 3, 1_000_000, $dummy_img],
        [$dummy_img, 'img 6', 2, 1_000_000, $dummy_img],
    );
    backend::baseclass::_reduce_to_biggest_changes(\@imglist, 5);    # pass limit of 5, we actually keep 6 images as the first one doesn't count
    is_deeply \@imglist, \@expected, 'images reduced as expected' or diag explain \@imglist;

    # note: This test has been added retrospectively assuming the implementation was correct at this point.
};

subtest 'stub functions' => sub {
    combined_like {
        $baseclass->freeze_vm;
        $baseclass->cont_vm;
    } qr/ignored freeze_vm.*ignored cont_vm/s, 'freeze/cont ignored by default';
};

subtest 'verifying image' => sub {
    my $fail_res = $baseclass->verify_image({imgpath => "$Bin/imgsearch/kde-logo.png", mustmatch => 0});
    is_deeply $fail_res, {candidates => []}, 'image not found (no candidates)' or diag explain $fail_res;

    my $fake_image = Test::MockObject->new->mock(search => sub ($self, $needles, $threshold, $search_ratio) { (1, [qw(foo bar)]) });
    my $tinycv_mock = Test::MockModule->new('tinycv')->redefine(read => $fake_image);
    my $ok_res = $baseclass->verify_image({imgpath => "$Bin/imgsearch/kde-logo.png", mustmatch => 0});
    is_deeply $ok_res, {found => 1, candidates => [qw(foo bar)]}, 'image found (mocked search)' or diag explain $ok_res;
};

subtest 'retrying assert screen' => sub {
    my $needles_reloaded = 0;
    my $mock = Test::MockModule->new('backend::baseclass')->redefine(reload_needles => sub ($self) { $needles_reloaded = 1 });
    $baseclass->assert_screen_deadline(0);
    combined_like {
        $baseclass->retry_assert_screen({reload_needles => 1, timeout => 42})
    } qr/cont_vm.*set_tags_to_assert: NO matching needles for foo/s, 'cont_vm called, set_tags_to_assert invoked';
    ok $needles_reloaded, 'needles have been reloaded';
    ok $baseclass->assert_screen_deadline, 'assert screen timeout set';
};

local $SIG{__DIE__} = 'DEFAULT';

subtest 'special cases when checking socket' => sub {
    my $rpc_mock = Test::MockModule->new('myjsonrpc');
    $rpc_mock->redefine(read_json => {invalid => 'response'});
    $baseclass->{cmdpipe} = 42;
    throws_ok { $baseclass->check_socket(42) } qr/no command in.*invalid.*response/s, 'dies on invalid response';

    $rpc_mock->redefine(read_json => {cmd => 'wait_screen_change', json_cmd_token => 'fake-postponed-token'});
    $baseclass->check_socket(42);
    is $baseclass->{_postponed_cmd_token}, 'fake-postponed-token', 'reply postponed, token saved for later';
};

subtest 'special cases of set_tags_to_assert' => sub {
    combined_like { needle::init("$Bin/data") } qr/loaded \d+ needles/, 'needles loaded';

    subtest 'invalid tags passed' => sub {
        my $warning = warning {
            combined_like {
                my $res = $baseclass->set_tags_to_assert({mustmatch => [{invalid => 'tags'}]});
                is_deeply $res, {tags => []}, 'empty set of tags returned for invalid needle' or diag explain $res;
            } qr/NO matching needles for/, 'no match logged for invalid needle'
        };
        like $warning, qr/invalid needle passed <HASH>.*invalid.*tags/s, 'warning about invalid needle';
        is_deeply $baseclass->assert_screen_needles, [], 'no assert screen needles assigned';
    };

    subtest 'multiple tags specified, multiple needles set for assertion' => sub {
        my @tags = (qw(inst-welcome not-existing));
        my $res = $baseclass->set_tags_to_assert({mustmatch => \@tags});
        is_deeply $res, {tags => \@tags}, 'tags returned' or diag explain $res;
        my @needles = sort { $a->{name} cmp $b->{name} } @{$baseclass->assert_screen_needles};
        is scalar @needles, 2, 'matching needles assigned';
        is $needles[0]->{name}, 'inst-welcome-20140902', 'needle inst-welcome-20140902 matched';
        is $needles[1]->{name}, 'welcome.ref', 'needle welcome.ref matched';
    };
};

subtest 'test _failed_screens_to_json when _reduce_to_biggest_changes removed final mismatch' => sub {
    my $mock = Test::MockModule->new('backend::baseclass')->redefine(_reduce_to_biggest_changes => sub ($failed_screens, $limit) {
            pop @$failed_screens;    # test case when the last one in the reduced list differs
    });
    my $dummy_img = Test::MockObject->new->set_always(similarity => 49)->set_always(ppm_data => 'img-data');
    my $dummy_frame = 'foo';
    $baseclass->assert_screen_fails([[$dummy_img, 'img 1', 5, 500, 'foo'], [$dummy_img, 'img 2', 5, 500, 'bar']]);
    my @expected_failures = (
        {candidates => 'img 1', frame => 'foo', image => "aW1nLWRhdGE=\n"},
        {candidates => 'img 2', frame => 'bar', image => "aW1nLWRhdGE=\n"},
    );
    my $res = $baseclass->_failed_screens_to_json;
    is_deeply $res, {timeout => 1, failed_screens => \@expected_failures}, 'expected res' or diag explain $res;
};

subtest 'check_asserted_screen takes too long' => sub {
    my $mock = Test::MockModule->new('backend::baseclass')->redefine(_reduce_to_biggest_changes => sub ($failed_screens, $limit) {
            splice @$failed_screens, $limit;
    });
    $baseclass->assert_screen_last_check(undef);
    $baseclass->assert_screen_fails([1 .. 60, [tinycv::new(1, 1), 'img 1', 5, 500, tinycv::new(1, 1)]]);
    combined_like { $baseclass->check_asserted_screen({}) } qr/check_asserted_screen took .* seconds for 2 candidate needles - make your needles more specific/, 'warning logged if check_asserted_screen takes too long';
    is ref $baseclass->assert_screen_last_check->[0], 'tinycv::Image', 'assert_screen_last_check assigned';
    is scalar @{$baseclass->assert_screen_fails}, 20, 'assert screen fails cleaned up';
};

subtest 'child process handling' => sub {
    throws_ok { $baseclass->_child_process(undef) } qr/without code/, 'starting dies without specifying coderef';
    local $SIG{TERM} = 'DEFAULT';
    # uncoverable statement count:2
    # uncoverable statement count:3
    my $pid = $baseclass->_child_process(sub { pause; _exit 0 });
    ok $pid, 'started child, pid returned: ' . ($pid // '?');
    combined_like { $baseclass->_stop_children_processes } qr/waitpid for $pid returned/, 'stopped child again';
};

done_testing;
