#!/usr/bin/perl

use Test::Most;
use Mojo::Base -signatures;

use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use Test::MockObject;
use Mojo::File qw(tempdir path);
use Mojo::Util qw(scope_guard);

use FindBin qw($Bin $Script);
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

use backend::qemu;

sub backend () {
    my $backend = backend::qemu->new();
    ($backend->{"select_$_"} = Test::MockObject->new)->set_true('add') for qw(read write);
    return $backend;
}

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $proc_mock = Test::MockModule->new('OpenQA::Qemu::Proc');
$proc_mock->redefine(exec_qemu => undef);
$proc_mock->redefine(connect_qmp => undef);
$proc_mock->redefine(init_blockdev_images => undef);

my $jsonrpc = Test::MockModule->new('myjsonrpc');
$jsonrpc->redefine(read_json => undef);

my $backend_mock = Test::MockModule->new('backend::qemu', no_auto => 1);
$backend_mock->redefine(handle_qmp_command => undef);
$backend_mock->redefine(determine_qemu_version => sub ($self, @) { $self->{qemu_version} = '9.0' });

my $distri = Test::MockModule->new('distribution');
$distri->redefine(add_console => sub {
        my $ret = Test::MockObject->new();
        $ret->set_true('backend');
        return $ret;
});
$backend_mock->mock(select_console => undef);
$testapi::distri = distribution->new;

my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
$mock_bmwqemu->noop('log_call', 'fctwarn', 'diag', 'save_vars');

subtest 'default hardware profile' => sub {
    my $backend = backend();
    %bmwqemu::vars = (ARCH => 'x86_64', VNC => 1, CASEDIR => $dir);
    my @params;
    $proc_mock->redefine(static_param => sub ($self, @args) { push @params, \@args });

    $backend->start_qemu();

    ok(grep { ref $_ eq 'ARRAY' && $_->[0] eq 'serial' && defined $_->[1] && $_->[1] eq 'chardev:serial0' } @params, 'default profile applied (serial)');
    ok($backend->_profile_has('serial'), 'profile has serial capability');
};

subtest 'virt-manager-defaults profile' => sub {
    my $backend = backend();
    %bmwqemu::vars = (ARCH => 'x86_64', VNC => 1, QEMU_HWPROFILE => 'virt-manager-defaults', CASEDIR => $dir);
    my @params;
    $proc_mock->redefine(static_param => sub ($self, @args) { push @params, \@args });

    $backend->start_qemu();

    ok(grep { ref $_ eq 'ARRAY' && $_->[1] && $_->[1] =~ /pcie-root-port/ } @params, 'virt-manager-defaults applied (pcie-root-port)');
    ok($backend->_profile_has('graphics'), 'profile has graphics capability');

    ok(!grep { ref $_ eq 'ARRAY' && $_->[0] eq 'device' && $_->[1] eq 'VGA,edid=on,xres=1024,yres=768' } @params, 'standard graphics backend skipped');
};

subtest 'custom profile from file' => sub {
    my $backend = backend();
    my $profile_path = "$dir/custom_profile.txt";
    path($profile_path)->spew("-machine q35\n-device my-custom-device\n# comment\n");

    %bmwqemu::vars = (ARCH => 'x86_64', VNC => 1, QEMU_HWPROFILE => $profile_path, CASEDIR => $dir);
    my @params;
    $proc_mock->redefine(static_param => sub ($self, @args) { push @params, \@args });

    $backend->start_qemu();

    ok(grep { ref $_ eq 'ARRAY' && $_->[0] eq 'machine' && $_->[1] eq 'q35' } @params, 'custom machine from file');
    ok(grep { ref $_ eq 'ARRAY' && $_->[0] eq 'device' && $_->[1] eq 'my-custom-device' } @params, 'custom device from file');
    ok(!$backend->_profile_has('serial'), 'custom profile has no serial capability');
};

subtest 'conditional variation (override)' => sub {
    my $backend = backend();
    %bmwqemu::vars = (ARCH => 'x86_64', VNC => 1, QEMU_HWPROFILE => 'virt-manager-defaults', QEMUMACHINE => 'pc-q35-4.2', CASEDIR => $dir);
    my @params;
    $proc_mock->redefine(static_param => sub ($self, @args) { push @params, \@args });

    $backend->start_qemu();

    my @machines = grep { ref $_ eq 'ARRAY' && $_->[0] eq 'machine' } @params;
    is($machines[-1]->[1], 'pc-q35-4.2', 'QEMUMACHINE override works (last one wins)');
};

done_testing();
