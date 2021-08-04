#!/usr/bin/perl

use Test::Most;
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
use distribution;
use Net::SSH2;
use testapi qw(get_var get_required_var check_var set_var);
use backend::svirt qw(SERIAL_CONSOLE_DEFAULT_PORT SERIAL_TERMINAL_DEFAULT_DEVICE SERIAL_TERMINAL_DEFAULT_PORT);
use Mojo::File 'tempdir';
use Mojo::Util qw(scope_guard);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

bmwqemu::init_logger;

set_var(WORKER_HOSTNAME => 'foo');
set_var(VIRSH_HOSTNAME  => 'bar');
set_var(VIRSH_PASSWORD  => 'password');

my $distri = $testapi::distri = distribution->new();
my $svirt  = backend::svirt->new();

is_deeply({$svirt->get_ssh_credentials()}, {
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
        console_hotkey  => 'ctrl-alt-f',
        libvirt_domain  => 'openQA-SUT-1',
        serial_port_no  => 1,
        testapi_console => 'sut-serial',
        pty_dev         => SERIAL_TERMINAL_DEFAULT_DEVICE,
}, 'SUT serial console correctly initialized') or diag explain $consoles;

subtest 'XML config for VNC and serial console' => sub {
    $svirt_console->_init_xml();
    $svirt_console->add_vnc({port        => 5901});
    $svirt_console->add_pty({target_port => SERIAL_CONSOLE_DEFAULT_PORT});
    $svirt_console->add_pty({pty_dev     => SERIAL_TERMINAL_DEFAULT_DEVICE, pty_dev_type => 'pty', target_port => SERIAL_TERMINAL_DEFAULT_PORT});

    my $produced_xml = $svirt_console->{domainxml}->toString(2);
    my $expected_xml = "$Bin/22-svirth-virsh-config.xml";

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

subtest 'SSH credentials' => sub {

    set_var('VIRSH_GUEST',          'foo321');
    set_var('VIRSH_GUEST_PASSWORD', 'password321');
    set_var('VIRSH_VMM_FAMILY',     'hyperv');
    my $svirt = backend::svirt->new();

    my %creds = $svirt->get_ssh_credentials();
    is_deeply(\%creds, {hostname => 'bar', password => 'password', username => 'root'}, 'Check SSH credentials');

    %creds = $svirt->get_ssh_credentials('hyperv');
    is_deeply(\%creds, {hostname => 'foo321', password => 'password321', username => 'root'}, 'Check SSH credentials for hyperv');
};

subtest 'SSH usage in console::sshVirtsh' => sub {
    # Check console::sshVirtsh
    my $ssh_creds_svirt    = {hostname => 'hostname_svirt', password => 'password_svirt', username => 'root'};
    my %ssh_expect         = (%$ssh_creds_svirt, wantarray => undef, keep_open => undef);
    my $run_ssh_cmd_return = undef;
    my $mock_baseclass     = Test::MockModule->new('backend::baseclass');
    $mock_baseclass->redefine('run_ssh_cmd' => sub {
            my ($self, $cmd, %args) = @_;
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
        set_var('VMWARE_HOST',      'my_vmware_host');
        set_var('VMWARE_PASSWORD',  'my_vmware_password');
        set_var('VIRSH_VMM_FAMILY', 'vmware');

        my $svirt_vmware_console = consoles::sshVirtsh->new('svirt');
        $svirt_vmware_console->_init_ssh($ssh_creds_svirt);
        $svirt_vmware_console->backend(backend::baseclass->new);

        is($svirt_vmware_console->run_cmd('echo "BLAFAFU"'), 0, "sshVirtsh::run_cmd() Check use of `default` credentials");

        $run_ssh_cmd_return = [undef, 'STDOUT', undef];
        is_deeply($svirt_console->get_cmd_output('echo -n "BLAFAFU"'), 'STDOUT', "sshVirtsh::get_cmd_output() Check use of `default` credentials");

        $ssh_expect{hostname} = 'my_vmware_host';
        $ssh_expect{password} = 'my_vmware_password';
        $run_ssh_cmd_return   = 0;
        is($svirt_vmware_console->run_cmd('echo "BLAFAFU"', domain => 'sshVMwareServer'), 0, "sshVirtsh::run_cmd(domain => sshVMwareServer) check use of VMWARE credentials ");

        $run_ssh_cmd_return = [undef, 'STDOUT', undef];
        is_deeply($svirt_vmware_console->get_cmd_output('echo -n "BLAFAFU"', {domain => 'sshVMwareServer'}), 'STDOUT', "sshVirtsh::get_cmd_output() Check use of VMWARE credentials");
    }
};

subtest 'Method backend::svirt::open_serial_console_via_ssh()' => sub {
    my $module = Test::MockModule->new('backend::baseclass');
    my @LAST_;
    my $test_log_cnt = 0;
    my $grep_return  = 1;
    my @deleted_logs;
    $module->redefine(run_ssh_cmd => sub {
            my $self = shift;
            @LAST_ = @_;
            my $cmd = shift;
            return !!($test_log_cnt > 0 ? --$test_log_cnt : 0) if ($cmd =~ m/^test -e/);
            return $grep_return                                if ($cmd =~ m/^grep -q/);
            push @deleted_logs, ($cmd =~ /(\S+)$/)             if ($cmd =~ / && rm /);
            return (0, "FOOBAR_OUTPUT", '')                    if ($cmd =~ m/^cat /);
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
    $bmwqemu::vars{VMWARE_HOST}      = 'my.vmware.host';
    $run_ssh_expect                  = 'socat - TCP4:my.vmware.host:,crnl;';
    $svirt->open_serial_console_via_ssh('NAME');
    $run_ssh_expect = 'socat - TCP4:my.vmware.host:666,crnl;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'hyperv';
    $bmwqemu::vars{HYPERV_SERVER}    = 'my.hyperv.server';
    $run_ssh_expect                  = 'socat - TCP4:my.hyperv.server:,crnl;';
    $svirt->open_serial_console_via_ssh('NAME');
    $run_ssh_expect = 'socat - TCP4:my.hyperv.server:666,crnl;';
    $svirt->open_serial_console_via_ssh('NAME', port => 666);

    # Disable command check, as we do not care anymore
    $module->redefine(run_ssh => sub { return ('A', 'B') });
    is_deeply([$svirt->open_serial_console_via_ssh('NAME')], ['A', 'B'], 'Check that we get output from run_ssh() call');

    $bmwqemu::vars{JOBTOKEN} = 'CHECK_DELETE_TOKEN';
    my $expected_serial_file = '/tmp/' . $svirt->SERIAL_TERMINAL_LOG_PATH . '.CHECK_DELETE_TOKEN';
    $test_log_cnt = 11;
    dies_ok(sub { $svirt->open_serial_console_via_ssh('NAME') }, "die() when log file wasn't created");
    is(shift @deleted_logs, $expected_serial_file, "Check if $expected_serial_file was deleted on die()");

    $test_log_cnt = 0;
    $grep_return  = 0;
    dies_ok(sub { $svirt->open_serial_console_via_ssh('NAME') }, 'die() when emulate CONSOLE_EXIT token in log file');
    is(shift @deleted_logs, $expected_serial_file, "Check if $expected_serial_file was deleted on die()");
};

sub svirt_xml_validate {
    my ($svirt, %args) = @_;
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
        is(defined($source_node),              1,                  '<disk> has a <source> child');
        is($source_node->getAttribute('file'), $args{source_file}, 'The file attribute of <source> is correct');
    }

    if ($args{driver}) {
        my $driver_node = $target_node->parentNode->findnodes('driver')->shift;
        is(defined($driver_node),               1,                      '<disk> has a <driver> child');
        is($driver_node->getAttribute('name'),  $args{driver}->{name},  'name attribute of <driver> is correct');
        is($driver_node->getAttribute('type'),  $args{driver}->{type},  'type attribute of <driver> is correct');
        is($driver_node->getAttribute('cache'), $args{driver}->{cache}, 'cache attribute of <driver> is correct');
    }
}

subtest 'Method consoles::sshVirtsh::add_disk()' => sub {
    my $ssh_creds_svirt = {hostname => 'hostname_svirt', password => 'password_svirt', username => 'root'};
    my @last_ssh_commands;
    my @last_ssh_args;
    my @ssh_cmd_return;
    my $_10gb = 1024 * 1024 * 1024 * 10;

    my $mock_baseclass = Test::MockModule->new('backend::baseclass');
    $mock_baseclass->redefine('run_ssh_cmd' => sub {
            my ($self, $cmd, %args) = @_;
            push @last_ssh_commands, $cmd;
            push @last_ssh_args,     [%args];

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

        set_var(VMWARE_HOST      => 'my_vmware_host');
        set_var(VMWARE_PASSWORD  => 'my_vmware_password');
        set_var(VIRSH_VMM_FAMILY => 'vmware');
        set_var(VMWARE_DATASTORE => 'my_vmware_datastore');

        my $vmware_openqa_datastore = '/vmfs/volumes/' . get_var('VMWARE_DATASTORE') . '/openQA/';

        my $svirt = consoles::sshVirtsh->new('svirt');
        $svirt->backend(backend::baseclass->new);
        $svirt->_init_ssh($ssh_creds_svirt);
        $svirt->_init_xml();

        subtest 'family vmware only file=>"specified"' => sub {
            my $dev_id          = 'device_id_101';
            my $exp_filename    = $svirt->name . $dev_id . '.vmdk';
            my $file_name_given = "/fo/bar/" . $exp_filename;

            $svirt->add_disk({dev_id => $dev_id, file => $file_name_given});
            is(scalar(@last_ssh_commands), 0, 'None command was triggered');

            svirt_xml_validate($svirt,
                dev         => 'hd' . $dev_id,
                bus         => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $exp_filename
            );
        };

        subtest 'vmware create=1' => sub {
            my $dev_id       = 'device_id_001';
            my $exp_filename = $svirt->name . $dev_id . '.vmdk';
            my $exp_fullpath = $vmware_openqa_datastore . $exp_filename;
            $svirt->add_disk({create => 1, size => '66G', dev_id => $dev_id});
            my $cmd = shift @last_ssh_commands;
            is(defined($cmd), 1, 'Command was triggered');

            like($cmd, qr/vmkfstools -v1 -U $exp_fullpath;/,                       "Check name");
            like($cmd, qr/vmkfstools -v1 -c 66G --diskformat thin $exp_fullpath;/, "Check size");

            svirt_xml_validate($svirt,
                dev         => 'hd' . $dev_id,
                bus         => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $exp_filename
            );
        };

        subtest 'vmware backingfile=1' => sub {
            @last_ssh_commands = ();
            my $dev_id       = 'dev_id_002';
            my $filename     = 'foo_file.vmdk';
            my $exp_filename = 'foo_file_' . $svirt->name . '_thinfile.vmdk';
            set_var(VMWARE_NFS_DATASTORE => 'nfs');
            $svirt->add_disk({backingfile => 1, size => '77G', dev_id => $dev_id, file => $filename});
            like($last_ssh_commands[1], qr/vmkfstools -v1 -i $vmware_openqa_datastore$filename --diskformat thin $vmware_openqa_datastore$exp_filename;/, "Check size");

            svirt_xml_validate($svirt,
                dev         => 'hd' . $dev_id,
                bus         => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $exp_filename
            );
        };

        subtest 'vmware cdrom=1' => sub {
            my $dev_id   = 'dev_id_003';
            my $filename = 'my_cdrom_file_' . $dev_id . '.iso';
            set_var(VMWARE_NFS_DATASTORE => 'nfs_data_store');
            @last_ssh_commands = ();
            $svirt->add_disk({cdrom => 1, dev_id => $dev_id, file => '/my/path/to/this/file/' . $filename});
            like($last_ssh_commands[0], qr%cp\s+/vmfs/volumes/nfs_data_store/iso/$filename\s+$vmware_openqa_datastore\s*;%, "Copy iso to $vmware_openqa_datastore");

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev         => 'hd' . $dev_id,
                bus         => 'ide',
                source_file => '[my_vmware_datastore] openQA/' . $filename
            );
        };

        subtest 'Check differnt size formattings on vmware' => sub {
            foreach my $size (qw(666k 666K 666M 666G 666T)) {
                my $dev_id = "dev_id_004_$size";
                my $name   = $vmware_openqa_datastore . 'openQA-SUT-1' . $dev_id . '\\.vmdk';
                $svirt->add_disk({create => 1, size => $size, dev_id => $dev_id});
                like($last_ssh_commands[-1], qr/vmkfstools -v1 -c $size --diskformat thin $name;/, "Check size $size");
            }
        };
    };

    subtest 'family svirt-xen-hvm' => sub {
        set_var(VIRSH_VMM_FAMILY => 'xen');
        set_var(VIRSH_VMM_TYPE   => 'hvm');
        my $basedir = '/var/lib/libvirt/images/';

        my $svirt = consoles::sshVirtsh->new('svirt');
        $svirt->backend(backend::baseclass->new);
        $svirt->_init_ssh($ssh_creds_svirt);
        $svirt->_init_xml();

        subtest 'family xcirt-xen-hvm only file=>"specified"' => sub {
            my $dev_id          = 'device_id_105';
            my $exp_filename    = $svirt->name . $dev_id . '.iso';
            my $file_name_given = "/fo/bar/" . $exp_filename;

            @last_ssh_commands = ();
            $svirt->add_disk({dev_id => $dev_id, file => $file_name_given});
            is(scalar(@last_ssh_commands), 0, 'None command was triggered');

            svirt_xml_validate($svirt,
                dev         => 'xvd' . $dev_id,
                bus         => 'xen',
                source_file => $basedir . $exp_filename
            );
        };

        subtest 'family svirt-xen-hvm create=1 error handling' => sub {
            @ssh_cmd_return = ([1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock']);

            my $dev_id   = 'dev_id_005';
            my $exp_file = $svirt->name . $dev_id . '.img';
            throws_ok { $svirt->add_disk({create => 1, size => '88G', dev_id => $dev_id}) } qr/Too many attempts to format HDD/, "Died after 5 retry attempts";

            @ssh_cmd_return = ([1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [1, '', 'lock'], [0, '', '']);
            $svirt->add_disk({create => 1, size => '88G', dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 88G -f qcow2", 'Triggered img creation, after 4 errors');

            @ssh_cmd_return = ([0, '', ''], [0, '', ''], [0, '', ''], [0, '', ''], [0, '', '']);

            subtest 'Check different size formattings' => sub {
                foreach my $size (qw(666k 666K 666M 666G 666T)) {
                    $dev_id   = "dev_id_006_$size";
                    $exp_file = $svirt->name . $dev_id . '.img';

                    $svirt->add_disk({create => 1, size => $size, dev_id => $dev_id});
                    is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file $size -f qcow2", "Check different size type $size");
                }
            };

            @ssh_cmd_return = ([0, '', '']);
            $dev_id         = 'dev_id_007_NO_SIZE';
            $exp_file       = $svirt->name . $dev_id . '.img';
            $svirt->add_disk({create => 1, dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 20G -f qcow2", 'Check for default size 20G');
        };

        # Reset xml
        $svirt->_init_xml();

        subtest 'family svirt-xen-hvm create=1' => sub {
            my $dev_id   = 'dev_id_008';
            my $exp_file = $svirt->name . $dev_id . '.img';
            @ssh_cmd_return    = ([0, '', '']);
            @last_ssh_commands = ();
            $svirt->add_disk({create => 1, size => '999G', dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 999G -f qcow2", 'Check create image was triggered');

            svirt_xml_validate($svirt,
                dev         => 'xvd' . $dev_id,
                bus         => 'xen',
                source_file => $basedir . $exp_file,
                driver      => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );
        };

        subtest 'family svirt-xen-hvm backingfile=1' => sub {
            my $dev_id = 'dev_id_009';
            my $file   = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return    = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);

            $svirt->add_disk({
                    backingfile => 1,
                    dev_id      => $dev_id,
                    file        => '/my/path/to/this/file/' . $file,
                    size        => 12
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -b '$basedir/$file' 12G", 'Used image size > backingfile size');
        };

        subtest 'family svirt-xen-hvm backingfile=1 size smaller backingfile-size' => sub {
            my $dev_id = 'dev_id_010';
            my $file   = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return    = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);
            $svirt->add_disk({
                    backingfile => 1,
                    dev_id      => $dev_id,
                    file        => '/my/path/to/this/file/' . $file,
                    size        => 5
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -b '$basedir/$file' $_10gb", 'Used image size <= backingfile size');

            svirt_xml_validate($svirt,
                dev         => 'xvd' . $dev_id,
                bus         => 'xen',
                source_file => $basedir . "openQA-SUT-1$dev_id.img",
                driver      => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );

            throws_ok { $svirt->add_disk({backingfile => 1, dev_id => $dev_id}) } qr/file/, "Die on missing file argument";
        };

        subtest 'family svirt-xen-hvm cdrom=1' => sub {
            my $dev_id = 'dev_id_011';
            my $file   = "my_cdrom_$dev_id.iso";
            @last_ssh_commands = ();
            @ssh_cmd_return    = (0, 0);
            $svirt->add_disk({
                    cdrom  => 1,
                    dev_id => $dev_id,
                    file   => '/my/path/to/this/file/' . $file,
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy cdrom iso');

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev         => 'sd' . $dev_id,
                bus         => 'scsi',
                source_file => $basedir . $file,
                driver      => {name => 'qemu', type => 'raw', cache => undef}
            );

            throws_ok { $svirt->add_disk({cdrom => 1, dev_id => $dev_id}) } qr/file/, "Die on missing file argument";
        };
    };

    subtest 'family kvm' => sub {
        set_var(VIRSH_VMM_FAMILY => 'kvm');
        set_var(VIRSH_VMM_TYPE   => undef);
        my $basedir = '/var/lib/libvirt/images/';

        my $svirt = consoles::sshVirtsh->new('svirt');
        $svirt->backend(backend::baseclass->new);
        $svirt->_init_ssh($ssh_creds_svirt);
        $svirt->_init_xml();

        subtest 'family kvm create=1' => sub {
            my $dev_id   = 'dev_id_012';
            my $exp_file = $svirt->name . $dev_id . ".img";

            @ssh_cmd_return = ([0, '', '']);
            $svirt->add_disk({create => 1, size => '778G', dev_id => $dev_id});

            svirt_xml_validate($svirt,
                dev         => 'vd' . $dev_id,
                bus         => 'virtio',
                source_file => $basedir . $exp_file,
                driver      => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );
        };

        subtest 'family kvm create=1 size types' => sub {
            @ssh_cmd_return = ([0, '', ''], [0, '', ''], [0, '', ''], [0, '', ''], [0, '', ''], [0, '', '']);
            foreach my $size (qw(666k 666K 666M 666G 666T)) {
                my $dev_id   = 'dev_id_013' . $size;
                my $exp_file = $svirt->name . $dev_id . ".img";
                $svirt->add_disk({create => 1, size => $size, dev_id => $dev_id});
                is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file $size -f qcow2", "Check different size type $size");
            }

            my $dev_id   = 'dev_id_014_NO_SIZE';
            my $exp_file = $svirt->name . $dev_id . ".img";
            $svirt->add_disk({create => 1, dev_id => $dev_id});
            is($last_ssh_commands[-1], "qemu-img create $basedir$exp_file 20G -f qcow2", "Default size is 20G");
        };

        subtest 'family svirt-xen-hvm backingfile=1' => sub {
            my $dev_id = 'dev_id_015';
            my $file   = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return    = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);

            $svirt->add_disk({
                    backingfile => 1,
                    dev_id      => $dev_id,
                    file        => '/my/path/to/this/file/' . $file,
                    size        => 12
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -b '$basedir/$file' 12G", 'Used image size > backingfile size');
        };

        subtest 'family kvm backingfile=1 size smaller then backingfile' => sub {
            my $dev_id = 'dev_id_016';
            my $file   = "my_image_$dev_id.img";
            @last_ssh_commands = ();
            @ssh_cmd_return    = (0, [0, '{"virtual-size": ' . $_10gb . ' }', '']);
            $svirt->add_disk({
                    backingfile => 1,
                    dev_id      => $dev_id,
                    file        => '/my/path/to/this/file/' . $file,
                    size        => 5
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy file');
            is($last_ssh_commands[-1], "qemu-img create '${basedir}openQA-SUT-1$dev_id.img' -f qcow2 -b '$basedir/$file' $_10gb", 'Used image size <= backingfile size');

            svirt_xml_validate($svirt,
                dev         => 'vd' . $dev_id,
                bus         => 'virtio',
                source_file => $basedir . "openQA-SUT-1$dev_id.img",
                driver      => {name => 'qemu', type => 'qcow2', cache => 'unsafe'}
            );
        };

        subtest 'family kvm cdrom=1' => sub {
            my $dev_id = 'dev_id_017';
            my $file   = "my_cdrom_$dev_id.iso";
            @last_ssh_commands = ();
            @ssh_cmd_return    = (0, 0);
            $svirt->add_disk({
                    cdrom  => 1,
                    dev_id => $dev_id,
                    file   => '/my/path/to/this/file/' . $file,
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy cdrom iso');

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev         => 'hd' . $dev_id,
                bus         => 'ide',
                source_file => $basedir . $file,
                driver      => {name => 'qemu', type => 'raw', cache => undef}
            );
        };

        subtest 'family kvm cdrom=1 xz file' => sub {
            my $dev_id     = 'dev_id_018';
            my $file_wo_xz = "my_compressed_cdrom_$dev_id.iso";
            my $file       = $file_wo_xz . '.xz';
            @last_ssh_commands = ();
            @ssh_cmd_return    = (0, 0);
            $svirt->add_disk({
                    cdrom  => 1,
                    dev_id => $dev_id,
                    file   => '/my/path/to/this/file/' . $file,
            });
            like($last_ssh_commands[0], qr%^rsync.*/my/path/to/this/file/$file.*$basedir/$file%, 'Use rsync to copy cdrom iso');
            like($last_ssh_commands[1], qr%unxz%,                                                'Uncompress file with unxz');

            svirt_xml_validate($svirt,
                disk_device => 'cdrom',
                dev         => 'hd' . $dev_id,
                bus         => 'ide',
                source_file => $basedir . $file_wo_xz,
                driver      => {name => 'qemu', type => 'raw', cache => undef}
            );
        };

        subtest 'check bootorder argument' => sub {
            my $dev_id = 'dev_id_019';
            $svirt->add_disk({
                    cdrom     => 1,
                    dev_id    => $dev_id,
                    file      => '/my/path/to/this/file/foo_file.iso',
                    bootorder => 'MyArbitraryBootOrderArgument'
            });
            my $target_nodelist = $svirt->{domainxml}->findnodes('domain/devices/disk[@type="file" and @device="cdrom"]/boot[@order="MyArbitraryBootOrderArgument"]');
            is($target_nodelist->size(), 1, 'Boot order entry was created in <disk device="cdrom">');

            $dev_id = 'dev_id_020';
            $svirt->add_disk({
                    dev_id    => $dev_id,
                    file      => '/my/path/to/this/file/foo_file2.iso',
                    bootorder => 'MyArbitraryBootOrderArgumentXXX'
            });
            $target_nodelist = $svirt->{domainxml}->findnodes('domain/devices/disk[@type="file" and @device="disk"]/boot[@order="MyArbitraryBootOrderArgumentXXX"]');
            is($target_nodelist->size(), 1, 'Boot order entry was created in <disk device="disk">');

        }
    };
};
done_testing;
