#!/usr/bin/perl

use Cwd qw(abs_path);
use Test::Most;
use File::chdir;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Mojo::Base -strict, -signatures;
use Test::MockRandom 'backend::vagrant';
use Test::MockObject;
use Test::MockModule;
use Test::Warnings ':report_warnings';
use Test::Output qw(stderr_like);
use backend::vagrant;

use bmwqemu ();

# hide debug messages, keep warnings & errors
$log::logger = Mojo::Log->new(level => 'warn');

my $mock_vagrant = Test::MockModule->new("vagrant", no_auto => 1);
$mock_vagrant->noop('mkdir');

my $tmpdir = File::Temp->newdir();
my $mock_file_tmp = Test::MockModule->new("File::Temp");
$mock_file_tmp->redefine('newdir', $tmpdir);

my $expected_console_name = undef;
my $expected_console_type = undef;
my %expected_console_credentials = ();
my $distri = Test::MockModule->new('distribution');
$distri->redefine('add_console', sub ($self, $name, $type, $creds) {
        local $Test::Builder::Level = $Test::Builder::Level + 1;

        if (defined($expected_console_name)) {
            die "Invalid console name '$name'. Expected '$expected_console_name'" unless $name eq $expected_console_name;
        }
        if (defined($expected_console_type)) {
            die "Invalid console type '$type'. Expected '$expected_console_type'" unless $type eq $expected_console_type;
        }
        if (keys %expected_console_credentials) {
            is_deeply($creds, \%expected_console_credentials, 'Check the name of the console');
        }
        my $ret = Test::MockObject->new();
        $ret->set_true('backend');
        return $ret;
});
$testapi::distri = distribution->new;

my $check_socket_ret = undef;
my $check_socket_fh_expected = undef;
my $check_socket_write_expected = undef;
my $mock_base = Test::MockModule->new("backend::baseclass", no_auto => 1);
$mock_base->redefine('check_socket', sub ($self, $fh, $write) {
        if (defined($check_socket_fh_expected)) {
            die "Invalid fh '$fh'. Expected '$fh'" unless $fh eq $check_socket_fh_expected;
        }
        if (defined($check_socket_write_expected)) {
            die "Invalid write '$write'. Expected '$check_socket_write_expected'" unless $write eq $check_socket_write_expected;
        }
        return $check_socket_ret;
});


my $mock_run = Test::MockModule->new("IPC::Run");
my $mock_file = Test::MockModule->new("File::chdir");

my $expected_spew_str = undef;
my $mock_path = Test::MockObject->new();
$mock_path->mock('make_path', sub ($self, %opts) { return $self; });
$mock_path->mock('child', sub ($self, $child_name) { return $self; });
$mock_path->mock('spew', sub ($self, $str) {
        if (defined($expected_spew_str)) {
            die "Invalid spew contents '$str', expected '$expected_spew_str'" unless $str eq $expected_spew_str;
        }
        return $self;
});

my $mock_mojo_file = Test::MockModule->new("Mojo::File");
$mock_mojo_file->redefine('path', $mock_path);

my $ipc_run_retval = [];

my $mock_handle = Test::MockObject->new();
$mock_handle->mock('full_result', sub {
        return (@$ipc_run_retval > 0) ? pop(@$ipc_run_retval) : 0;
});
my $run_expect_cmd = [];
my $run_stdout_to_write = [];
my $run_stderr_to_write = [];

$mock_run->redefine('start', sub ($cmd, $stdin, $stdout, $stderr, $timeout = undef) {
        $$stdout = (@$run_stdout_to_write > 0) ? pop(@$run_stdout_to_write) : '';
        $$stderr = (@$run_stderr_to_write > 0) ? pop(@$run_stderr_to_write) : '';

        if (@$run_expect_cmd > 0) {
            my $next_expected_cmd = pop(@$run_expect_cmd);
            is_deeply($cmd, $next_expected_cmd);
        }
        return $mock_handle;
});

$mock_run->redefine('finish');

my $backend_vars = \%bmwqemu::vars;
$backend_vars->{VAGRANT_PROVIDER} = "libvirt";
$backend_vars->{VAGRANT_BOX} = "foobar";

my $vagrant = backend::vagrant->new();

