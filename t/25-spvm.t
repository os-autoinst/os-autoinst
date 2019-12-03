#!/usr/bin/perl

use 5.018;
use strict;
use warnings;

use Test::More;
use Test::MockModule;
use backend::spvm;
use testapi 'set_var';

subtest 'SSH credentials in spvm' => sub {
    my $expected_credentials = {username => 'root', password => 'foo', hostname => 'my_foo_hostname'};
    my $mock_spvm            = Test::MockModule->new('backend::spvm');
    $mock_spvm->mock('run_ssh_cmd', sub {
            my ($self, $cmd, %args) = @_;
            for my $k (keys(%{$expected_credentials})) {
                is($args{$k}, $expected_credentials->{$k}, "Correct $k parameter");
            }
            return $cmd =~ m/true/ ? 0 : 1;
    });

    set_var(WORKER_HOSTNAME => 'foo');
    my $spvm = backend::spvm->new();

    set_var('NOVALINK_HOSTNAME', 'my_foo_hostname');
    set_var('NOVALINK_PASSWORD', 'foo');
    is($spvm->run_cmd('true'), 0, "Test default credentials - without user");

    set_var('NOVALINK_USERNAME', 'tony');
    $expected_credentials->{username} = 'tony';
    is($spvm->run_cmd('true'),  0, "Test default credentials - with user");
    is($spvm->run_cmd('false'), 1, "Test different return code");

    $expected_credentials = {hostname => 'specific_hostname', username => 'tony', password => 'specific_password'};
    is($spvm->run_cmd('true', $expected_credentials->{hostname}, $expected_credentials->{password}), 0, "Test specific credentials");
};

done_testing;
