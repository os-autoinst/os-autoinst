#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Warnings ':report_warnings';
use Test::Output;
use Test::Mock::Time;
use Mojo::Log;
use XML::SemanticDiff;
use backend::svirt;
use consoles::sshVirtsh;
use distribution;
use Net::SSH2;
use testapi qw(get_var get_required_var check_var set_var);
use backend::svirt qw(SERIAL_CONSOLE_DEFAULT_PORT SERIAL_TERMINAL_DEFAULT_DEVICE SERIAL_TERMINAL_DEFAULT_PORT SERIAL_USER_TERMINAL_DEFAULT_DEVICE SERIAL_USER_TERMINAL_DEFAULT_PORT);
use Mojo::File qw(tempdir path);
use Mojo::Util qw(scope_guard);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

bmwqemu::init_logger;

set_var(WORKER_HOSTNAME => 'foo');
set_var(VIRSH_HOSTNAME => 'bar');
set_var(VIRSH_PASSWORD => 'password');
set_var(SVIRT_WORKER_CACHE => 1);

my $ssh_xterm_vt_mock = Test::MockModule->new('consoles::sshXtermVt');
$ssh_xterm_vt_mock->noop('activate');

my $distri = $testapi::distri = distribution->new;
my $svirt = backend::svirt->new;
is_deeply({$svirt->get_ssh_credentials}, {
        hostname => 'bar',
        username => 'root',
        password => 'password',
}, 'reading SSH credentials via svirt backend, username defaults to "root"');

my $ssh_virtsh = consoles::sshVirtsh->new(undef, {hostname => 'some-host', password => 'foo'});
$ssh_virtsh->activate;
is_deeply({$ssh_virtsh->get_ssh_credentials}, {
        hostname => 'some-host',
        username => 'root',
        password => 'foo',
}, 'reading SSH credentials via sshVirtsh console, username defaults to "root"');

$svirt->do_start_vm;
$distri->add_console('root-sut-serial', 'ssh-virtsh-serial', {});
$distri->add_console('user-sut-serial', 'ssh-virtsh-serial', {});

my $consoles = $distri->{consoles};
my $svirt_console = $consoles->{svirt};
my $svirt_sut_console = $consoles->{'root-sut-serial'};

subtest 'svirt console correctly initialized' => sub {
    ok($svirt_console);
    is($svirt_console->{class}, 'consoles::sshVirtsh');
    is($svirt_console->{backend}, $svirt);
    is($svirt_console->{name}, 'openQA-SUT-1');
    is($svirt_console->{testapi_console}, 'svirt');
    is($svirt_console->{instance}, 1);
    is($svirt_console->{vmm_family}, 'kvm');
    is($svirt_console->{vmm_type}, 'hvm');
};

is_deeply($svirt_sut_console, {
        activated => 0,
        args => {},
        class => 'consoles::sshVirtshSUT',
        console_hotkey => 'ctrl-alt-f',
        libvirt_domain => 'openQA-SUT-1',
        serial_port_no => 1,
        testapi_console => 'root-sut-serial',
        pty_dev => SERIAL_TERMINAL_DEFAULT_DEVICE,
}, 'SUT serial console correctly initialized') or always_explain $consoles;

sub _is_xml ($actual_xml_data, $expected_xml_file_path) {
    my $diff = XML::SemanticDiff->new(keeplinenums => 1);
    if (my @changes = $diff->compare($actual_xml_data, $expected_xml_file_path)) {
        fail 'XML not as expected';    # uncoverable statement
        always_explain 'differences:', \@changes;    # uncoverable statement
        note 'produced XML:';    # uncoverable statement
        note $actual_xml_data;    # uncoverable statement
        return 0;    # uncoverable statement
    }
    ok 'XML looks as expected';
}

subtest 'XML config for VNC and serial console' => sub {
    $svirt_console->_init_xml();
    $testapi::password = 'secret';
    $svirt_console->add_vnc({port => 5901});
    $svirt_console->add_pty({target_port => SERIAL_CONSOLE_DEFAULT_PORT});
    $svirt_console->add_pty({pty_dev => SERIAL_TERMINAL_DEFAULT_DEVICE, pty_dev_type => 'pty', target_port => SERIAL_TERMINAL_DEFAULT_PORT});
    $svirt_console->add_pty({pty_dev => SERIAL_USER_TERMINAL_DEFAULT_DEVICE, pty_dev_type => 'pty', target_port => SERIAL_USER_TERMINAL_DEFAULT_PORT});
    _is_xml $svirt_console->{domainxml}->toString(2), "$Bin/22-svirt-virsh-config.xml";
};

subtest 's390x specifics' => sub {
    $bmwqemu::vars{ARCH} = 's390x';
    $svirt_console->_init_xml;
    unlike $svirt_console->{domainxml}->toString, qr/acpi/i, 'ACPI support is not configured for s390x';
};

subtest 'add_input modifies XML config ' => sub {
    $svirt_console->add_input({type => 'tablet', bus => 'usb'});
    like $svirt_console->{domainxml}->toString, qr/tablet.*usb/i, 'XML contains correct type and bus';
};

subtest 'add network config on XML config' => sub {
    my %ifcfg = ();
    $ifcfg{source} = {bridge => 'br0'};
    $ifcfg{mac} = {address => '00:16:3e:11:22:33'};
    $svirt_console->add_interface(\%ifcfg);
    like $svirt_console->{domainxml}->toString, qr/br0/i, 'source was added correctly on XML';
    like $svirt_console->{domainxml}->toString, qr/00:16:3e:11:22:33/i, 'mac was added correctly on XML';
    subtest 'add the serial console used for the serial log' => sub {
        $bmwqemu::vars{VMWARE_SERIAL_PORT} = '10002';
        $svirt_console->add_pty({pty_dev => SERIAL_TERMINAL_DEFAULT_DEVICE,
                pty_dev_type => 'pty',
                target_type => 'bar',
                protocol_type => 'raw',
                source => 1});
        like $svirt_console->{domainxml}->toString, qr/service="10002"/i, 'serial port added correctly on XML';
        like $svirt_console->{domainxml}->toString, qr/<target type="bar" port=""\/>/i, 'target type added correctly on XML';
        like $svirt_console->{domainxml}->toString, qr/<protocol type="raw"\/>/i, 'protocol type added correctly on XML';
    };
};

subtest 'allow to add, remove elements and set attributes in the domain XML' => sub {
    $svirt_console->change_domain_element(funny => guy => 'hello');
    like $svirt_console->{domainxml}->toString, qr/<funny><guy>hello<\/guy><\/funny>/i, 'added node successfully in the domain XML';
    $svirt_console->change_domain_element(funny => guy => undef);
    unlike $svirt_console->{domainxml}->toString, qr/<funny><guy>hello<\/guy><\/funny>/i, 'remove node successfully in the domain XML';
    $svirt_console->change_domain_element(funny => guy => {hello => 'world'});
    like $svirt_console->{domainxml}->toString, qr/<funny><guy hello="world"\/><\/funny>/i, 'set attributes successfully in the domain XML';
};