subtest 'Vagrantfile for the libvirt provider' => sub {
    $backend_vars->{VAGRANT_PROVIDER} = "libvirt";
    $backend_vars->{VAGRANT_BOX} = "foobar";
    $backend_vars->{QEMUCPUS} = 3;
    $backend_vars->{QEMURAM} = 3072;

    $expected_spew_str = <<'END';
Vagrant.configure("2") do |config|
  config.vm.box = "foobar"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider :libvirt do |libvirt|
    libvirt.cpus = 3
    libvirt.memory = 3072
    libvirt.storage_pool_name = "vagrant0"
  end
end
END
    my $libvirt_vagrant = backend::vagrant->new();
    is($libvirt_vagrant->{box_name}, $backend_vars->{VAGRANT_BOX}, 'Backend variable matches box_name class variable');
    is($libvirt_vagrant->{provider}, $backend_vars->{VAGRANT_PROVIDER}, 'Backend variable matches provider class variable');

    $expected_spew_str = undef;
};

subtest 'Vagrantfile for the virtualbox provider' => sub {
    $backend_vars->{VAGRANT_PROVIDER} = "virtualbox";
    $backend_vars->{VAGRANT_BOX} = "barBaz";
    $backend_vars->{QEMUCPUS} = 18;
    $backend_vars->{QEMURAM} = 2042;

    $expected_spew_str = <<'END';
Vagrant.configure("2") do |config|
  config.vm.box = "barBaz"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider "virtualbox" do |v|
    v.memory = 2042
    v.cpus = 18
  end
end
END
    my $virtualbox_backend = backend::vagrant->new();
    is($virtualbox_backend->{box_name}, $backend_vars->{VAGRANT_BOX}, 'Backend variable matches box_name class variable');
    is($virtualbox_backend->{provider}, $backend_vars->{VAGRANT_PROVIDER}, 'Backend variable matches provider class variable');

    $expected_spew_str = undef;
};

subtest 'Vagrantfile with a box url' => sub {
    $backend_vars->{VAGRANT_PROVIDER} = "libvirt";
    $backend_vars->{VAGRANT_BOX} = "Leap-15.2.x86_64";
    $backend_vars->{VAGRANT_BOX_URL} = "http://download.opensuse.org/distribution/leap/15.2/appliances/boxes/Leap-15.2.x86_64.json";
    $backend_vars->{QEMUCPUS} = 1;
    $backend_vars->{QEMURAM} = 1024;


    $expected_spew_str = <<'END';
Vagrant.configure("2") do |config|
  config.vm.box = "Leap-15.2.x86_64"
  config.vm.box_url = "http://download.opensuse.org/distribution/leap/15.2/appliances/boxes/Leap-15.2.x86_64.json"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider :libvirt do |libvirt|
    libvirt.cpus = 1
    libvirt.memory = 1024
    libvirt.storage_pool_name = "vagrant0"
  end
end
END
    my $provider_with_url = backend::vagrant->new();
    is($provider_with_url->{box_name}, $backend_vars->{VAGRANT_BOX}, 'Backend variable matches box_name class variable');
    is($provider_with_url->{provider}, $backend_vars->{VAGRANT_PROVIDER}, 'Backend variable matches provider class variable');
    is($provider_with_url->{box_url}, $backend_vars->{VAGRANT_BOX_URL}, 'Backend variable matches box_url class variable');

    $expected_spew_str = undef;
    $backend_vars->{VAGRANT_BOX_URL} = undef;
};

subtest 'backend creation dies when VAGRANT_ASSETDIR cannot be opened' => sub {
    my $fakedir = '/foo/bar/baz/duitraen/dont/create/this/folder/16';
    $backend_vars->{VAGRANT_ASSETDIR} = $fakedir;
    $backend_vars->{VAGRANT_BOX} = "/foobar";

    eval { backend::vagrant->new(); };
    like($@, qr/Could not opendir $fakedir/, 'opendir error message is present in the output');

    $backend_vars->{VAGRANT_BOX} = "foobar";
    $backend_vars->{ASSETDIR} = undef;
};

subtest 'backend creation dies when the vagrant box is not in VAGRANT_ASSETDIR' => sub {
    $backend_vars->{VAGRANT_ASSETDIR} = $tmpdir;
    $backend_vars->{VAGRANT_BOX} = "/foobar";

    eval { backend::vagrant->new(); };
    like(
        $@, qr/File $tmpdir\/foobar does not exist/,
        'error message that the box was not found is in the output'
    );

    $backend_vars->{VAGRANT_BOX} = "foobar";
    $backend_vars->{ASSETDIR} = undef;
};

