#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use backend::spvm;
use testapi qw(set_var power);

subtest 'SSH credentials in spvm' => sub {
    my $expected_credentials = {username => 'root', password => 'foo', hostname => 'my_foo_hostname'};
    my $mock_spvm            = Test::MockModule->new('backend::spvm');
    $mock_spvm->mock(run_ssh_cmd => sub {
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

subtest 'PowerVM power actions' => sub {
    my $mock_spvm = Test::MockModule->new('backend::spvm');
    $mock_spvm->redefine('run_cmd', sub {
            my ($self, $cmd) = @_;
            return $cmd;
    });
    my $spvm    = backend::spvm->new();
    my $lpar_id = 3;
    set_var(NOVALINK_LPAR_ID => $lpar_id);
    is($spvm->power({action => 'on'}), "pvmctl lpar power-on -i id=${lpar_id} --bootmode norm", "Test power on");
    throws_ok { $spvm->power({action => 'reboot'}) } qr/Unknown power action reboot/, 'Unknown power action';
};
done_testing;
