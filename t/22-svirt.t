#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::Warnings;
use Test::Output 'stderr_like';
use XML::SemanticDiff;
use backend::svirt;
use distribution;
use testapi qw(get_var get_required_var check_var set_var);

BEGIN {
    unshift @INC, '..';
}

set_var(WORKER_HOSTNAME => 'foo');
set_var(VIRSH_HOSTNAME  => 'bar');
set_var(VIRSH_PASSWORD  => 'password');

my $distri = $testapi::distri = distribution->new();
my $svirt  = backend::svirt->new();

is_deeply($svirt->read_credentials_from_virsh_variables, {
        hostname => 'bar',
        username => 'root',
        password => 'password',
}, 'read credentials');

$svirt->do_start_vm;
$distri->add_console('sut-serial', 'ssh-virtsh-serial', {});

my $consoles          = $distri->{consoles};
my $svirt_console     = $consoles->{svirt};
my $svirt_sut_console = $consoles->{'sut-serial'};

subtest 'svirt console correctly initialized' => sub {
    ok($svirt_console);
    is($svirt_console->{class},           'consoles::sshVirtsh');
    is($svirt_console->{backend},         $svirt);
    is($svirt_console->{name},            'openQA-SUT-1');
    is($svirt_console->{testapi_console}, 'svirt');
    is($svirt_console->{instance},        1);
    is($svirt_console->{vmm_family},      'kvm');
    is($svirt_console->{vmm_type},        'hvm');
};

is_deeply($svirt_sut_console, {
        activated       => 0,
        args            => {},
        class           => 'consoles::sshVirtshSUT',
        libvirt_domain  => 'openQA-SUT-1',
        serial_port_no  => 1,
        testapi_console => 'sut-serial',
}, 'SUT serial console correctly initialized') or diag explain $consoles;

subtest 'XML config for VNC and serial console' => sub {
    $svirt_console->_init_xml();
    $svirt_console->add_vnc({port => 5901});
    $svirt_console->add_pty({target_port => 0});
    $svirt_console->add_serial_console();

    my $produced_xml = $svirt_console->{domainxml}->toString(2);
    my $expected_xml = '22-svirth-virsh-config.xml';
    $expected_xml = 't/' . $expected_xml unless (-f $expected_xml);

    my $diff = XML::SemanticDiff->new(keeplinenums => 1);
    if (my @changes = $diff->compare($produced_xml, $expected_xml)) {
        fail('XML not as expected');
        note('differences:');
        diag explain \@changes;
        note('produced XML:');
        note($produced_xml);
    }
    else {
        ok('XML looks as expected');
    }
};

done_testing;