subtest 'Vagrantfile with a box file existing in VAGRANT_ASSETDIR' => sub {
    my $box_name = "/Tumbleweed.box";
    my $box_file = "$tmpdir$box_name";
    $mock_mojo_file->original("path")->($box_file)->touch();

    $backend_vars->{VAGRANT_ASSETDIR} = $tmpdir;
    $backend_vars->{VAGRANT_PROVIDER} = 'libvirt';
    $backend_vars->{VAGRANT_BOX} = $box_name;
    $backend_vars->{QEMUCPUS} = 1;
    $backend_vars->{QEMURAM} = 1024;

    $expected_spew_str = <<END;
Vagrant.configure("2") do |config|
  config.vm.box = "$box_file"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider :libvirt do |libvirt|
    libvirt.cpus = 1
    libvirt.memory = 1024
    libvirt.storage_pool_name = "vagrant0"
  end
end
END
    my $local_file_backend = backend::vagrant->new();
    like($local_file_backend->{box_name}, qr/$backend_vars->{VAGRANT_BOX}/, 'Backend variable matches box_name class variable');
    is($local_file_backend->{provider}, $backend_vars->{VAGRANT_PROVIDER}, 'Backend variable matches provider class variable');

    $expected_spew_str = undef;
    $backend_vars->{ASSETDIR} = undef;
    $backend_vars->{VAGRANT_BOX} = "foobar";

    unlink($box_file) or die $!;
};

subtest 'dies on invalid providers' => sub {
    $backend_vars->{VAGRANT_PROVIDER} = 'superVirt';

    eval { backend::vagrant->new(); };
    like($@, qr/unknown vagrant provider superVirt/, 'backend creation dies on invalid providers');
};

subtest 'get_ssh_credentials returns default values' => sub {
    $run_expect_cmd = [["vagrant", "ssh-config"]];
    $run_stdout_to_write = [];
    my %credentials = $vagrant->get_ssh_credentials();
    my %default_credentials = (hostname => "localhost", username => "vagrant", password => "vagrant", port => 22);
    is_deeply(\%credentials, \%default_credentials, 'get_ssh_credentials returns the defaults without a match in stdout');
};

subtest 'get_ssh_credentials parses the ssh configuration' => sub {
    $run_expect_cmd = [["vagrant", "ssh-config"]];
    my $ssh_config_output = << 'END';
Host default
  HostName 192.168.122.9
  User foobar
  Port 2328
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile /home/dan/tmp/.vagrant/machines/default/libvirt/private_key
  IdentitiesOnly yes
  LogLevel FATAL


END
    $run_stdout_to_write = [$ssh_config_output];

    my %credentials = $vagrant->get_ssh_credentials();
    my %expected_credentials = (hostname => "192.168.122.9", username => "foobar", password => "vagrant", port => 2328);
    is_deeply(\%credentials, \%expected_credentials, 'get_ssh_credentials extracts data from vagrant ssh-config');
};

subtest 'run_cmd invokes vagrant ssh' => sub {
    $run_expect_cmd = [["vagrant", "ssh", "--", "cat", "/etc/os-release"]];
    my $os_release = 'NAME="openSUSE Tumbleweed"';
    $run_stdout_to_write = [$os_release];
    my $res = $vagrant->run_cmd("cat /etc/os-release");

    is($res, $os_release, 'run_cmd returns the IPC::Run stdout');
};

subtest 'do_stop_vm does not try to remove the libvirt storage pool when using virtualbox' => sub {
    $run_expect_cmd = [
        ["vagrant", "box", "--machine-readable", "remove", "-af", "--provider", "virtualbox", "baz"],
        ["vagrant", "destroy", "--machine-readable", "-f"],
        ["vagrant", "halt", "--machine-readable"]
    ];

    $backend_vars->{VAGRANT_PROVIDER} = "virtualbox";
    $backend_vars->{VAGRANT_BOX} = "baz";
    my $virtualbox = backend::vagrant->new();

    $virtualbox->do_stop_vm();
};

subtest 'do_stop_vm halts the vm, destroys the vm and removes the base box and the libvirt storage pool' => sub {
    $run_expect_cmd = [
        ["virsh", "pool-destroy", "vagrant0"],
        ["vagrant", "box", "--machine-readable", "remove", "-af", "--provider", "libvirt", "foobar"],
        ["vagrant", "destroy", "--machine-readable", "-f"],
        ["vagrant", "halt", "--machine-readable"]
    ];
    my $res = $vagrant->do_stop_vm();
};

