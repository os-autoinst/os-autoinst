#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Output;
use Test::Warnings ':report_warnings';
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';
use Mojo::File 'path';
use Mojo::JSON 'decode_json';
use backend::baseclass;
use POSIX 'tzset';
use Mojo::File 'tempdir';
use Mojo::Util qw(scope_guard);
use bmwqemu ();

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

# make the test time-zone neutral
$ENV{TZ} = 'UTC';
tzset;

bmwqemu::init_logger;

my $baseclass = backend::baseclass->new();

subtest 'format_vtt_timestamp' => sub {
    my $timestamp = 1543917024;

    $baseclass->{video_frame_number} = 0;
    is($baseclass->format_vtt_timestamp($timestamp),
        "\n0\n00:00:00.000 --> 00:00:00.041\n[2018-12-04T09:50:24.000]\n",
        'frame number 0'
    );

    $baseclass->{video_frame_number} = 1;
    is($baseclass->format_vtt_timestamp($timestamp),
        "\n1\n00:00:00.041 --> 00:00:00.083\n[2018-12-04T09:50:24.000]\n",
        'frame number 1'
    );
};

subtest 'SSH utilities' => sub {
    my $ssh_expect           = {username => 'root', password => 'password', hostname => 'foo.bar', port => undef};
    my $fail_on_channel_call = undef;
    my $ssh_auth_ok          = 1;
    my $ssh_obj_data         = {};                                                                                # used to store Net::SSH2 fake data per object
    my @net_ssh2_error       = ();
    my $net_ssh2             = Test::MockModule->new('Net::SSH2');
    $net_ssh2->redefine(new => sub {
            my ($class, %opts) = @_;
            my $self = Test::MockObject->new();
            my $id   = $self->{my_custom_id} = bmwqemu::random_string(32);
            die 'Identifier not unique' if exists $ssh_obj_data->{$id};
            $ssh_obj_data->{$id} = $self;

            $self->mock(connect => sub {
                    my ($self, $hostname, $port) = @_;
                    is($hostname, $ssh_expect->{hostname}, 'Connect to correct hostname');
                    # if unspecified, default to port 22
                    is($port, $ssh_expect->{port} // 22, 'Connect to correct port');
                    $self->{hostname} = $hostname;
                    $self->{port}     = $port;
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
                        $self->{sock}     = $mock_sock;
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
                                $self->{stdout}      = `$cmd`;
                                $self->{exit_status} = $?;
                                $self->{stderr}      = '';
                            }
                            return 1;
                    });
                    $mock_channel->mock(read2 => sub {
                            my ($self) = @_;
                            $self->{eof} = 1;
                            return ($self->{stdout}, $self->{stderr});
                    });
                    $mock_channel->mock(eof         => sub { return shift->{eof}; });
                    $mock_channel->mock(blocking    => sub { return shift->{ssh}->blocking(shift) });
                    $mock_channel->mock(pty         => sub { return 1; });
                    $mock_channel->mock(send_eof    => sub { return 1; });
                    $mock_channel->mock(exit_status => sub { shift->{exit_status}; });
                    $mock_channel->mock(ext_data    => sub { my ($self, $v) = @_; $self->{ext_data} = $v; });
                    $mock_channel->mock(close       => sub { return 1; });
                    return $mock_channel;
            });

            return $self;
    });
    sub refaddr { return shift->{my_custom_id}; }

    my ($ssh1, $ssh2, $ssh3, $ssh4, $ssh5, $ssh6, $ssh7, $ssh8);
    my %ssh_creds        = (username => 'root', password => 'password', hostname => 'foo.bar');
    my $exp_log_new      = qr/SSH connection to root\@foo\.bar established/;
    my $exp_log_existing = qr/Use existing SSH connection/;
    my $exp_log_renew    = qr/Close broken SSH connection[\s\S]+SSH connection to root\@foo\.bar established/;
    my $default_logger   = $bmwqemu::logger;
    $bmwqemu::logger = Mojo::Log->new(level => 'debug');

    # 1st SSH instance
    stderr_like { $ssh1 = $baseclass->new_ssh_connection(%ssh_creds) } $exp_log_new, 'New SSH connection announced in logs 1';
    # 2nd SSH instance
    stderr_like { $ssh2 = $baseclass->new_ssh_connection(%ssh_creds) } $exp_log_new, 'New SSH connection announced in logs 2';
    # 3rd SSH instance
    stderr_like { $ssh3 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds) } $exp_log_new, 'New SSH connection announced in logs (first keep_open=>1)';
    stderr_unlike { $ssh4 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds) } $exp_log_new,    'No new SSH connection announced in logs';
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

    $bmwqemu::logger = $default_logger;

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

    my @connected_ssh    = grep { $_->{connected} } values(%$ssh_obj_data);
    my @disconnected_ssh = grep { !$_->{connected} } values(%$ssh_obj_data);

    is(scalar(@connected_ssh), 5, "Expect 5 connected SSH connections");
    is($ssh1->{connected},     1, "SSH connection ssh1 connected");
    is($ssh2->{connected},     1, "SSH connection ssh2 connected");
    is($ssh7->{connected},     1, "SSH connection ssh7 connected");
    is($ssh8->{connected},     1, "SSH connection ssh8 connected");
    # +1 unamed connection form implicit run_ssh_cmd()

    is(scalar(@disconnected_ssh), 3, "Expect 3 disconnected SSH connections");
    is($ssh3->{connected},        0, "SSH connection ssh3 disconnected");
    # +1 from auth failure
    # +1 run_ssh_cmd(keep_open => 0)

    $baseclass->close_ssh_connections();
    @connected_ssh = grep { $_->{connected} } values(%$ssh_obj_data);
    is(scalar(@connected_ssh), 2, "Expect 2 connected SSH connections (ssh1 and ssh2");
    is($ssh1->{connected},     1, "SSH connection ssh1 connected");
    is($ssh2->{connected},     1, "SSH connection ssh2 connected");

    subtest 'Serial SSH' => sub {
        my $io_select_mock = Test::MockModule->new('IO::Select');
        $io_select_mock->redefine('add');
        $io_select_mock->redefine('remove');
        $baseclass->{select_read} = IO::Select->new;

        $ssh_expect      = {username => 'serial', password => 'XXX', hostname => 'serial.host'};
        $num_ssh_connect = scalar(keys(%{$ssh_obj_data}));
        my ($ssh, $chan) = $baseclass->start_ssh_serial(username => 'serial', password => 'XXX', hostname => 'serial.host');
        is($num_ssh_connect + 1, scalar(keys(%{$ssh_obj_data})), 'Ensure start_ssh_serial() uses a new SSH connection');
        is($chan->{ext_data},    'merge',                        'STDOUT and STDERR are merged');
        is($ssh->blocking(),     0,                              'We run SSH in none blocking mode');

        $baseclass->truncate_serial_file();
        my $expect_output       = "FOO$/" x 4096;
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
        is(path($baseclass->{serialfile})->slurp(), $expect_output, 'Serial output is writen to serial file');
        is($exit_value,                             1,              'Check return value on success');

        $channel_read_string = undef;
        @net_ssh2_error      = (LIBSSH2_ERROR_EAGAIN, 'EAGAIN', 'Try later');
        stdout_is { $exit_value = $baseclass->check_ssh_serial($ssh->sock()) } '', 'No output on EAGAIN only';
        is($exit_value,          1,    'Check return value on EAGAIN');
        is($baseclass->{serial}, $ssh, 'Serial SSH exists after EGAIN');

        is($baseclass->check_ssh_serial(42), 0, 'Return 0 when called with wrong socket');

        @net_ssh2_error = (666, 'UNKNOWN', 'OHA');
        stdout_is { $exit_value = $baseclass->check_ssh_serial($ssh->sock()) } '', 'No output on ERROR only';
        is($exit_value,          1,     'Check return value on EAGAIN');
        is($baseclass->{serial}, undef, 'SSH serial get disconnected on unknown read ERROR');

        is($baseclass->check_ssh_serial(23), 0, 'Return 0 if SSH serial isn\'t connected');
    };
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

done_testing;
