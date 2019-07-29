#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::MockObject;
use Test::Warnings;
use Net::SSH2;
use Scalar::Util 'refaddr';
use backend::baseclass;
use POSIX 'tzset';

BEGIN {
    unshift @INC, '..';
}

# make the test time-zone neutral
$ENV{TZ} = 'UTC';
tzset;

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
    my $ssh_expect_credentials = {username => 'root', password => 'password'};
    my $ssh_obj_data           = {};                                             # used to store Net::SSH2 fake data per object
    my $net_ssh2               = Test::MockModule->new('Net::SSH2');
    $net_ssh2->mock('connect', sub {
            my $self = shift;
            $ssh_obj_data->{refaddr($self)}->{connected} = 1;
            $ssh_obj_data->{refaddr($self)}->{blocking}  = 0;
            return 1;
    });
    $net_ssh2->mock('auth', sub {
            my ($self, %args) = @_;
            is($args{username}, $ssh_expect_credentials->{username}, 'Correct username for ssh connection');
            is($args{password}, $ssh_expect_credentials->{password}, 'Correct password for ssh connection');
            return 1;
    });
    $net_ssh2->mock('auth_ok', sub { return 1; });
    $net_ssh2->mock('blocking', sub {
            my ($self, $v);
            $ssh_obj_data->{refaddr($self)}->{blocking} = $v if defined($v);
            return $self->{blocking};
    });
    $net_ssh2->mock('disconnect', sub {
            $ssh_obj_data->{refaddr(shift)}->{connected} = 0;
            return 1;
    });
    $net_ssh2->mock('channel', sub {
            my $self = shift;
            die("Not connected") unless ($ssh_obj_data->{refaddr($self)}->{connected});
            my $mock_channel = Test::MockObject->new();
            $mock_channel->{ssh} = $self;
            $mock_channel->mock('exec', sub {
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
            $mock_channel->mock('read2', sub {
                    my ($self) = @_;
                    $self->{eof} = 1;
                    return ($self->{stdout}, $self->{stderr});
            });
            $mock_channel->mock('eof',         sub { return shift->{eof}; });
            $mock_channel->mock('blocking',    sub { return shift->{ssh}->blocking(shift) });
            $mock_channel->mock('pty',         sub { return 1; });
            $mock_channel->mock('send_eof',    sub { return 1; });
            $mock_channel->mock('exit_status', sub { shift->{exit_status}; });
    });

    my %ssh_creds = (username => 'root', password => 'password', hostname => 'foo.bla');
    my $ssh1      = $baseclass->new_ssh_connection(%ssh_creds);
    my $ssh2      = $baseclass->new_ssh_connection(%ssh_creds);
    my $ssh3      = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds);
    my $ssh4      = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds);
    $ssh_expect_credentials->{username} = 'foo911';
    my $ssh5 = $baseclass->new_ssh_connection(keep_open => 1, %ssh_creds, username => 'foo911');
    $ssh_expect_credentials->{username} = 'root';
    isnt(refaddr($ssh1), refaddr($ssh2), "Got new connection each call");
    is(refaddr($ssh3), refaddr($ssh4), "Got same connection with keep_open");
    isnt(refaddr($ssh4), refaddr($ssh5), "Got new connection with different credentials");

    # check run_ssh_cmd() usage
    is($baseclass->run_ssh_cmd('echo -n "foo"', %ssh_creds), 0, 'Command successful exit');
    isnt($baseclass->run_ssh_cmd('test 23 -eq 42', %ssh_creds), 0, 'Command failed exit');
    my @output = $baseclass->run_ssh_cmd('echo -n "foo"', wantarray => 1, %ssh_creds);
    is_deeply(\@output, [0, 'foo', ''], 'Command successful exit with output');

    $ssh_expect_credentials->{password} = '2+3=5';
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
};

done_testing;