subtest 'do_stop_vm logs when vagrant halt fails' => sub {
    $run_expect_cmd = [["vagrant", "halt", "--machine-readable"]];
    $ipc_run_retval = [1];

    stderr_like(
        sub { $vagrant->do_stop_vm(); },
        qr/vagrant: failed to execute vagrant halt, got 1/,
        'do_stop_vm stderr log contains an error message including vagrant halt'
    );
};

subtest 'do_stop_vm logs when destroying the vm fails' => sub {
    $run_expect_cmd = [
        ["vagrant", "destroy", "--machine-readable", "-f"],
        ["vagrant", "halt", "--machine-readable"]
    ];
    $ipc_run_retval = [1, 0];

    stderr_like(
        sub { $vagrant->do_stop_vm(); },
        qr/vagrant: failed to destroy the vagrant VM, got/,
        'do_stop_vm stderr contains an error message mentioning that vagrant box destroy failed'
    );
};

subtest 'do_stop_vm logs when removing the box fails' => sub {
    $run_expect_cmd = [
        ["vagrant", "box", "--machine-readable", "remove", "-af", "--provider", "libvirt", "foobar"],
        ["vagrant", "destroy", "--machine-readable", "-f"],
        ["vagrant", "halt", "--machine-readable"]
    ];
    $ipc_run_retval = [1, 0, 0];

    stderr_like(
        sub { $vagrant->do_stop_vm(); },
        qr/vagrant: failed to destroy the vagrant box foobar/,
        'do_stop_vm stderr contains an error message mentioning that vagrant box remove failed'
    );
};

subtest 'do_stop_vm logs when destroying the libvirt pool fails' => sub {
    $run_expect_cmd = [
        ["virsh", "pool-destroy", "vagrant0"],
        ["vagrant", "box", "--machine-readable", "remove", "-af", "--provider", "libvirt", "foobar"],
        ["vagrant", "destroy", "--machine-readable", "-f"],
        ["vagrant", "halt", "--machine-readable"]
    ];
    $ipc_run_retval = [3, 0, 0, 0];

    stderr_like(
        sub { $vagrant->do_stop_vm(); },
        qr/vagrant: failed to destroy the libvirt storage pool vagrant0, got 3/,
        'do_stop_vm stderr contains an error message mentioning that vagrant box remove failed'
    );
};

subtest 'do_start_vm launches vm via vagrant up and configures a ssh terminal' => sub {
    $run_expect_cmd = [
        ["vagrant", "ssh-config"],
        ["vagrant", "up", "--machine-readable", "--provider", "libvirt"],
        ["virsh", "pool-create-as", "--target", "$tmpdir/pool", "--name", "vagrant0", "--type", "dir"]
    ];
    $expected_console_name = 'vagrant-ssh';
    $expected_console_type = 'ssh-serial';
    %expected_console_credentials = (hostname => "localhost", username => "vagrant", password => "vagrant", port => 22);

    $vagrant->do_start_vm();

    $expected_console_type = undef;
    $expected_console_name = undef;
    %expected_console_credentials = ();
};

subtest 'do_start_vm dies when the libvirt pool cannot be created' => sub {
    $run_expect_cmd = [
        ["virsh", "pool-create-as", "--target", "$tmpdir/pool", "--name", "vagrant0", "--type", "dir"]
    ];
    $ipc_run_retval = [1];
    $run_stdout_to_write = ['fooStdout'];
    $run_stderr_to_write = ['barStderr'];

    eval { $vagrant->do_start_vm(); };
    like($@, qr/Create libvirt storage pool failed with exit code: 1/, 'Check the error message reported by do_start_vm');
    like($@, qr/fooStdout/, 'Check that the error message contains stdout');
    like($@, qr/barStderr/, 'Check that the error message contains stderr');
};

subtest 'do_start_vm does not die when the libvirt pool already exists' => sub {
    my $virsh_pool_exists_stderr = <<'END';
error: Failed to create pool vagrant0
error: operation failed: pool 'vagrant0' already exists with uuid 0ad1d63e-a52f-4524-8b33-b20cca52d57b

END
    $run_expect_cmd = [
        ["virsh", "pool-create-as", "--target", "$tmpdir/pool", "--name", "vagrant0", "--type", "dir"]
    ];
    $ipc_run_retval = [1];
    $run_stdout_to_write = [''];
    $run_stderr_to_write = [$virsh_pool_exists_stderr];

    $vagrant->do_start_vm();
};