subtest 'check virsh() method' => sub {
    $bmwqemu::vars{VMWARE_REMOTE_VMM} = 'my_vmm';
    my $virsh = consoles::sshVirtsh::virsh();
    is $virsh, 'virsh my_vmm', 'correct output from virsh()';
};

subtest 'check suspend() method' => sub {
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my @cmds;
    $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $svirt_console->suspend();
    is_deeply \@cmds, ['virsh my_vmm suspend openQA-SUT-1'], 'correct command from suspend()';
};

subtest 'check resume() method' => sub {
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my @cmds;
    $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $svirt_console->resume();
    is_deeply \@cmds, ['virsh my_vmm resume openQA-SUT-1'], 'correct command from suspend()';
};

subtest 'check get_remote_vmm() method' => sub {
    $bmwqemu::vars{VMWARE_REMOTE_VMM} = 'my_vmm';
    my $virsh = consoles::sshVirtsh->get_remote_vmm();
    is $virsh, 'my_vmm', 'correct output from virsh';
};

# assume VMware for further testing
$svirt_console->vmm_family($bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware');

subtest 'XML config with UEFI loader and VMware' => sub {
    $bmwqemu::vars{UEFI} = 1;
    $bmwqemu::vars{ARCH} = 'x86_64';

    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    $console_mock->redefine(run_cmd => 1);
    lives_ok { $svirt_console->_init_xml } 'UEFI firmware can be found on hypervisor';

    $console_mock->redefine(run_cmd => 0);
    $svirt_console->_init_xml;
    _is_xml $svirt_console->{domainxml}->toString(2), "$Bin/22-svirt-virsh-config-uefi.xml";
};

subtest 'starting VMware console' => sub {
    $bmwqemu::vars{VMWARE_HOST} = 'h';
    $bmwqemu::vars{VMWARE_USERNAME} = 'u';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'p';

    my $chan_mock = Test::MockObject->new->set_true(qw(write send_eof close read2 eof exit_status));
    my $backend_mock = Test::MockModule->new('backend::svirt');
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my $tmp_mock = Test::MockModule->new('File::Temp');
    my (@cmds, @ssh_cmds);
    $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $console_mock->redefine(get_cmd_output => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $backend_mock->redefine(run_ssh => sub ($self, $cmd, %args) { push @ssh_cmds, $cmd; (undef, $chan_mock) });
    $backend_mock->redefine(start_serial_grab => 1);
    $console_mock->redefine(get_ssh_credentials => sub { (hostname => 'foo', username => 'root', password => '123') });
    $tmp_mock->redefine(tempfile => sub { (undef, '/t') });

    $svirt_console->define_and_start;
    like shift @cmds, qr/cat > \/t <<.*username=u.*password=p.*auth-esx-h/s, 'config written';
    my $s = 'virsh -c esx://u@h/?no_verify=1\\&authfile=/t ';
    is_deeply \@cmds, [
        $s . ' destroy openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' undefine --snapshots-metadata openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' define /var/lib/libvirt/images/openQA-SUT-1.xml',
        'echo \'bios.bootDelay = "10000"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'test -e /vmfs/volumes/datastore1/openQA/openQA-SUT-1.nvram',
        'echo \'nvram = "openQA-SUT-1.nvram"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        $s . ' start openQA-SUT-1 2> >(tee /tmp/os-autoinst-openQA-SUT-1-stderr.log >&2)',
        $s . ' dumpxml openQA-SUT-1'
    ], 'expected commands invoked' or always_explain \@cmds;
};

subtest 'test config encoding' => sub {
    $bmwqemu::vars{GUESTINFO_COMBUSTION} = 'someTestScript';
    my $test_script_dir = path(File::Temp->newdir('testXXXX'));
    $bmwqemu::vars{CASEDIR} = $test_script_dir->to_string;

    my $test_script = $test_script_dir->child('data')->make_path;
    $test_script = $test_script->child($bmwqemu::vars{GUESTINFO_COMBUSTION});
    my $test_string = 'combustion' x 100;
    $test_script->spew($test_string);

    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my $conf_encoded = $svirt_console->_encode_config($test_script->basename, 'GUESTINFO_COMBUSTION');
    like $conf_encoded, qr/^H4sI.*noAwAA$/, 'config encoded';
    is_deeply length $conf_encoded < length $test_string, 1, 'Encoded string is shorter';
    dies_ok { $svirt_console->_encode_config('testingFile') } '_encode_config dies with insufficient amount of arguments passed';
};

subtest 'starting VMware console with InvalidConfig' => sub {
    $bmwqemu::vars{VMWARE_HOST} = 'h';
    $bmwqemu::vars{VMWARE_USERNAME} = 'u';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'p';
    $bmwqemu::vars{GUESTINFO_COMBUSTION} = 'someTestScript';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'NotValid';

    my $chan_mock = Test::MockObject->new->set_true(qw(write send_eof close read2 eof exit_status));
    my $backend_mock = Test::MockModule->new('backend::svirt');
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my $tmp_mock = Test::MockModule->new('File::Temp');
    my (@cmds, @ssh_cmds);
    $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $console_mock->redefine(get_cmd_output => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $backend_mock->redefine(run_ssh => sub ($self, $cmd, %args) { push @ssh_cmds, $cmd; (undef, $chan_mock) });
    $backend_mock->redefine(start_serial_grab => 1);
    $console_mock->redefine(get_ssh_credentials => sub { (hostname => 'foo', username => 'root', password => '123') });
    $tmp_mock->redefine(tempfile => sub { (undef, '/t') });

    dies_ok { $svirt_console->define_and_start } 'Invalid GUESTINFO_CONFIG was passed';
};

subtest 'starting VMware console with combustion' => sub {
    $bmwqemu::vars{VMWARE_HOST} = 'h';
    $bmwqemu::vars{VMWARE_USERNAME} = 'u';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'p';
    $bmwqemu::vars{GUESTINFO_COMBUSTION} = 'someTestScript';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'combustion';

    my $chan_mock = Test::MockObject->new->set_true(qw(write send_eof close read2 eof exit_status));
    my $backend_mock = Test::MockModule->new('backend::svirt');
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my $tmp_mock = Test::MockModule->new('File::Temp');
    my (@cmds, @ssh_cmds);
    $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $console_mock->redefine(get_cmd_output => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $backend_mock->redefine(run_ssh => sub ($self, $cmd, %args) { push @ssh_cmds, $cmd; (undef, $chan_mock) });
    $backend_mock->redefine(start_serial_grab => 1);
    $console_mock->redefine(get_ssh_credentials => sub { (hostname => 'foo', username => 'root', password => '123') });
    $tmp_mock->redefine(tempfile => sub { (undef, '/t') });
    $console_mock->redefine(_encode_config => sub ($self, $f, $k) { 'testingCombustion' });

    $svirt_console->define_and_start;
    like shift @cmds, qr/cat > \/t <<.*username=u.*password=p.*auth-esx-h/s, 'config written';
    my $s = 'virsh -c esx://u@h/?no_verify=1\\&authfile=/t ';
    is_deeply \@cmds, [
        $s . ' destroy openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' undefine --snapshots-metadata openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' define /var/lib/libvirt/images/openQA-SUT-1.xml',
        'echo \'bios.bootDelay = "10000"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'test -e /vmfs/volumes/datastore1/openQA/openQA-SUT-1.nvram',
        'echo \'nvram = "openQA-SUT-1.nvram"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'echo \'guestinfo.combustion.script = "testingCombustion"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        $s . ' start openQA-SUT-1 2> >(tee /tmp/os-autoinst-openQA-SUT-1-stderr.log >&2)',
        $s . ' dumpxml openQA-SUT-1'
    ], 'expected commands invoked' or always_explain \@cmds;
};

subtest 'starting VMware console with ignition' => sub {
    $bmwqemu::vars{VMWARE_HOST} = 'h';
    $bmwqemu::vars{VMWARE_USERNAME} = 'u';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'p';
    $bmwqemu::vars{GUESTINFO_IGNITION} = 'testing/config.ign';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'ignition';
    $bmwqemu::vars{GUESTINFO_COMBUSTION} = undef;

    my $chan_mock = Test::MockObject->new->set_true(qw(write send_eof close read2 eof exit_status));
    my $backend_mock = Test::MockModule->new('backend::svirt');
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my $tmp_mock = Test::MockModule->new('File::Temp');
    my (@cmds, @ssh_cmds);
    $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $console_mock->redefine(get_cmd_output => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $backend_mock->redefine(run_ssh => sub ($self, $cmd, %args) { push @ssh_cmds, $cmd; (undef, $chan_mock) });
    $backend_mock->redefine(start_serial_grab => 1);
    $console_mock->redefine(get_ssh_credentials => sub { (hostname => 'foo', username => 'root', password => '123') });
    $tmp_mock->redefine(tempfile => sub { (undef, '/t') });
    $console_mock->redefine(_encode_config => sub ($self, $f, $k) { 'ignitionTEST' });

    $svirt_console->define_and_start;
    like shift @cmds, qr/cat > \/t <<.*username=u.*password=p.*auth-esx-h/s, 'config written';
    my $s = 'virsh -c esx://u@h/?no_verify=1\\&authfile=/t ';
    is_deeply \@cmds, [
        $s . ' destroy openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' undefine --snapshots-metadata openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' define /var/lib/libvirt/images/openQA-SUT-1.xml',
        'echo \'bios.bootDelay = "10000"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'test -e /vmfs/volumes/datastore1/openQA/openQA-SUT-1.nvram',
        'echo \'nvram = "openQA-SUT-1.nvram"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'echo \'guestinfo.ignition.config.data.encoding = "gzip+base64"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'echo \'guestinfo.ignition.config.data = "ignitionTEST"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        $s . ' start openQA-SUT-1 2> >(tee /tmp/os-autoinst-openQA-SUT-1-stderr.log >&2)',
        $s . ' dumpxml openQA-SUT-1'
    ], 'expected commands invoked' or always_explain \@cmds;
};

subtest 'starting VMware console with cloud-init' => sub {
    $bmwqemu::vars{VMWARE_HOST} = 'h';
    $bmwqemu::vars{VMWARE_USERNAME} = 'u';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'p';
    $bmwqemu::vars{GUESTINFO_CLOUD_INIT} = 'someCloud_init_file1, meta_data';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'cloud-init';
    $bmwqemu::vars{GUESTINFO_COMBUSTION} = undef;

    my $chan_mock = Test::MockObject->new->set_true(qw(write send_eof close read2 eof exit_status));
    my $backend_mock = Test::MockModule->new('backend::svirt');
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my $tmp_mock = Test::MockModule->new('File::Temp');
    my (@cmds, @ssh_cmds);
    $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $console_mock->redefine(get_cmd_output => sub ($self, $cmd, %args) { push @cmds, $cmd; 0 });
    $backend_mock->redefine(run_ssh => sub ($self, $cmd, %args) { push @ssh_cmds, $cmd; (undef, $chan_mock) });
    $backend_mock->redefine(start_serial_grab => 1);
    $console_mock->redefine(get_ssh_credentials => sub { (hostname => 'foo', username => 'root', password => '123') });
    $tmp_mock->redefine(tempfile => sub { (undef, '/t') });
    $console_mock->redefine(_encode_config => sub ($self, $f, $k) { 'CI_test_CONF' });

    $svirt_console->define_and_start;
    like shift @cmds, qr/cat > \/t <<.*username=u.*password=p.*auth-esx-h/s, 'config written';
    my $s = 'virsh -c esx://u@h/?no_verify=1\\&authfile=/t ';
    is_deeply \@cmds, [
        $s . ' destroy openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' undefine --snapshots-metadata openQA-SUT-1 |& grep -v "\\(failed to get domain\\|Domain not found\\)"',
        $s . ' define /var/lib/libvirt/images/openQA-SUT-1.xml',
        'echo \'bios.bootDelay = "10000"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'test -e /vmfs/volumes/datastore1/openQA/openQA-SUT-1.nvram',
        'echo \'nvram = "openQA-SUT-1.nvram"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'echo \'guestinfo.userdata.encoding = "gzip+base64"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'echo \'guestinfo.metadata.encoding = "gzip+base64"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'echo \'guestinfo.userdata = "CI_test_CONF"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        'echo \'guestinfo.metadata = "CI_test_CONF"\' >> /vmfs/volumes/datastore1/openQA/openQA-SUT-1.vmx',
        $s . ' start openQA-SUT-1 2> >(tee /tmp/os-autoinst-openQA-SUT-1-stderr.log >&2)',
        $s . ' dumpxml openQA-SUT-1'
    ], 'expected commands invoked' or always_explain \@cmds;
};

subtest 'SSH credentials' => sub {

    set_var('VIRSH_GUEST', 'foo321');
    set_var('VIRSH_GUEST_PASSWORD', 'password321');
    set_var('VIRSH_VMM_FAMILY', 'hyperv');
    my $svirt = backend::svirt->new();

    my %creds = $svirt->get_ssh_credentials();
    is_deeply(\%creds, {hostname => 'bar', password => 'password', username => 'root'}, 'Check SSH credentials');

    %creds = $svirt->get_ssh_credentials('hyperv');
    is_deeply(\%creds, {hostname => 'foo321', password => 'password321', username => 'root'}, 'Check SSH credentials for hyperv');
};

subtest 'SSH usage in console::sshVirtsh' => sub {
    # Check console::sshVirtsh
    my $ssh_creds_svirt = {hostname => 'hostname_svirt', password => 'password_svirt', username => 'root'};
    my %ssh_expect = (%$ssh_creds_svirt, wantarray => undef, keep_open => undef);
    my $run_ssh_cmd_return = undef;
    my $fake_timeouts = 0;
    my $mock_baseclass = Test::MockModule->new('backend::baseclass');
    $mock_baseclass->redefine('run_ssh_cmd' => sub ($self, $cmd, %args) {
            die 'Time out waiting for data (-9 LIBSSH2_ERROR_TIMEOUT)' if $fake_timeouts-- > 0;
            for my $key (keys(%ssh_expect)) {
                is($args{$key}, $ssh_expect{$key}, "Correct $key for ssh connection") if $ssh_expect{$key};
            }
            if (ref($run_ssh_cmd_return) eq 'ARRAY') {
                return @$run_ssh_cmd_return;
            } else {
                return $run_ssh_cmd_return;
            }
    });

    # W/A cause $svirt_console->activate() didn't worked so far
    $svirt_console->_init_ssh($ssh_creds_svirt);
    $run_ssh_cmd_return = 0;
    is($svirt_console->run_cmd('echo "BLAFAFU"'), 0, "sshVirtsh::run_cmd() test return value");

    $run_ssh_cmd_return = [0, 'BLAFAFU', ''];
    $ssh_expect{wantarray} = 1;
    is_deeply([$svirt_console->run_cmd('echo -n "BLAFAFU"', wantarray => 1)], $run_ssh_cmd_return, "sshVirtsh::run_cmd_(wantarray => 1) ");

    $run_ssh_cmd_return = [undef, 'BLAFAFU', undef];
    is($svirt_console->get_cmd_output('echo -n "BLAFAFU"'), 'BLAFAFU', "sshVirtsh::get_cmd_output()");

    $run_ssh_cmd_return = [undef, 'STDOUT', 'STDERR'];
    is_deeply($svirt_console->get_cmd_output('echo -n "BLAFAFU"', {wantarray => 1}), ['STDOUT', 'STDERR'], "sshVirtsh::get_cmd_output(wantarray => 1 ");
    $ssh_expect{wantarray} = undef;

    $ssh_expect{keep_open} = 0;
    $run_ssh_cmd_return = 0;
    is($svirt_console->run_cmd('echo "BLAFAFU"', keep_open => 0), 0, "sshVirtsh::run_cmd(keep_open=>0) test return value ");
    $ssh_expect{keep_open} = undef;

    subtest 'SSH usage in consoles::sshVirtsh(vmware)' => sub {
        set_var('VMWARE_HOST', 'my_vmware_host');
        set_var('VMWARE_PASSWORD', 'my_vmware_password');
        set_var('VIRSH_VMM_FAMILY', 'vmware');

        my $svirt_vmware_console = consoles::sshVirtsh->new('svirt');
        $svirt_vmware_console->_init_ssh($ssh_creds_svirt);
        $svirt_vmware_console->backend(backend::baseclass->new);

        is($svirt_vmware_console->run_cmd('echo "BLAFAFU"'), 0, "sshVirtsh::run_cmd() Check use of `default` credentials");

        $run_ssh_cmd_return = [undef, 'STDOUT', undef];
        is_deeply($svirt_console->get_cmd_output('echo -n "BLAFAFU"'), 'STDOUT', "sshVirtsh::get_cmd_output() Check use of `default` credentials");

        $ssh_expect{hostname} = 'my_vmware_host';
        $ssh_expect{password} = 'my_vmware_password';
        $run_ssh_cmd_return = 0;
        is($svirt_vmware_console->run_cmd('echo "BLAFAFU"', domain => 'sshVMwareServer'), 0, "sshVirtsh::run_cmd(domain => sshVMwareServer) check use of VMWARE credentials ");

        $run_ssh_cmd_return = [undef, 'STDOUT', undef];
        is_deeply($svirt_vmware_console->get_cmd_output('echo -n "BLAFAFU"', {domain => 'sshVMwareServer'}), 'STDOUT', "sshVirtsh::get_cmd_output() Check use of VMWARE credentials");
    };

    subtest 'running command with retry on ssh timeout' => sub {
        local $bmwqemu::vars{SVIRT_ASSET_DOWNLOAD_ATTEMPTS} = 3;
        %ssh_expect = ();
        $run_ssh_cmd_return = 42;
        $fake_timeouts = 2;
        is $svirt_console->run_cmd_retrying_on_timeouts('foo'), 42, 'got expected return value after retries';
        is $fake_timeouts, -1, 'invoked run_ssh_cmd the expected number of times';
        $fake_timeouts = 3;
        throws_ok { $svirt_console->run_cmd_retrying_on_timeouts('foo') } qr/timeout/i, 'dies after too many timeouts';
    };
};

subtest 'Methods backend::svirt::attach_to_running, start_serial_grab and stop_serial_grab' => sub {
    my $backend_mock = Test::MockObject->new->set_true('start_serial_grab')->set_true('stop_serial_grab');
    $svirt_console->backend($backend_mock);
    $svirt_console->attach_to_running;
    $backend_mock->called_ok('start_serial_grab', 'serial grab attempted');
    is $bmwqemu::vars{SVIRT_KEEP_VM_RUNNING}, 1, 'destructon of VM prevented by default';

    $svirt_console->attach_to_running('foobar');
    is $svirt_console->name, 'foobar', 'console name set';

    $bmwqemu::vars{SVIRT_KEEP_VM_RUNNING} = 0;
    $svirt_console->attach_to_running({name => 'barfoo', stop_vm => 1});
    is $svirt_console->name, 'barfoo', 'console name set (2)';
    is $bmwqemu::vars{SVIRT_KEEP_VM_RUNNING}, 0, 'VM not kept running';

    $backend_mock->clear;
    $svirt_console->start_serial_grab;
    $backend_mock->called_ok('start_serial_grab', 'start serial grab');
    $backend_mock->called_args_pos_is(0, 2, 'barfoo', 'name passed to start serial grab');

    $backend_mock->clear;
    $svirt_console->stop_serial_grab;
    $backend_mock->called_ok('stop_serial_grab', 'stop serial grab');
    $backend_mock->called_args_pos_is(0, 2, 'barfoo', 'name passed to stop serial grab');
};

subtest 'Method backend::svirt::open_serial_console_via_ssh()' => sub {
    my $module = Test::MockModule->new('backend::baseclass');
    my @LAST_;
    my $test_log_cnt = 0;
    my $grep_return = 1;
    my @deleted_logs;
    $module->redefine(run_ssh_cmd => sub {
            my $self = shift;
            @LAST_ = @_;
            my $cmd = shift;
            return !!($test_log_cnt > 0 ? --$test_log_cnt : 0) if ($cmd =~ m/^test -e/);
            return $grep_return if ($cmd =~ m/^grep -q/);
            push @deleted_logs, ($cmd =~ /(\S+)$/) if ($cmd =~ / && rm /);
            return (0, "FOOBAR_OUTPUT", '') if ($cmd =~ m/^cat /);
            die("Adopt test, unexpected call of run_ssh_cmd()");
    });

    my $run_ssh_expect = '$a';
    $module->redefine(run_ssh => sub {
            my ($self, $cmd, %args) = @_;
            like($cmd, qr/$run_ssh_expect/, "run_ssh() command is like qr/$run_ssh_expect/");
            return ('A', 'B');
    });

    delete $bmwqemu::vars{VIRSH_VMM_FAMILY};
    $bmwqemu::vars{JOBTOKEN} = 'XYZ23';

    my $svirt = backend::svirt->new();
    $run_ssh_expect = 'virsh console NAME\s+;';
    $svirt->open_serial_console_via_ssh('NAME');

    $run_ssh_expect = 'virsh console NAME DEV\s*;';
    $svirt->open_serial_console_via_ssh('NAME', devname => 'DEV');
    $run_ssh_expect = 'virsh console NAME DEV666\s*;';
    $svirt->open_serial_console_via_ssh('NAME', devname => 'DEV', port => 666);
    $run_ssh_expect = 'virsh console NAME 666\s*;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware';
    $bmwqemu::vars{VMWARE_HOST} = 'my.vmware.host';
    $run_ssh_expect = 'socat - TCP4:my.vmware.host:,crnl;';
    $svirt->open_serial_console_via_ssh('NAME');
    $run_ssh_expect = 'socat - TCP4:my.vmware.host:666,crnl;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'hyperv';
    $bmwqemu::vars{HYPERV_SERVER} = 'my.hyperv.server';
    $run_ssh_expect = 'socat - TCP4:my.hyperv.server:,crnl;';
    $svirt->open_serial_console_via_ssh('NAME');
    $run_ssh_expect = 'socat - TCP4:my.hyperv.server:666,crnl;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    # Disable command check, as we do not care anymore
    $module->redefine(run_ssh => sub { return ('A', 'B') });
    is_deeply([$svirt->open_serial_console_via_ssh('NAME')], ['A', 'B'], 'Check that we get output from run_ssh() call');

    $bmwqemu::vars{JOBTOKEN} = 'CHECK_DELETE_TOKEN';
    my $expected_serial_file = '/tmp/' . $svirt->SERIAL_TERMINAL_LOG_PATH . '.CHECK_DELETE_TOKEN';
    $test_log_cnt = 11;
    dies_ok { $svirt->open_serial_console_via_ssh('NAME') } "die() when log file wasn't created";
    is(shift @deleted_logs, $expected_serial_file, "Check if $expected_serial_file was deleted on die()");

    $test_log_cnt = 0;
    $grep_return = 0;
    dies_ok { $svirt->open_serial_console_via_ssh('NAME') } 'die() when emulate CONSOLE_EXIT token in log file';
    is(shift @deleted_logs, $expected_serial_file, "Check if $expected_serial_file was deleted on die()");
};

sub svirt_xml_validate ($svirt, %args) {
    $args{disk_device} //= 'disk';
    die 'missing dev' unless $args{dev};
    die 'missing bus' unless $args{bus};
    my $doc = $svirt->{domainxml};

    my $xpath = sprintf('domain/devices/disk[@type="file" and @device="%s"]/target[@dev="%s" and @bus="%s"]',
        $args{disk_device}, $args{dev}, $args{bus});
    my $target_nodelist = $doc->findnodes($xpath);
    is($target_nodelist->size, 1, 'Only one <target> with that dev ' . $args{dev} . ' exists');
    my $target_node = $target_nodelist->shift;
    return unless ($target_node);

    if ($args{source_file}) {
        my $source_node = $target_node->parentNode->findnodes('source')->shift;
        is(defined($source_node), 1, '<disk> has a <source> child');
        is($source_node->getAttribute('file'), $args{source_file}, 'The file attribute of <source> is correct');
    }

    if ($args{driver}) {
        my $driver_node = $target_node->parentNode->findnodes('driver')->shift;
        is(defined($driver_node), 1, '<disk> has a <driver> child');
        is($driver_node->getAttribute('name'), $args{driver}->{name}, 'name attribute of <driver> is correct');
        is($driver_node->getAttribute('type'), $args{driver}->{type}, 'type attribute of <driver> is correct');
        is($driver_node->getAttribute('cache'), $args{driver}->{cache}, 'cache attribute of <driver> is correct');
    }
}

subtest 'Method consoles::sshVirtsh::add_disk()' => sub {
    my $ssh_creds_svirt = {hostname => 'hostname_svirt', password => 'password_svirt', username => 'root'};
    my @last_ssh_commands;
    my @last_ssh_args;
    my @ssh_cmd_return;
    my $_10gb = 1024 * 1024 * 1024 * 10;

    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');
    my @last_system_calls;
    $console_mock->redefine(_system => sub { push @last_system_calls, join ' ', @_; return 0 });
    $console_mock->redefine(which => 1);

    my $mock_baseclass = Test::MockModule->new('backend::baseclass');
    $mock_baseclass->redefine('run_ssh_cmd' => sub {
            my ($self, $cmd, %args) = @_;
            push @last_ssh_commands, $cmd;
            push @last_ssh_args, [%args];

            my $ret = shift @ssh_cmd_return;
            return undef unless defined $ret;

            if (ref($ret) eq 'ARRAY') {
                return @$ret;
            } else {
                return $ret;
            }
    });

    subtest 'family vmware' => sub {
        set_var(VIRSH_INSTANCE => '1');
        set_var(VIRSH_VMM_TYPE => 'XXX');

        set_var(VMWARE_HOST => 'my_vmware_host');
        set_var(VMWARE_PASSWORD => 'my_vmware_password');
        set_var(VIRSH_VMM_FAMILY => 'vmware');
        set_var(VMWARE_DATASTORE => 'my_vmware_datastore');

        my $vmware_openqa_datastore = '/vmfs/volumes/' . get_var('VMWARE_DATASTORE') . '/openQA/';

        my $svirt = consoles::sshVirtsh->new('svirt');
        $svirt->backend(backend::baseclass->new);
        $svirt->_init_ssh($ssh_creds_svirt);
        $svirt->_init_xml();

        subtest 'family vmware only file=>"specified"' => sub {
            my $dev_id = 'device_id_101';
            my $exp_filename = $svirt->name . $dev_id . '.vmdk';
            my $file_name_given = "/fo/bar/" . $exp_filename;

            $svirt->add_disk({dev_id => $dev_id, file => $file_name_given});
            is(scalar(@last_ssh_commands), 0, 'None command was triggered');

            svirt_xml_validate($svirt,
                dev => 'hd' . $dev_id,
                bus => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $exp_filename
            );
        };

        subtest 'vmware create=1' => sub {
            my $dev_id = 'device_id_001';
            my $exp_filename = $svirt->name . $dev_id . '.vmdk';
            my $exp_fullpath = $vmware_openqa_datastore . $exp_filename;
            $svirt->add_disk({create => 1, size => '66G', dev_id => $dev_id});
            my $cmd = shift @last_ssh_commands;
            is(defined($cmd), 1, 'Command was triggered');

            like($cmd, qr/vmkfstools -v1 -U $exp_fullpath;/, "Check name");
            like($cmd, qr/vmkfstools -v1 -c 66G --diskformat thin $exp_fullpath;/, "Check size");

            svirt_xml_validate($svirt,
                dev => 'hd' . $dev_id,
                bus => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $exp_filename
            );
        };

        subtest 'vmware backingfile=1' => sub {
            @last_ssh_commands = ();
            my $dev_id = 'dev_id_002';
            my $filename = 'foo_file.vmdk';
            my $exp_filename = 'foo_file_' . $svirt->name . '_thinfile.vmdk';
            set_var(VMWARE_NFS_DATASTORE => 'nfs');
            $svirt->add_disk({backingfile => 1, size => '77G', dev_id => $dev_id, file => $filename});
            like($last_ssh_commands[1], qr/vmkfstools -v1 -i $vmware_openqa_datastore$filename --diskformat thin $vmware_openqa_datastore$exp_filename;/, "Check size");

            svirt_xml_validate($svirt,
                dev => 'hd' . $dev_id,
                bus => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $exp_filename
            );
        };

        subtest 'vmware cdrom=1' => sub {
            my $dev_id = 'dev_id_003';
            my $filename = 'my_cdrom_file_' . $dev_id . '.iso';
            set_var(VMWARE_NFS_DATASTORE => 'nfs_data_store');
            @last_ssh_commands = ();
            $svirt->add_disk({cdrom => 1, dev_id => $dev_id, file => '/my/path/to/this/file/' . $filename});
            like($last_ssh_commands[0], qr%cp\s+/vmfs/volumes/nfs_data_store/iso/$filename\s+$vmware_openqa_datastore\s*;%, "Copy iso to $vmware_openqa_datastore");

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev => 'hd' . $dev_id,
                bus => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $filename
            );
        };

        subtest 'Check differnt size formattings on vmware' => sub {
            foreach my $size (qw(666k 666K 666M 666G 666T)) {
                my $dev_id = "dev_id_004_$size";
                my $name = $vmware_openqa_datastore . 'openQA-SUT-1' . $dev_id . '\\.vmdk';
                $svirt->add_disk({create => 1, size => $size, dev_id => $dev_id});
                like($last_ssh_commands[-1], qr/vmkfstools -v1 -c $size --diskformat thin $name;/, "Check size $size");
            }
        };
    };

    subtest 'family svirt-xen-hvm' => sub {
        set_var(VIRSH_VMM_FAMILY => 'xen');
        set_var(VIRSH_VMM_TYPE => 'hvm');
        my $basedir = '/var/lib/libvirt/images/';

        my $svirt = consoles::sshVirtsh->new('svirt');
        $svirt->backend(backend::baseclass->new);
        $svirt->_init_ssh($ssh_creds_svirt);
        $svirt->_init_xml();

        subtest 'family xcirt-xen-hvm only file=>"specified"' => sub {
            my $dev_id = 'device_id_105';
            my $exp_filename = $svirt->name . $dev_id . '.iso';
            my $file_name_given = "/fo/bar/" . $exp_filename;

            @last_ssh_commands = ();
            $svirt->add_disk({dev_id => $dev_id, file => $file_name_given});
            is(scalar(@last_ssh_commands), 0, 'None command was triggered');

            svirt_xml_validate($svirt,
                dev => 'xvd' . $dev_id,
                bus => 'xen',
                source_file => $basedir . $exp_filename
            );
        };

        subtest 'family svirt-xen-hvm create=1 error handling' => sub {
            @ssh_cmd_return = ([1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock']);

            my $dev_id = 'dev_id_005';
            my $exp_file = $svirt->name . $dev_id . '.img';
            throws_ok { $svirt->add_disk({create => 1, size => '88G', dev_id => $dev_id}) } qr/Too many attempts to format HDD/, "Died after 5 retry attempts";

            @ssh_cmd_return = ([1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [0, '', '']);
            $svirt->add_disk({create => 1, size => '88G', dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 88G -f qcow2", 'Triggered img creation, after 4 errors');

            @ssh_cmd_return = ([0, '', ''], [0, '', ''], [0, '', ''], [0, '', ''], [0, '', '']);

            subtest 'Check different size formattings' => sub {
                foreach my $size (qw(666k 666K 666M 666G 666T)) {
                    $dev_id = "dev_id_006_$size";
                    $exp_file = $svirt->name . $dev_id . '.img';

                    $svirt->add_disk({create => 1, size => $size, dev_id => $dev_id});
                    is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file $size -f qcow2", "Check different size type $size");
                }
            };

            @ssh_cmd_return = ([0, '', '']);
            $dev_id = 'dev_id_007_NO_SIZE';
            $exp_file = $svirt->name . $dev_id . '.img';
            $svirt->add_disk({create => 1, dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 20G -f qcow2", 'Check for default size 20G');
        };

        # Reset xml
        $svirt->_init_xml();

        subtest 'family svirt-xen-hvm create=1' => sub {
            my $dev_id = 'dev_id_008';
            my $exp_file = $svirt->name . $dev_id . '.img';
            @ssh_cmd_return = ([0, '', '']);
            @last_ssh_commands = ();
            $svirt->add_disk({create => 1, size => '999G', dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 999G -f qcow2", 'Check create image was triggered');

            svirt_xml_validate($svirt,
                dev => 'xvd' . $dev_id,
                bus => 'xen',
                source_file => $basedir . $exp_file,
                driver => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );
        };

        subtest 'family svirt-xen-hvm backingfile=1' => sub {
            my $dev_id = 'dev_id_009';
            my $file = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);

            $svirt->add_disk({
                    backingfile => 1,
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/' . $file,
                    size => 12
            });
            like($last_ssh_commands[0], qr%^rsync.*--partial.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -F qcow2 -b '$basedir/$file' 12G", 'Used image size > backingfile size');
        };

        subtest 'family svirt-xen-hvm backingfile=1 size smaller backingfile-size' => sub {
            my $dev_id = 'dev_id_010';
            my $file = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);
            $svirt->add_disk({
                    backingfile => 1,
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/' . $file,
                    size => 5
            });
            like($last_ssh_commands[0], qr%^rsync.*--partial.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -F qcow2 -b '$basedir/$file' $_10gb", 'Used image size <= backingfile size');

            svirt_xml_validate($svirt,
                dev => 'xvd' . $dev_id,
                bus => 'xen',
                source_file => $basedir . "openQA-SUT-1$dev_id.img",
                driver => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );

            throws_ok { $svirt->add_disk({backingfile => 1, dev_id => $dev_id}) } qr/file/, "Die on missing file argument";
        };

        subtest 'family svirt-xen-hvm cdrom=1' => sub {
            my $dev_id = 'dev_id_011';
            my $file = "my_cdrom_$dev_id.iso";
            @last_ssh_commands = ();
            @ssh_cmd_return = (0, 0);
            $svirt->add_disk({
                    cdrom => 1,
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/' . $file,
            });
            like($last_ssh_commands[0], qr%^rsync.*--partial.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy cdrom iso');

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev => 'sd' . $dev_id,
                bus => 'scsi',
                source_file => $basedir . $file,
                driver => {name => 'qemu', type => 'raw', cache => undef}
            );

            throws_ok { $svirt->add_disk({cdrom => 1, dev_id => $dev_id}) } qr/file/, "Die on missing file argument";
        };
    };

    subtest 'family kvm' => sub {
        set_var(VIRSH_VMM_FAMILY => 'kvm');
        set_var(VIRSH_VMM_TYPE => undef);
        my $basedir = '/var/lib/libvirt/images/';

        my $svirt = consoles::sshVirtsh->new('svirt');
        $svirt->backend(backend::baseclass->new);
        $svirt->_init_ssh($ssh_creds_svirt);
        $svirt->_init_xml();

        subtest 'family kvm create=1' => sub {
            my $dev_id = 'dev_id_012';
            my $exp_file = $svirt->name . $dev_id . ".img";

            @ssh_cmd_return = ([0, '', '']);
            $svirt->add_disk({create => 1, size => '778G', dev_id => $dev_id});

            svirt_xml_validate($svirt,
                dev => 'vd' . $dev_id,
                bus => 'virtio',
                source_file => $basedir . $exp_file,
                driver => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );
        };

        subtest 'family kvm create=1 size types' => sub {
            @ssh_cmd_return = ([0, '', ''], [0, '', ''], [0, '', ''], [0, '', ''], [0, '', ''], [0, '', '']);
            foreach my $size (qw(666k 666K 666M 666G 666T)) {
                my $dev_id = 'dev_id_013' . $size;
                my $exp_file = $svirt->name . $dev_id . ".img";
                $svirt->add_disk({create => 1, size => $size, dev_id => $dev_id});
                is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file $size -f qcow2", "Check different size type $size");
            }

            my $dev_id = 'dev_id_014_NO_SIZE';
            my $exp_file = $svirt->name . $dev_id . ".img";
            $svirt->add_disk({create => 1, dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 20G -f qcow2", "Default size is 20G");
        };

        subtest 'family svirt-xen-hvm backingfile=1' => sub {
            my $dev_id = 'dev_id_015';
            my $file = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);

            $svirt->add_disk({
                    backingfile => 1,
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/' . $file,
                    size => 12
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -F qcow2 -b '$basedir/$file' 12G", 'Used image size > backingfile size');
        };

        subtest 'family kvm backingfile=1 size smaller then backingfile' => sub {
            my $dev_id = 'dev_id_016';
            my $file = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);
            $svirt->add_disk({
                    backingfile => 1,
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/' . $file,
                    size => 5
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -F qcow2 -b '$basedir/$file' $_10gb", 'Used image size <= backingfile size');

            svirt_xml_validate($svirt,
                dev => 'vd' . $dev_id,
                bus => 'virtio',
                source_file => $basedir . "openQA-SUT-1$dev_id.img",
                driver => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );
        };

        subtest 'family kvm cdrom=1' => sub {
            my $dev_id = 'dev_id_017';
            my $file = "my_cdrom_$dev_id.iso";
            @last_ssh_commands = ();
            @last_ssh_args = ();
            @ssh_cmd_return = (0, 0);
            $svirt->add_disk({
                    cdrom => 1,
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/' . $file,
            });
            like($last_ssh_commands[0], qr%^rsync.*--timeout='150' --stats .*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy cdrom iso');
            my %ssh_args = @{$last_ssh_args[0]};
            is $ssh_args{timeout}, 900, 'timeout for ssh command specified';

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev => 'hd' . $dev_id,
                bus => 'ide',
                source_file => $basedir . $file,
                driver => {name => 'qemu', type => 'raw', cache => undef}
            );
        };

        subtest 'family kvm cdrom=1 xz file, using cached file' => sub {
            my $dev_id = 'dev_id_018';
            my $file_wo_xz = "my_compressed_cdrom_$dev_id.iso";
            my $file = path($file_wo_xz . '.xz')->touch;
            my $file_path = '/my/path/to/this/file/' . $file;
            @last_system_calls = ();
            @last_ssh_commands = ();
            @ssh_cmd_return = (0, 0);
            $svirt->add_disk({cdrom => 1, dev_id => $dev_id, file => $file_path});
            is $last_system_calls[0], "sshpass -p 'password_svirt' rsync -e 'ssh -o StrictHostKeyChecking=no' --timeout='150' --stats --partial --append-verify -av '$dir/$file' 'root\@hostname_svirt:$basedir/$file'", 'file copied with rsync';
            like $last_ssh_commands[0], qr%unxz%, 'file uncompressed with unxz';

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev => 'hd' . $dev_id,
                bus => 'ide',
                source_file => $basedir . $file_wo_xz,
                driver => {name => 'qemu', type => 'raw', cache => undef}
            );
        };

        subtest 'check bootorder argument' => sub {
            my $dev_id = 'dev_id_019';
            $svirt->add_disk({
                    cdrom => 1,
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/foo_file.iso',
                    bootorder => 'MyArbitraryBootOrderArgument'
            });
            my $target_nodelist = $svirt->{domainxml}->findnodes('domain/devices/disk[@type="file" and @device="cdrom"]/boot[@order="MyArbitraryBootOrderArgument"]');
            is($target_nodelist->size(), 1, 'Boot order entry was created in <disk device="cdrom">');

            $dev_id = 'dev_id_020';
            $svirt->add_disk({
                    dev_id => $dev_id,
                    file => '/my/path/to/this/file/foo_file2.iso',
                    bootorder => 'MyArbitraryBootOrderArgumentXXX'
            });
            $target_nodelist = $svirt->{domainxml}->findnodes('domain/devices/disk[@type="file" and @device="disk"]/boot[@order="MyArbitraryBootOrderArgumentXXX"]');
            is($target_nodelist->size(), 1, 'Boot order entry was created in <disk device="disk">');

        }
    };
    subtest 'family svirt-xen-pv' => sub {
        set_var(VIRSH_VMM_FAMILY => 'xen');
        set_var(VIRSH_VMM_TYPE => 'linux');
        my $basedir = '/var/lib/libvirt/images/';

        my $svirt = consoles::sshVirtsh->new('svirt');
        $svirt->backend(backend::baseclass->new);
        $svirt->_init_ssh($ssh_creds_svirt);
        $svirt->_init_xml();

        subtest 'family svirt-xen-pv only file=>"specified"' => sub {
            my $dev_id = 'device_id_105';
            my $exp_filename = $svirt->name . $dev_id . '.iso';
            my $file_name_given = "/fo/bar/" . $exp_filename;

            @last_ssh_commands = ();
            $svirt->add_disk({dev_id => $dev_id, file => $file_name_given});
            $svirt->add_usb_hub();
            is(scalar(@last_ssh_commands), 0, 'None command was triggered');

            svirt_xml_validate($svirt,
                dev => 'xvd' . $dev_id,
                bus => 'xen',
                source_file => $basedir . $exp_filename,
                usb => 1
            );
        };

        subtest '<controller type="usb" index="0" ports="8"/>' => sub {
            my $doc = $svirt->{domainxml};
            my $target = $doc->findnodes('domain/devices/controller')->shift();
            my $driver_node = $target->parentNode->findnodes('controller')->shift;
            is($driver_node->getAttribute('ports'), 8, 'no. of ports <controller> is correct');
            is($driver_node->getAttribute('type'), 'usb', 'type attribute of <controller> is correct');
        };
    };
};

subtest 'get_wait_still_screen_on_here_doc_input' => sub {
    set_var(VIRSH_VMM_FAMILY => 'hyperv');
    is($svirt->get_wait_still_screen_on_here_doc_input({}) > 0, 1, 'wait_still_screen on here doc is set for hyperv');
    set_var(VIRSH_VMM_FAMILY => 'vmware');
    is($svirt->get_wait_still_screen_on_here_doc_input({}) > 0, 1, 'wait_still_screen on here doc is set for vmware');
    set_var(VIRSH_VMM_FAMILY => 'kvm');
    is($svirt->get_wait_still_screen_on_here_doc_input({}), 0, 'wait_still_screen on here doc is not set for kvm');
};

subtest 'Test routine consoles::sshVirtsh::provide_image_vmware_in_ds' => sub {
    # Temporary base subdir of this test; real default is /vmfs/volumes.
    # All contents will be deleted after the test completed
    my $my_test_basedir = tempdir($dir . '/tb_XXXX');
    my $nfs_ds = 'openqa_test';
    my $ds = 'datastore_test';
    $bmwqemu::vars{VMWARE_NFS_DATASTORE_DEBUG} = '0';
    $bmwqemu::vars{VIRSH_OPENQA_BASEDIR} = $my_test_basedir;
    $bmwqemu::vars{VMWARE_DATASTORE} = $ds;
    $bmwqemu::vars{VMWARE_NFS_DATASTORE} = $nfs_ds;
    # VMware image files path on test host:
    # origin path definition, like: /vmfs/volumes/openqa/hdd/img.vmdk.xz
    my $my_test_dir = path($my_test_basedir, $nfs_ds);
    my $my_test_dir_hdd = path($my_test_dir, 'hdd');
    my $my_test_dir_iso = path($my_test_dir, 'iso');
    # destination path definition, like: /vmfs/volumes/Datastore1/openQA/img.vmdk.xz
    my $vmware_openqa_datastore = path($my_test_basedir, $ds, 'openQA');
    my $svirt = consoles::sshVirtsh->new('svirt');
    my $console_mock = Test::MockModule->new('consoles::sshVirtsh');

    subtest 'vmw-test-1: static check script preparation before execution' => sub {
        my @last_run_commands = ();
        # image definition, object only, no file creation
        my $input_file = path('vmware-mock-1-image.vmdk');
        my $input_file_xz = path($input_file . '.xz');
        my $input_file2 = path('vmware-mock-1-image.iso');
        my $input_file2_xz = path($input_file2 . '.xz');
        $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) {
                push @last_run_commands, $cmd;
                0;
        });
        my $n = 0;
        # check script body resulting from parameters:
        foreach my $tuple (
            [$input_file_xz, "/hdd/$input_file_xz", "$input_file_xz", 1],
            [path($my_test_dir_hdd, $input_file), "/hdd/$input_file", "$input_file_xz", 1],
            [path($my_test_dir_iso, $input_file2_xz), "/iso/$input_file2_xz", "$input_file2_xz", 0],
            [path($my_test_dir_iso, $input_file2), "/iso/$input_file2", "$input_file2_xz", '']
        ) {
            my ($inp, $qry, $qry_xz, $backf_trig) = @$tuple;
            $svirt->provide_image_vmware_in_ds($inp, $vmware_openqa_datastore, backingfile => $backf_trig);
            like $last_run_commands[$n], qr{cp\s.*$qry\"\s\"$vmware_openqa_datastore}, 'vmw-test-1: checking image management script, file origin:' . $n . 'a';
            like $last_run_commands[$n], qr{xz\s.*$vmware_openqa_datastore/$qry_xz}, 'vmw-test-1: checking image management script, file destination: ' . $n . 'b';
            $n += 1;
        }
    };

    subtest 'wmv-test-2: check shell script execution' => sub {
        my @last_run_commands = ();
        my @output = ();
        my $input_file = path('vmware-mock-2-image.vmdk');
        my $input_file_xz = path($input_file . '.xz');
        my $input_file2 = path('vmware-mock-2-image.iso');
        my $input_file2_xz = path($input_file2 . '.xz');
        # create path on FS
        $my_test_dir->make_path;
        $my_test_dir_hdd->make_path;
        $my_test_dir_iso->make_path;
        $vmware_openqa_datastore->make_path;
        # origin full path file, define, create, compress, check
        my $file = path($my_test_dir, $input_file);
        my $file2 = path($my_test_dir, $input_file2);
        $file->spew('VMmware image vmdk');
        $file2->spew('VMmware image iso');
        qx(xz -f --compress --keep $file);
        qx(xz -f --compress --keep $file2);
        my $file_xz = path($my_test_dir, $input_file_xz);
        my $file2_xz = path($my_test_dir, $input_file2_xz);
        ok -e $file_xz, "mock image $file_xz created.";
        ok -e $file2_xz, "mock image iso $file2_xz created.";
        ok -e $file, "mock image $file exists.";
        ok -e $file2, "mock image iso $file2 exists.";
        # populate hdd, iso with vaild files.
        my $file_i = path($file2)->copy_to($my_test_dir_iso);
        my $file_h = path($file)->copy_to($my_test_dir_hdd);
        my $file_xz_i = path($file2_xz)->copy_to($my_test_dir_iso);
        my $file_xz_h = path($file_xz)->copy_to($my_test_dir_hdd);
        $console_mock->redefine(run_cmd => sub ($self, $cmd, %args) {
                push @last_run_commands, $cmd;
                # run shell script in local host.
                my $out = qx($cmd);
                ($? >> 8);
        });
        # pre-cleanup dest. file xz
        path($vmware_openqa_datastore, $input_file_xz)->remove;
        path($vmware_openqa_datastore, $input_file2_xz)->remove;
        my $i = 0;
        foreach my $tuple (
            [path($my_test_dir_hdd, $input_file_xz), "/hdd/$input_file_xz", "$input_file", 1, 1],
            [$input_file, "/hdd/$input_file", "$input_file", 1, 1],
            [$input_file2, "/iso/$input_file2", "$input_file2", '', 1],
            [$input_file2_xz, "/iso/$input_file2_xz", "$input_file2", 0, 0]
        ) {
            my ($input, $qry, $file_out, $backf_trig, $preclean) = @$tuple;
            # pre-cleanup file in destination dir. to trigger reload
            path($vmware_openqa_datastore, $file_out)->remove if $preclean;
            $output[$i] = $svirt->provide_image_vmware_in_ds($input, $vmware_openqa_datastore, backingfile => $backf_trig);
            like $last_run_commands[$i], qr{$qry}, 'wmv-test-2: checking image management ' . $input . ': ' . $i . 'a';
            like $output[$i], qr{$vmware_openqa_datastore/$file_out}, 'wmv-test-2: checking image management output: ' . $input . ': ' . $i . 'b';
            $i += 1;
        }
    };
};

done_testing;
