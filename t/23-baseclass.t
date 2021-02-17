#!/usr/bin/perl

use Test::Most;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Output 'stdout_is';
use Test::Warnings ':report_warnings';
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';
use Mojo::File 'path';
use Mojo::JSON 'decode_json';
use Scalar::Util 'refaddr';
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
    my $ssh_expect     = {username => 'root', password => 'password', hostname => 'foo.bla'};
    my $ssh_obj_data   = {};                                                                    # used to store Net::SSH2 fake data per object
    my @net_ssh2_error = ();
    my $net_ssh2       = Test::MockModule->new('Net::SSH2');
    $net_ssh2->redefine(connect => sub {
            my ($self, $hostname) = @_;
            is($hostname, $ssh_expect->{hostname}, 'Connect to correct hostname');
            $ssh_obj_data->{refaddr($self)}->{hostname}  = $hostname;
            $ssh_obj_data->{refaddr($self)}->{connected} = 1;
            $ssh_obj_data->{refaddr($self)}->{blocking}  = 0;
            return 1;
    });
    $net_ssh2->redefine(hostname => sub { return $ssh_obj_data->{refaddr(shift)}->{hostname} });
    $net_ssh2->redefine(auth => sub {
            my ($self, %args) = @_;
            is($args{username}, $ssh_expect->{username}, 'Correct username for ssh connection');
            is($args{password}, $ssh_expect->{password}, 'Correct password for ssh connection');
            return 1;
    });
    $net_ssh2->redefine(auth_ok => sub { return 1; });
    $net_ssh2->redefine(blocking => sub {
            my ($self, $v) = @_;
            $ssh_obj_data->{refaddr($self)}->{blocking} = $v if defined($v);
            return $ssh_obj_data->{refaddr($self)}->{blocking};
    });
    $net_ssh2->redefine(disconnect => sub {
            $ssh_obj_data->{refaddr(shift)}->{connected} = 0;
            return 1;
    });
    $net_ssh2->redefine(error => sub { return @net_ssh2_error; });
    $net_ssh2->redefine(sock => sub {
            my $self = shift;
            unless ($ssh_obj_data->{refaddr($self)}->{sock}) {
                my $mock_sock = Test::MockObject->new();
                $mock_sock->{ssh} = $self;
                $ssh_obj_data->{refaddr($self)}->{sock} = $mock_sock;
            }
            return $ssh_obj_data->{refaddr($self)}->{sock};
    });
    $net_ssh2->redefine(channel => sub {
            my $self = shift;
            die("Not connected") unless ($ssh_obj_data->{refaddr($self)}->{connected});
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
            return $mock_channel;
    });

    my %ssh_creds = (username => 'root', password => 'password', hostname => 'foo.bla');
    my $ssh1      = $baseclass->new_ssh_connection(%ssh_creds);
    my $ssh2      = $baseclass->new_ssh_connection(%ssh_creds);
    my $ssh3      = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds);
    my $ssh4      = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds);
    $ssh_expect->{username} = 'foo911';
    my $ssh5 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds, username => 'foo911');
    $ssh_expect->{username} = 'root';
    isnt(refaddr($ssh1), refaddr($ssh2), "Got new connection each call");
    is(refaddr($ssh3), refaddr($ssh4), "Got same connection with keep_open");
    isnt(refaddr($ssh4), refaddr($ssh5), "Got new connection with different credentials");

    # check run_ssh_cmd() usage
    is($baseclass->run_ssh_cmd('echo -n "foo"', %ssh_creds), 0, 'Command successful exit');
    isnt($baseclass->run_ssh_cmd('test 23 -eq 42', %ssh_creds), 0, 'Command failed exit');
    my @output = $baseclass->run_ssh_cmd('echo -n "foo"', wantarray => 1, %ssh_creds);
    is_deeply(\@output, [0, 'foo', ''], 'Command successful exit with output');

    $ssh_expect->{password} = '2+3=5';
    is($baseclass->run_ssh_cmd('echo -n "foo"', %ssh_creds, password => '2+3=5'), 0, 'Allow SSH credentials per run_ssh_cmd() call');

    my $num_ssh_connect = scalar(keys(%{$ssh_obj_data}));
    $baseclass->run_ssh_cmd('echo -n "foo"', %ssh_creds, password => '2+3=5', keep_open => 0);
    is($num_ssh_connect + 1, scalar(keys(%{$ssh_obj_data})), 'Ensure run_ssh_cmd(keep_open => 0) uses a new SSH connection');

    # cleanup kept ssh connections
    for my $ssh_ref ((refaddr($ssh3), refaddr($ssh4), refaddr($ssh5))) {
        is($ssh_obj_data->{$ssh_ref}->{connected}, 1, "SSH connection $ssh_ref connected");
    }
    $baseclass->close_ssh_connections();
    is(scalar(keys(%{$baseclass->{ssh_connections}})), 0, "Cleanup ssh connections");
    for my $ssh_ref ((refaddr($ssh3), refaddr($ssh4), refaddr($ssh5))) {
        is($ssh_obj_data->{$ssh_ref}->{connected}, 0, "SSH connection $ssh_ref is disconnected");
    }

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