subtest 'do_start_vm dies when vagrant up returns an error' => sub {
    $run_expect_cmd = [
        ["vagrant", "up", "--machine-readable", "--provider", "libvirt"],
        ["virsh", "pool-create-as", "--target", "$tmpdir/pool", "--name", "vagrant0", "--type", "dir"]
    ];
    $ipc_run_retval = [1, 0];
    $run_stdout_to_write = ['fooStdout', ''];
    $run_stderr_to_write = ['barStderr', ''];

    eval { $vagrant->do_start_vm(); };
    like($@, qr/Failed to execute vagrant up/, 'Check the error message reported by do_start_vm');
    like($@, qr/fooStdout/, 'Check that the error message contains stdout');
    like($@, qr/barStderr/, 'Check that the error message contains stderr');
};

subtest 'do_start_vm does not call to virsh when using virtualbox' => sub {
    $run_expect_cmd = [
        ["vagrant", "ssh-config"],
        ["vagrant", "up", "--machine-readable", "--provider", "virtualbox"],
    ];

    $backend_vars->{VAGRANT_PROVIDER} = "virtualbox";
    my $virtualbox = backend::vagrant->new();

    $virtualbox->do_start_vm();
    is(@$run_expect_cmd, 0, 'Both commands should have been executed');
};

subtest 'is_shutdown reports the status correctly' => sub {
    $run_expect_cmd = [
        ["vagrant", "status", "--machine-readable"],
        ["vagrant", "status", "--machine-readable"],
        ["vagrant", "status", "--machine-readable"]
    ];
    my $libvirt_running_stdout = << 'END';
1623931306,default,metadata,provider,libvirt
1623931306,default,provider-name,libvirt
1623931306,default,state,running
1623931306,default,state-human-short,running
1623931306,default,state-human-long,The Libvirt domain is running. To stop this machine%!(VAGRANT_COMMA) you can run\n`vagrant halt`. To destroy the machine%!(VAGRANT_COMMA) you can run `vagrant destroy`.
1623931306,,ui,info,Current machine states:\n\ndefault                   running (libvirt)\n\nThe Libvirt domain is running. To stop this machine%!(VAGRANT_COMMA) you can run\n`vagrant halt`. To destroy the machine%!(VAGRANT_COMMA) you can run `vagrant destroy`.

END
    my $libvirt_not_running_stdout = << 'END';
1623931749,default,metadata,provider,libvirt
1623931749,default,provider-name,libvirt
1623931749,default,state,shutoff
1623931749,default,state-human-short,shutoff
1623931749,default,state-human-long,The Libvirt domain is not running. Run `vagrant up` to start it.
1623931749,,ui,info,Current machine states:\n\ndefault                   shutoff (libvirt)\n\nThe Libvirt domain is not running. Run `vagrant up` to start it.

END
    my $libvirt_not_created_stdout = <<'END';
1623931891,default,metadata,provider,libvirt
1623931891,default,provider-name,libvirt
1623931891,default,state,not_created
1623931891,default,state-human-short,not created
1623931891,default,state-human-long,The Libvirt domain is not created. Run `vagrant up` to create it.
1623931891,,ui,info,Current machine states:\n\ndefault                   not created (libvirt)\n\nThe Libvirt domain is not created. Run `vagrant up` to create it.

END

    $run_stdout_to_write = [
        $libvirt_not_created_stdout, $libvirt_not_running_stdout, $libvirt_running_stdout
    ];

    ok(!$vagrant->is_shutdown(), 'vagrant should report the VM as running');
    ok($vagrant->is_shutdown(), 'vagrant should report the shutoff VM as turned off');
    ok($vagrant->is_shutdown(), 'vagrant should report the not created VM as turned off');
};

subtest 'can_handle is a noop' => sub {
    is($vagrant->can_handle(), undef, 'can_handle returns undef');
};

subtest 'stop_serial_grab is a noop' => sub {
    is($vagrant->stop_serial_grab(), undef, 'stop_serial_grab returns undef');
};

subtest 'check_socket calls the base class function' => sub {
    $check_socket_fh_expected = '16';
    $check_socket_write_expected = 42;
    $check_socket_ret = 1;

    is($vagrant->check_socket('16', 42), 1, 'check_socket return value matches');
};

done_testing;
