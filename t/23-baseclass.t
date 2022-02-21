#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Mock::Time;
use Test::MockModule;
use Test::MockObject;
use Test::Output;
use Test::Warnings ':report_warnings';
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';
use Mojo::File 'path';
use Mojo::JSON 'decode_json';
use backend::baseclass;
use POSIX 'tzset';
use Mojo::File qw(tempdir path);
use Mojo::Util qw(scope_guard);
use IO::Pipe;
use bmwqemu ();

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

# make the test time-zone neutral
$ENV{TZ} = 'UTC';
tzset;

bmwqemu::init_logger;

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
        [save_memory_dump => 23],
        [save_storage_drives => 23],
    );
    for my $test (@tests) {
        my ($m, @args) = @$test;
        eval { $dummy->$m(@args) };
        my $err = $@;
        like $err, qr{backend method '$m' not implemented for class 'dummy'}, "notimplemented() works for '\$self->$m(@args)'";
    }
};

subtest 'SSH utilities' => sub {
    my $ssh_expect = {username => 'root', password => 'password', hostname => 'foo.bar', port => undef};
    my $fail_on_channel_call = undef;
    my $ssh_auth_ok = 1;
    my $ssh_obj_data = {};    # used to store Net::SSH2 fake data per object
    my @net_ssh2_error = ();
    my $net_ssh2 = Test::MockModule->new('Net::SSH2');
    $net_ssh2->redefine(new => sub {
            my ($class, %opts) = @_;
            my $self = Test::MockObject->new();
            my $id = $self->{my_custom_id} = bmwqemu::random_string(32);
            die 'Identifier not unique' if exists $ssh_obj_data->{$id};
            $ssh_obj_data->{$id} = $self;

            $self->mock(connect => sub {
                    my ($self, $hostname, $port) = @_;
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
            $self->mock(auth_agent => sub { return 1; });
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
                                $self->{stdout} = `$cmd`;
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
    sub refaddr { return shift->{my_custom_id}; }

    my ($ssh1, $ssh2, $ssh3, $ssh4, $ssh5, $ssh6, $ssh7, $ssh8);
    my %ssh_creds = (username => 'root', password => 'password', hostname => 'foo.bar');
    my $exp_log_new = qr/SSH connection to root\@foo\.bar established/;
    my $exp_log_existing = qr/Use existing SSH connection/;
    my $exp_log_renew = qr/Close broken SSH connection[\s\S]+SSH connection to root\@foo\.bar established/;
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

    is(scalar(@connected_ssh), 5, "Expect 5 connected SSH connections");
    is($ssh1->{connected}, 1, "SSH connection ssh1 connected");
    is($ssh2->{connected}, 1, "SSH connection ssh2 connected");
    is($ssh7->{connected}, 1, "SSH connection ssh7 connected");
    is($ssh8->{connected}, 1, "SSH connection ssh8 connected");
    # +1 unnamed connection form implicit run_ssh_cmd()

    is(scalar(@disconnected_ssh), 3, "Expect 3 disconnected SSH connections");
    is($ssh3->{connected}, 0, "SSH connection ssh3 disconnected");
    # +1 from auth failure
    # +1 run_ssh_cmd(keep_open => 0)

    $baseclass->close_ssh_connections();
    @connected_ssh = grep { $_->{connected} } values(%$ssh_obj_data);
    is(scalar(@connected_ssh), 2, "Expect 2 connected SSH connections (ssh1 and ssh2");
    is($ssh1->{connected}, 1, "SSH connection ssh1 connected");
    is($ssh2->{connected}, 1, "SSH connection ssh2 connected");

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

        @net_ssh2_error = (666, 'UNKNOWN', 'OHA');
        stdout_is { $exit_value = $baseclass->check_ssh_serial($ssh->sock()) } '', 'No output on ERROR only';
        is($exit_value, 1, 'Check return value on EAGAIN');
        is($baseclass->{serial}, undef, 'SSH serial get disconnected on unknown read ERROR');

        is($baseclass->check_ssh_serial(23), 0, 'Return 0 if SSH serial isn\'t connected');
    };
};

sub _prepare_video_encoder ($baseclass) {
    my @pipes;
    for (1 .. 3) {
        my $pipe = IO::Pipe->new;
        my $pid = fork;
        if ($pid) { $pipe->writer }
        elsif (defined $pid) {    # uncoverable statement
            $pipe->reader;    # uncoverable statement
            my @lines = <$pipe>;    # uncoverable statement
            exit;    # uncoverable statement
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
    path($baseclass->{serialfile})->spurt(<<EOT);
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

done_testing;
