# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::qemu;
use Mojo::Base 'backend::virt', -signatures;
use autodie ':all';
use File::Basename 'dirname';
use File::Path 'mkpath';
use File::Which;
use Time::HiRes qw(sleep gettimeofday);
use Time::Seconds;
use IO::Socket::UNIX 'SOCK_STREAM';
use IO::Handle;
use POSIX qw(strftime :sys_wait_h mkfifo);
use Mojo::File 'path';
use Mojo::JSON;
use Carp;
use Fcntl;
use Net::DBus;
use bmwqemu qw(diag);
require IPC::System::Simple;
use osutils qw(find_bin qv run_diag runcmd);
use List::Util qw(first max);
use Data::Dumper;
use Mojo::IOLoop::ReadWriteProcess::Session 'session';
use OpenQA::Qemu::Proc;
use Socket;

# The maximum value of the system's native signed integer. Which will probably
# be 2^64 - 1.
use constant LONG_MAX => (~0 >> 1);

# Folder where RAM/VM state files live. Note that the blockdevice snapshots go
# in a separate dir.
use constant VM_SNAPSHOTS_DIR => 'vm-snapshots';

sub new ($class) {
    my $self = $class->SUPER::new;
    $self->{pidfilename} = 'qemu.pid';
    $self->{proc} = OpenQA::Qemu::Proc->new();
    $self->{proc}->_process->pidfile($self->{pidfilename});
    return $self;
}

# baseclass virt method overwrite

sub _wrap_hmc ($cmdline) { {
        execute => 'human-monitor-command',
        arguments => {'command-line' => $cmdline}}
}

# poo#66667: Since qemu 4.2, -audiodev is required to record sounds, as we need an audiodev id for 'wavcapture'
sub requires_audiodev ($self) {
    return (version->declare($self->{qemu_version}) ge version->declare(4.2));
}

sub start_audiocapture ($self, $args) {

    # poo#66667: an audiodev id is required by wavcapture when audiodev is used
    my $audiodev_id = $self->requires_audiodev ? 'snd0' : '';
    $self->handle_qmp_command(_wrap_hmc("wavcapture $args->{filename} $audiodev_id 44100 16 1"));
}

sub stop_audiocapture ($self, $args) {
    $self->handle_qmp_command(_wrap_hmc("stopcapture 0"));
}

# parameters: acpi, reset, (on), off
sub power ($self, $args) {
    my %action_to_cmd = (
        acpi => 'system_powerdown',
        reset => 'system_reset',
        off => 'quit',
    );
    $self->handle_qmp_command({execute => $action_to_cmd{$args->{action}}});
}

sub eject_cd ($self, $args = {}) {
    die "'device' parameter is not supported anymore, use 'id'" if defined $args->{device};
    my $id = $args->{id} // 'cd0-device';
    $self->handle_qmp_command({execute => 'eject', arguments => {
                id => $id,
                force => (!defined $args->{force} || $args->{force} ? Mojo::JSON->true : Mojo::JSON->false)
    }});
    $self->handle_qmp_command({execute => 'blockdev-remove-medium', arguments => {id => $id}});
}

sub execute_qmp_command ($self, $args) { $self->handle_qmp_command($args->{query}) }

sub cpu_stat ($self) {
    my $stat = path("/proc/" . $self->{proc}->_process->pid . "/stat")->slurp;
    my @a = split(" ", $stat);
    return [@a[13, 14]];
}

sub do_start_vm ($self, @) {
    $self->start_qemu();
    return {};
}

sub stop_qemu ($self) {
    $self->{proc}->stop_qemu;
    delete_virtio_console_fifo();
    $self->_stop_children_processes;
}

sub _dbus_do_call ($self, $fn, @args) {
    # we intentionally do not persist the dbus connection to avoid
    # queueing up signals we are not interested in handling:
    # https://progress.opensuse.org/issues/90872
    my $bus = Net::DBus->system(private => 1);
    my $bus_service = $bus->get_service("org.opensuse.os_autoinst.switch");
    my $bus_object = $bus_service->get_object("/switch", "org.opensuse.os_autoinst.switch");
    my @result = $bus_object->$fn(@args);
    $bus->get_connection->disconnect;
    return @result;
}

sub _dbus_call ($self, $fn, @args) {
    my ($rt, $message);
    eval {
        # do not die on unconfigured service
        local $SIG{__DIE__};
        ($rt, $message) = $self->_dbus_do_call($fn, @args);
        chomp $message;
        die $message unless $rt == 0;
    };
    my $error = $@;
    if ($error) {
        my $msg = "Open vSwitch command '$fn' with arguments '@args' failed: $error";
        die "$msg\n" unless $bmwqemu::vars{QEMU_NON_FATAL_DBUS_CALL};
        bmwqemu::diag $msg;
    }
    return ($rt, $message, ($error) x !!($error));
}

sub do_stop_vm ($self, @) {

    my $proc = $self->{proc};
    if ($bmwqemu::vars{QEMU_WAIT_FINISH}) {
        # wait until QEMU finishes on its own; used in t/18-qemu-options.t
        if (my $qemu_pid = $proc->qemu_pid) {
            waitpid $qemu_pid, 0;
        }
    }
    $proc->save_state;
    $self->stop_qemu;
}

sub can_handle ($self, $args) {
    my $vars = \%bmwqemu::vars;

    return unless $args->{function} eq 'snapshots';
    return if $vars->{QEMU_DISABLE_SNAPSHOTS};
    my @models = ($vars->{HDDMODEL}, map { $vars->{"HDDMODEL_$_"} } (1 .. $vars->{NUMDISKS}));
    my $nvme = first { ($_ // '') eq 'nvme' } @models;
    return {ret => 1} unless $nvme;
    bmwqemu::fctwarn('NVMe drives can not be migrated which is required for snapshotting')
      unless $args->{no_warn};
    return undef;
}

sub open_file_and_send_fd_to_qemu ($self, $path, $fdname) {

    mkpath(dirname($path));
    my $fd = POSIX::open($path, POSIX::O_CREAT() | POSIX::O_RDWR()) or die "Failed to open $path: $!";
    my $rsp = $self->handle_qmp_command(
        {execute => 'getfd', arguments => {fdname => $fdname}},
        send_fd => $fd,
        fatal => 1
    );
    POSIX::close($fd);
}

sub set_migrate_capability ($self, $name, $state) {

    $self->handle_qmp_command(
        {
            execute => 'migrate-set-capabilities',
            arguments => {
                capabilities => [
                    {
                        capability => $name,
                        state => $state ? Mojo::JSON::true : Mojo::JSON::false,
                    }]}
        },
        fatal => 1
    );
}

sub _wait_while_status_is ($self, $status, $timeout, $fail_msg) {

    my $rsp = $self->handle_qmp_command({execute => 'query-status'}, fatal => 1);
    my $i = 0;
    while (($rsp->{return}->{status} // '') =~ $status) {
        $i += 1;
        die "$fail_msg; QEMU status is $rsp->{return}->{status}" if $i > $timeout;
        sleep(1);
        $rsp = $self->handle_qmp_command({execute => 'query-status'}, fatal => 1);
    }
}

sub _wait_for_migrate ($self) {
    my $migration_starttime = gettimeofday;
    my $execution_time = gettimeofday;
    # We need to wait for qemu, since it will not honor timeouts
    # 240 seconds should be ok for 4GB
    my $max_execution_time = $bmwqemu::vars{QEMU_MAX_MIGRATION_TIME} // 240;
    my $rsp;

    do {
        # We want to wait a decent amount of time, a file of 1GB will be
        # migrated in about 40secs with an ssd drive. and no heavy load.
        sleep 0.5;

        $execution_time = gettimeofday - $migration_starttime;
        $rsp = $self->handle_qmp_command({execute => 'query-migrate'}, fatal => 1);
        die 'Migrate to file failed' if $rsp->{return}->{status} eq 'failed';

        log::diag "Migrating total bytes:     \t" . $rsp->{return}->{ram}->{total};
        log::diag "Migrating remaining bytes:   \t" . $rsp->{return}->{ram}->{remaining};

        if ($execution_time > $max_execution_time) {
            # migrate_cancel returns an empty hash, so there is no need to check.
            $rsp = $self->handle_qmp_command({execute => 'migrate_cancel'});
            die "Migrate to file failed, it has been running for more than $max_execution_time seconds";
        }

    } until ($rsp->{return}->{status} eq 'completed');

    # Avoid race condition where QEMU allows us to start the VM (set state to
    # running) then tries to transition to post-migarte which fails
    $self->_wait_while_status_is(qr/paused|finish-migrate/,
        $max_execution_time - $execution_time,
        'Timed out waiting for migration to finalize');
}

sub _migrate_to_file ($self, %args) {
    my $fdname = 'dumpfd';
    my $compress_level = $args{compress_level} || 0;
    my $compress_threads = $args{compress_threads} // 2;
    my $filename = $args{filename};
    my $max_bandwidth = $args{max_bandwidth} // LONG_MAX;

    # Internally compressed dumps can't be opened by crash. They need to be
    # fed back into QEMU as an incoming migration.
    $self->set_migrate_capability('compress', 1) if $compress_level > 0;
    $self->set_migrate_capability('events', 1);

    $self->handle_qmp_command(
        {
            execute => 'migrate-set-parameters',
            arguments => {
                # This is ignored if the compress capability is not set
                'compress-level' => $compress_level + 0,
                'compress-threads' => $compress_threads + 0,
                # Ensure slow dump times are not due to a transfer rate cap
                'max-bandwidth' => $max_bandwidth + 0,
            }
        },
        fatal => 1
    );

    $self->open_file_and_send_fd_to_qemu($filename, $fdname);

    # QEMU will freeze the VM when the RAM migration reaches a low water
    # mark. However it is easier for QEMU if the VM is already frozen.
    $self->freeze_vm();
    # migrate consumes the file descriptor, so we do not need to call closefd
    $self->handle_qmp_command(
        {
            execute => 'migrate',
            arguments => {uri => "fd:$fdname"}
        },
        fatal => 1
    );

    return $self->_wait_for_migrate();
}

sub switch_network ($self, $args) {
    $self->handle_qmp_command({execute => 'set_link', arguments => {
                name => $args->{network_link_name} // "qanet0",
                up => (!defined $args->{network_enabled} || $args->{network_enabled} ? Mojo::JSON->true : Mojo::JSON->false)
    }}, fatal => 1);
}

sub save_memory_dump ($self, $args) {
    my $fdname = 'dumpfd';
    my $vars = \%bmwqemu::vars;
    my $compress_method = $vars->{QEMU_DUMP_COMPRESS_METHOD} || 'xz';
    my $compress_level = $vars->{QEMU_COMPRESS_LEVEL} || 6;
    my $compress_threads = $vars->{QEMU_COMPRESS_THREADS} || $vars->{QEMUCPUS} || 2;
    my $filename = $args->{filename} . '-vm-memory-dump';

    my $rsp = $self->handle_qmp_command({execute => 'query-status'}, fatal => 1);
    bmwqemu::diag("Migrating the machine (Current VM state is $rsp->{return}->{status})");
    my $was_running = $rsp->{return}->{status} eq 'running';

    mkpath('ulogs');
    $self->_migrate_to_file(compress_level => $compress_method eq 'internal' ? $compress_level : 0,
        compress_threads => $compress_threads,
        filename => "ulogs/$filename",
        max_bandwidth => $vars->{QEMU_MAX_BANDWIDTH});

    diag 'Memory dump completed';

    $self->cont_vm() if $was_running;

    return undef unless $compress_method;
    if ($compress_method eq 'xz') {
        if (defined File::Which::which('xz')) {
            runcmd('xz', '--no-warn', '-T', $compress_threads, "-v$compress_level", "ulogs/$filename");
        }
        else {
            bmwqemu::fctwarn('xz not found; falling back to bzip2');
            $compress_method = 'bzip2';
        }
    }
    if ($compress_method eq 'bzip2') {
        runcmd('bzip2', "-v$compress_level", "ulogs/$filename");
    }
}

sub inflate_balloon ($self) {
    my $vars = \%bmwqemu::vars;
    return unless $vars->{QEMU_BALLOON_TARGET};
    my $target_bytes = $vars->{QEMU_BALLOON_TARGET} * 1048576;
    $self->handle_qmp_command({execute => 'balloon', arguments => {value => $target_bytes}}, fatal => 1);
    my $rsp = $self->handle_qmp_command({execute => 'query-balloon'}, fatal => 1);
    my $prev_actual = $rsp->{return}->{actual};
    my $i = 0;
    my $timeout = $vars->{QEMU_BALLOON_TIMEOUT} // 5;
    while ($i < $timeout) {
        $i += 1;
        sleep(1);
        $rsp = $self->handle_qmp_command({execute => 'query-balloon'}, fatal => 1);
        last if $prev_actual <= $rsp->{return}->{actual};
    }
}

sub deflate_balloon ($self) {
    my $vars = \%bmwqemu::vars;
    return unless $vars->{QEMU_BALLOON_TARGET};
    my $ram_bytes = $vars->{QEMURAM} * 1048576;
    $self->handle_qmp_command({execute => 'balloon', arguments => {value => $ram_bytes}}, fatal => 1);
}

sub save_storage ($self, $args) {
    my $vars = \%bmwqemu::vars;
    my $bdc = $self->{proc}->blockdev_conf;
    my $fname = $args->{filename};
    my $rsp = $self->handle_qmp_command({execute => 'query-status'}, fatal => 1);
    bmwqemu::diag("Saving storage devices (current VM state is $rsp->{return}->{status})");
    my $was_running = $rsp->{return}->{status} eq 'running';
    if ($was_running) {
        $self->inflate_balloon();
        $self->freeze_vm();
    }
    mkpath("assets_public");
    $bdc->for_each_drive(sub ($drive) {
            my $size = $drive->{drive}->{size};
            my $id = "$drive->{id}-backup-$fname";
            my $node = $drive->{drive}->{node_name};
            # no need to save CDs
            return if ($node =~ qr/cd[0-9]-overlay/);
            my $my_node = "$node-$fname";
            my $bck_file = "assets_public/$my_node-$vars->{NAME}.qcow2";
            # create disk
            runcmd('qemu-img', 'create', '-f', 'qcow2', "$bck_file", $size);
            my $req = {execute => 'blockdev-add',
                arguments => {driver => 'qcow2', 'node-name' => $my_node,
                    file => {driver => 'file', filename => $bck_file}
                }};
            $self->handle_qmp_command($req, fatal => 1);
            $req = {execute => 'blockdev-backup',
                arguments => {device => $node, target => $my_node,
                    sync => 'full', 'job-id' => $id}};
            $self->handle_qmp_command($req, fatal => 1);
            my $return;
            my $timeout = $vars->{SAVE_STORAGE_TIMEOUT} // (ONE_MINUTE * 15);
            # wait for background job to finish before we continue
            do {
                die "Saving volume $node exceeded the timeout" if $timeout == 0;
                my $query = {execute => 'query-jobs'};
                $return = $self->handle_qmp_command($query, fatal => 1)->{return};
                sleep 1;
                --$timeout;
            } while (@$return);
    });
    bmwqemu::diag("Saving storage complete");
    if ($was_running) {
        $self->cont_vm();
        $self->deflate_balloon();
    }
}

sub save_snapshot ($self, $args) {
    my $vars = \%bmwqemu::vars;
    my $vmname = $args->{name};
    my $bdc = $self->{proc}->blockdev_conf;

    my $rsp = $self->handle_qmp_command({execute => 'query-status'}, fatal => 1);
    bmwqemu::diag("Saving snapshot (Current VM state is $rsp->{return}->{status})");
    my $was_running = $rsp->{return}->{status} eq 'running';
    if ($was_running) {
        $self->inflate_balloon();
        $self->freeze_vm();
    }

    $self->save_console_snapshots($vmname);

    my $snapshot = $self->{proc}->snapshot_conf->add_snapshot($vmname);
    $bdc->for_each_drive(sub {
            local $Data::Dumper::Indent = 0;
            local $Data::Dumper::Terse = 1;
            local $Data::Dumper::Sortkeys = 1;
            my $drive = shift;

            my $overlay = $bdc->add_snapshot_to_drive($drive, $snapshot);
            my $req = {execute => 'blockdev-snapshot-sync',
                arguments => {'node-name' => $overlay->backing_file->node_name,
                    'snapshot-node-name' => $overlay->node_name,
                    'snapshot-file' => $overlay->file,
                    format => $overlay->driver}};
            $rsp = $self->handle_qmp_command($req);

            # Assumes errors are caused by pflash drives using an autogenerated
            # blockdev node-name. Try again using the device id instead.
            if ($rsp->{error}) {
                diag('blockdev-snapshot-sync(' . Dumper($req) . ') -> ' . Dumper($rsp));
                delete($req->{arguments}->{'node-name'});
                $req->{arguments}->{device} = $overlay->backing_file->node_name;
                $rsp = $self->handle_qmp_command($req);
            }

            diag('blockdev-snapshot-sync(' . Dumper($req) . ') -> ' . Dumper($rsp));
    });

    $self->_migrate_to_file(
        filename => path(VM_SNAPSHOTS_DIR, $snapshot->name),
        compress_level => $vars->{QEMU_COMPRESS_LEVEL} || 6,
        compress_threads => $vars->{QEMU_COMPRESS_THREADS} // $vars->{QEMUCPUS},
        max_bandwidth => $vars->{QEMU_MAX_BANDWIDTH});
    diag('Snapshot complete');

    if ($was_running) {
        $self->cont_vm();
        $self->deflate_balloon();
    }
    return;
}

sub load_snapshot ($self, $args) {
    my $vmname = $args->{name};

    my $rsp = $self->handle_qmp_command({execute => 'query-status'}, fatal => 1);
    bmwqemu::diag("Loading snapshot (Current VM state is $rsp->{return}->{status})");
    my $was_running = $rsp->{return}->{status} eq 'running';
    $self->freeze_vm() if $was_running;

    $self->disable_consoles();

    # NOTE: This still needs to be handled better
    # Between restarts we do not rewire network switches
    $self->{stop_only_qemu} = 1;
    $self->close_pipes();
    $self->{stop_only_qemu} = 0;

    my $snapshot = $self->{proc}->revert_to_snapshot($vmname);

    create_virtio_console_fifo();
    my $qemu_pipe = $self->{qemupipe} = $self->{proc}->exec_qemu();
    $self->{qmpsocket} = $self->{proc}->connect_qmp();
    my $init = myjsonrpc::read_json($self->{qmpsocket});
    my $hash = $self->handle_qmp_command({execute => 'qmp_capabilities'});
    $self->{select_read}->add($qemu_pipe, 'qemu::load_snapshot::qemu_pipe');
    $self->{select_write}->add($qemu_pipe, 'qemu::load_snapshot::qemu_pipe');

    # Ideally we want to send a file descriptor to QEMU, but it doesn't seem
    # to work for incoming migrations, so we are forced to use exec:cat instead.
    #
    # my $fdname = 'incoming';
    # $self->open_file_and_send_fd_to_qemu(VM_SNAPSHOTS_DIR . '/' . $snapshot->name,
    #                                     $fdname);
    $self->set_migrate_capability('compress', 1);
    $self->set_migrate_capability('events', 1);
    $rsp = $self->handle_qmp_command({execute => 'migrate-incoming',
            arguments => {uri => 'exec:cat ' . VM_SNAPSHOTS_DIR . '/' . $snapshot->name}},
        #arguments => { uri => "fd:$fdname" }},
        fatal => 1);

    $self->load_console_snapshots($vmname);

    # query-migrate does not seem to work for an incoming migration
    $self->_wait_while_status_is(qr/migrate/, 300, 'Timed out while loading snapshot');

    $self->reenable_consoles();
    $self->select_console({testapi_console => 'sut'});
    diag('Restored snapshot');
    $self->cont_vm();
    $self->deflate_balloon();
}

sub do_extract_assets ($self, $args) {
    my $name = $args->{name};
    my $img_dir = $args->{dir};
    my $hdd_num = ($args->{hdd_num} // 0) - 1;
    my $pattern = $args->{pflash_vars} ? qr/^pflash-vars$/ : qr/^hd$hdd_num$/;
    $self->{proc}->load_state() unless $self->{proc}->has_state();
    mkpath($img_dir);
    bmwqemu::fctinfo("Extracting $pattern");
    my $qemu_compress_qcow = $bmwqemu::vars{QEMU_COMPRESS_QCOW2} // 1;
    my $res = $self->{proc}->export_blockdev_images($pattern, $img_dir, $name, $qemu_compress_qcow);
    die "Expected one drive to be exported, not $res" if $res != 1;
}

# baseclass virt method overwrite end

sub find_ovmf () { first { -e } @bmwqemu::ovmf_locations }

sub virtio_console_names () {
    return () unless $bmwqemu::vars{VIRTIO_CONSOLE};
    return (
        'virtio_console', 'virtio_console_user',
        map { 'virtio_console' . $_ } (1 .. ($bmwqemu::vars{VIRTIO_CONSOLE_NUM} // 1) - 1),
    );
}

sub virtio_console_fifo_names () { map { $_ . '.in', $_ . '.out' } virtio_console_names }

sub console_fifo ($name) {
    return bmwqemu::fctwarn("Fifo pipe '$name' already exists!") if -e $name;
    mkfifo($name, 0666) or bmwqemu::fctwarn("Failed to create pipe $name: $!");
}

sub create_virtio_console_fifo () { console_fifo($_) for virtio_console_fifo_names }

sub delete_virtio_console_fifo () { unlink $_ or bmwqemu::fctwarn("Could not unlink $_ $!") for grep { -e } virtio_console_fifo_names }

sub qemu_params_ofw ($self) {
    my $vars = \%bmwqemu::vars;
    $vars->{QEMUMACHINE} //= "usb=off";
    # set the initial resolution on PCC and SPARC
    sp('g', "$self->{xres}x$self->{yres}");
    # newer qemu needs safe cache capability level quirk settings
    # https://progress.opensuse.org/issues/75259
    my $caps = ',cap-cfpc=broken,cap-sbbc=broken,cap-ibs=broken';
    $vars->{QEMUMACHINE} .= $caps if $vars->{QEMUMACHINE} !~ /$caps/;
    $caps = ',cap-ccf-assist=off';
    $vars->{QEMUMACHINE} .= $caps if $self->{qemu_version} >= version->declare(5) && $vars->{QEMUMACHINE} !~ /$caps/;
    return 1;
}

sub setup_tpm ($self, $arch) {
    my $vars = \%bmwqemu::vars;
    return unless ($vars->{QEMUTPM});
    my $tpmn = $vars->{QEMUTPM} eq 'instance' ? $vars->{WORKER_INSTANCE} : $vars->{QEMUTPM};
    my $vmpath = ($vars->{QEMUTPM_PATH_PREFIX} // '/tmp/mytpm') . $tpmn;
    mkdir $vmpath unless -d $vmpath;
    my $vmsock = "$vmpath/swtpm-sock";
    unless (-e $vmsock) {
        # Before create swtpm-sock, we should make sure there is no tpm*.permall file
        # When tpm version is 2.0, the file is tpm2-00.permall.
        # When tpm version is 1.x, the file is tpm-00.permall.
        # See: https://progress.opensuse.org/issues/107155
        unlink glob "$vmpath/tpm*.permall";

        my @args = ('swtpm', 'socket', '--tpmstate', "dir=$vmpath", '--ctrl', "type=unixio,path=$vmsock", '--log', 'level=20', '-d');
        push @args, '--tpm2' if (($vars->{QEMUTPM_VER} // '2.0') == '2.0');
        runcmd(@args);
    }
    sp('chardev', "socket,id=chrtpm,path=$vmsock");
    sp('tpmdev', 'emulator,id=tpm0,chardev=chrtpm');
    if ($arch eq 'aarch64') {
        sp('device', 'tpm-tis-device,tpmdev=tpm0');
    }
    elsif ($arch eq 'ppc64le') {
        sp('device', 'tpm-spapr,tpmdev=tpm0');
        sp('device', 'spapr-vscsi,id=scsi9,reg=0x00002000');
    }
    else {
        # x86_64
        sp('device', 'tpm-tis,tpmdev=tpm0');
    }
}

sub _set_graphics_backend ($self, $is_arm) {
    my $vars = \%bmwqemu::vars;
    my $device = "VGA";
    my $options = "";
    if ($vars->{QEMU_OVERRIDE_VIDEO_DEVICE_AARCH64}) {
        bmwqemu::fctwarn("QEMU_OVERRIDE_VIDEO_DEVICE_AARCH64 is deprecated, please set QEMU_VIDEO_DEVICE=VGA instead");
    }
    else {
        # annoying pre-existing special-case default for ARM
        $device = "virtio-gpu-pci" if ($is_arm);
    }
    if ($vars->{QEMU_VIDEO_DEVICE}) {
        bmwqemu::fctwarn("Both QEMUVGA and QEMU_VIDEO_DEVICE set, ignoring deprecated QEMUVGA!") if $vars->{QEMUVGA};
        $device = $vars->{QEMU_VIDEO_DEVICE};
    }
    elsif ($vars->{QEMUVGA}) {
        my $vga = $vars->{QEMUVGA};
        bmwqemu::fctwarn("QEMUVGA is deprecated, please set QEMU_VIDEO_DEVICE");
        $device = "virtio-vga" if ($vga eq "virtio");
        $device = "qxl-vga" if ($vga eq "qxl");
        $device = "cirrus-vga" if ($vga eq "cirrus");
        $device = "VGA" if ($vga eq "std");
    }
    my @edids = ("VGA", "virtio-vga", "virtio-gpu-pci", "bochs-display", "virtio-gpu");
    if (grep { $device eq $_ } @edids) {
        # these devices support EDID
        $options = ",edid=on,xres=$self->{xres},yres=$self->{yres}";
    }
    if ($vars->{QEMU_VIDEO_DEVICE_OPTIONS}) {
        $options .= "," . $vars->{QEMU_VIDEO_DEVICE_OPTIONS};
    }
    sp('device', "${device}${options}");
}

sub start_qemu ($self) {
    my $vars = \%bmwqemu::vars;

    my $basedir = path('raid')->to_abs;
    my $qemubin = $ENV{QEMU};

    my $qemuimg = find_bin('/usr/bin/', qw(kvm-img qemu-img));

    local *sp = sub (@args) { $self->{proc}->static_param(@args); };
    $vars->{VIRTIO_CONSOLE} = 1 if ($vars->{VIRTIO_CONSOLE} // '') ne 0;

    unless ($qemubin) {
        if ($vars->{QEMU}) {
            $qemubin = find_bin('/usr/bin/', 'qemu-system-' . $vars->{QEMU});
        }
        else {
            (my $class = $vars->{WORKER_CLASS} || '') =~ s/qemu_/qemu-system\-/g;
            my @execs = qw(kvm qemu-kvm qemu qemu-system-x86_64 qemu-system-ppc64 qemu-system-aarch64);
            my %allowed = map { $_ => 1 } @execs;
            for (split(/\s*,\s*/, $class)) {
                if ($allowed{$_}) {
                    $qemubin = find_bin('/usr/bin/', $_);
                    last;
                }
            }
            $qemubin ||= find_bin('/usr/bin/', @execs) // find_bin('/usr/libexec/', @execs);
        }
    }

    die "no kvm-img/qemu-img found\n" unless $qemuimg;
    die "no Qemu/KVM found\n" unless $qemubin;

    $self->{proc}->qemu_bin($qemubin);
    $self->{proc}->qemu_img_bin($qemuimg);

    # Get qemu version
    my $qemu_version = qx{$qemubin -version};
    $qemu_version =~ /([0-9]+([.][0-9]+)+)/;
    $qemu_version = $1;
    $self->{qemu_version} = $qemu_version;
    bmwqemu::diag "qemu version detected: $self->{qemu_version}";

    $vars->{BIOS} //= $vars->{UEFI_BIOS} if ($vars->{UEFI});    # XXX: compat with old deployment
    $vars->{UEFI} = 1 if $vars->{UEFI_PFLASH};


    if ($vars->{UEFI_PFLASH} && (($vars->{ARCH} // '') eq 'x86_64')) {
        $vars->{BIOS} //= find_ovmf =~ s/-code//r;
    }
    elsif ($vars->{UEFI} && (($vars->{ARCH} // '') eq 'x86_64')) {
        $vars->{UEFI_PFLASH_CODE} //= find_ovmf;
        $vars->{UEFI_PFLASH_VARS} //= $vars->{UEFI_PFLASH_CODE} =~ s/code/$&=~tr,CcOoDdEe,VvAaRrSs,r/eir;
        die "No UEFI firmware can be found! Please specify UEFI_PFLASH_CODE/UEFI_PFLASH_VARS or BIOS or UEFI_BIOS or install an appropriate package" unless $vars->{UEFI_PFLASH_CODE};
    }
    if ($vars->{UEFI_PFLASH} || $vars->{BIOS}) {
        bmwqemu::fctinfo('UEFI_PFLASH and BIOS are deprecated. It is recommended to use UEFI_PFLASH_CODE and UEFI_PFLASH_VARS instead. These variables can be auto-discovered, try to just remove UEFI_PFLASH.');
    }

    foreach my $attribute (qw(BIOS KERNEL INITRD)) {
        if ($vars->{$attribute} && $vars->{$attribute} !~ /^\//) {
            # Non-absolute paths are assumed relative to /usr/share/qemu
            $vars->{$attribute} = '/usr/share/qemu/' . $vars->{$attribute};
        }
        if ($vars->{$attribute} && !-e $vars->{$attribute}) {
            die "'$vars->{$attribute}' missing, check $attribute\n";
        }
    }

    if ($vars->{LAPTOP}) {
        if ($vars->{LAPTOP} =~ /\/|\.\./) {
            die "invalid characters in LAPTOP\n";
        }
        $vars->{LAPTOP} = 'hp_elitebook_820g1' if $vars->{LAPTOP} eq '1';
        die "no dmi data for '$vars->{LAPTOP}'\n" unless -d "$bmwqemu::scriptdir/dmidata/$vars->{LAPTOP}";
    }

    my $bootfrom = '';    # branch by "disk" or "cdrom", not "c" or "d"
    if ($vars->{BOOT_HDD_IMAGE}) {
        # skip dvd boot menu and boot directly from hdd
        $vars->{BOOTFROM} //= 'c';
    }
    if (my $bootfrom_var = $vars->{BOOTFROM}) {
        if ($bootfrom_var eq 'd' || $bootfrom_var eq 'cdrom') {
            $bootfrom = 'cdrom';
            $vars->{BOOTFROM} = 'd';
        }
        elsif ($bootfrom_var eq 'c' || $bootfrom_var eq 'disk') {
            $bootfrom = 'disk';
            $vars->{BOOTFROM} = 'c';
        }
        elsif ($bootfrom_var eq 'n' || $bootfrom_var eq 'net') {
            $bootfrom = 'net';
            $vars->{BOOTFROM} = 'n';
        }
        else {
            die "unknown/unsupported boot order: $bootfrom_var";
        }
    }

    # disk settings
    if ($vars->{MULTIPATH}) {
        $vars->{HDDMODEL} ||= "scsi-hd";
        $vars->{PATHCNT} ||= 2;
    }
    $vars->{NUMDISKS} //= defined($vars->{RAIDLEVEL}) ? 4 : 1;
    $vars->{HDDSIZEGB} ||= 10;
    $vars->{CDMODEL} ||= "scsi-cd";
    $vars->{HDDMODEL} ||= "virtio-blk";

    # network settings
    $vars->{NICMODEL} ||= "virtio-net";
    $vars->{NICTYPE} ||= "user";
    $vars->{NICMAC} ||= "52:54:00:12:34:56" if $vars->{NICTYPE} eq 'user';
    if ($vars->{NICTYPE} eq "vde") {
        $vars->{VDE_SOCKETDIR} ||= '.';
        # use consistent port. port 1 is slirpvde so add + 2.
        # *2 to have another slot for slirpvde. Default number
        # of ports is 32 so enough for 14 workers per host.
        $vars->{VDE_PORT} ||= ($vars->{WORKER_ID} // 0) * 2 + 2;
    }

    # arch discovery
    my $arch = $vars->{ARCH} // '';
    $arch = 'arm' if ($arch =~ /armv6|armv7/);
    my $is_arm = $arch eq 'aarch64' || $arch eq 'arm';
    my $is_ppc = $arch =~ /ppc/;
    my $is_riscv = $arch eq 'riscv64';
    my $is_s390x = $arch eq 's390x';
    my $is_x86 = $arch eq 'i586' || $arch eq 'x86_64';

    $self->_set_graphics_backend($is_arm);

    # misc
    my $arch_supports_boot_order = $vars->{UEFI} ? 0 : 1;    # UEFI/OVMF supports ",bootindex=N", but not "-boot order=X"
    my $use_usb_kbd;
    my $use_virtio_kbd;

    if ($is_arm || $is_riscv) {
        $arch_supports_boot_order = 0;
        $use_usb_kbd = 1;
    }
    elsif ($is_s390x) {
        $arch_supports_boot_order = 0;
        $use_virtio_kbd = 1;
    }
    elsif ($vars->{OFW}) {
        $use_usb_kbd = $self->qemu_params_ofw;
    }

    my @nicmac;
    my @nicvlan;
    my @tapdev;
    my @tapscript;
    my @tapdownscript;

    @nicmac = split /\s*,\s*/, $vars->{NICMAC} if $vars->{NICMAC};
    @nicvlan = split /\s*,\s*/, $vars->{NICVLAN} if $vars->{NICVLAN};
    @tapdev = split /\s*,\s*/, $vars->{TAPDEV} if $vars->{TAPDEV};
    @tapscript = split /\s*,\s*/, $vars->{TAPSCRIPT} if $vars->{TAPSCRIPT};
    @tapdownscript = split /\s*,\s*/, $vars->{TAPDOWNSCRIPT} if $vars->{TAPDOWNSCRIPT};

    my $num_networks = $vars->{OFFLINE_SUT} ? 0 : max(1, scalar @nicmac, scalar @nicvlan, scalar @tapdev);
    for (my $i = 0; $i < $num_networks; $i++) {
        # ensure MAC addresses differ globally
        # and allow MAC addresses for more than 256 workers (up to 16384)
        my $workerid = $vars->{WORKER_ID};
        $nicmac[$i] //= sprintf('52:54:00:12:%02x:%02x', int($workerid / 256) + $i * 64, $workerid % 256);

        # always set proper TAPDEV for os-autoinst when using tap network mode
        my $instance = ($vars->{WORKER_INSTANCE} || 'manual') eq 'manual' ? 255 : $vars->{WORKER_INSTANCE};
        # use $instance for tap name so it is predicable, network is still configured staticaly
        $tapdev[$i] = 'tap' . ($instance - 1 + $i * 64) if !defined($tapdev[$i]) || $tapdev[$i] eq 'auto';
        my $vlan = (@nicvlan) ? $nicvlan[-1] : 0;
        $nicvlan[$i] //= $vlan;
    }
    push @tapscript, 'no' until @tapscript >= $num_networks;    #no TAPSCRIPT by default
    push @tapdownscript, 'no' until @tapdownscript >= $num_networks;    #no TAPDOWNSCRIPT by default

    # put it back to the vars for saving
    $vars->{NICMAC} = join ',', @nicmac;
    $vars->{NICVLAN} = join ',', @nicvlan;
    $vars->{TAPDEV} = join ',', @tapdev if $vars->{NICTYPE} eq "tap";
    $vars->{TAPSCRIPT} = join ',', @tapscript if $vars->{NICTYPE} eq "tap";
    $vars->{TAPDOWNSCRIPT} = join ',', @tapdownscript if $vars->{NICTYPE} eq "tap";

    if ($vars->{NICTYPE} eq "vde") {
        my $mgmtsocket = $vars->{VDE_SOCKETDIR} . '/vde.mgmt';
        my $port = $vars->{VDE_PORT};
        my $vlan = $nicvlan[0];
        # XXX: no useful return value from those commands
        runcmd('vdecmd', '-s', $mgmtsocket, 'port/remove', $port);
        runcmd('vdecmd', '-s', $mgmtsocket, 'port/create', $port);
        if ($vlan) {
            runcmd('vdecmd', '-s', $mgmtsocket, 'vlan/create', $vlan);
            runcmd('vdecmd', '-s', $mgmtsocket, 'port/setvlan', $port, $vlan);
        }

        if ($vars->{VDE_USE_SLIRP}) {
            my @cmd = ('slirpvde', '--dhcp', '-s', "$vars->{VDE_SOCKETDIR}/vde.ctl", '--port', $port + 1);
            my $child_pid = $self->_child_process(
                sub {
                    # overwrite the default die handler to just exit
                    $SIG{__DIE__} = undef;    # uncoverable statement
                    exec @cmd or die "failed to exec slirpvde: $!";    # uncoverable statement
                });
            diag join(' ', @cmd) . " started with pid $child_pid";

            runcmd('vdecmd', '-s', $mgmtsocket, 'port/setvlan', $port + 1, $vlan) if $vlan;
        }
    }

    bmwqemu::save_vars();    # update variables

    mkpath($basedir);

    # do not use autodie here, it can fail on tmpfs, xfs, ...
    run_diag('/usr/bin/chattr', '+C', $basedir);

    bmwqemu::diag('Configuring storage controllers and block devices');
    my $keephdds = $vars->{KEEPHDDS} || $vars->{SKIPTO};
    if ($keephdds) {
        $self->{proc}->load_state();
    } else {
        $self->{proc}->configure_controllers($vars);
        $self->{proc}->configure_blockdevs($bootfrom, $basedir, $vars);
        $self->{proc}->configure_pflash($vars);
    }
    bmwqemu::diag('Initializing block device images');
    $self->{proc}->init_blockdev_images();

    sp('only-migratable') if $self->can_handle({function => 'snapshots', no_warn => 1});
    sp('chardev', 'ringbuf,id=serial0,logfile=serial0,logappend=on');
    sp('serial', 'chardev:serial0');

    if (!$is_s390x) {
        if ($self->requires_audiodev) {
            my $audiodev = $vars->{QEMU_AUDIODEV} // 'intel-hda';
            my $audiobackend = $vars->{QEMU_AUDIOBACKEND} // 'none';
            sp('audiodev', $audiobackend . ',id=snd0');
            if ("$audiodev" eq "intel-hda") {
                sp('device', $audiodev);
                $audiodev = "hda-output";
            }
            sp('device', $audiodev . ',audiodev=snd0');
        }
        else {
            my $soundhw = $vars->{QEMU_SOUNDHW} // 'hda';
            sp('soundhw', $soundhw);
        }
    }
    {
        # Remove floppy drive device on architectures which have it
        sp('global', 'isa-fdc.fdtypeA=none') if (($is_ppc || $is_x86) && !$vars->{QEMU_NO_FDC_SET});

        sp('m', $vars->{QEMURAM}) if $vars->{QEMURAM};
        sp('machine', $vars->{QEMUMACHINE}) if $vars->{QEMUMACHINE};
        sp('cpu', $vars->{QEMUCPU}) if $vars->{QEMUCPU};
        sp('net', 'none') if $vars->{OFFLINE_SUT};
        if (my $path = $vars->{QEMU_HUGE_PAGES_PATH}) {
            sp('mem-prealloc');
            sp('mem-path', $path);
        }

        sp('device', 'virtio-balloon,deflate-on-oom=on') if $vars->{QEMU_BALLOON_TARGET};

        for (my $i = 0; $i < $num_networks; $i++) {
            if ($vars->{NICTYPE} eq "user") {
                my $nictype_user_options = $vars->{NICTYPE_USER_OPTIONS} ? ',' . $vars->{NICTYPE_USER_OPTIONS} : '';
                $nictype_user_options .= ",smb=${\(dirname($basedir))}" if ($vars->{QEMU_ENABLE_SMBD});
                sp('netdev', [qv "user id=qanet$i$nictype_user_options"]);
            }
            elsif ($vars->{NICTYPE} eq "tap") {
                sp('netdev', [qv "tap id=qanet$i ifname=$tapdev[$i] script=$tapscript[$i] downscript=$tapdownscript[$i]"]);
            }
            elsif ($vars->{NICTYPE} eq "vde") {
                sp('netdev', [qv "vde id=qanet0 sock=$vars->{VDE_SOCKETDIR}/vde.ctl port=$vars->{VDE_PORT}"]);
            }
            else {
                die "unknown NICTYPE $vars->{NICTYPE}\n";
            }
            my $bootorder = $vars->{PXEBOOT} ? "bootindex=" . ($i + 1) : '';
            sp('device', [qv "$vars->{NICMODEL} netdev=qanet$i mac=$nicmac[$i] $bootorder"]);
        }

        # Keep additional virtio _after_ Ethernet setup to keep virtio-net as eth0
        if ($vars->{QEMU_VIRTIO_RNG} // 1) {
            my $rngdev = $is_s390x ? 'virtio-rng' : 'virtio-rng-pci';
            sp('object', 'rng-random,filename=/dev/urandom,id=rng0');
            sp('device', "$rngdev,rng=rng0");
        }

        sp('smbios', $vars->{QEMU_SMBIOS}) if $vars->{QEMU_SMBIOS};

        if ($vars->{LAPTOP}) {
            my $laptop_path = "$bmwqemu::scriptdir/dmidata/$vars->{LAPTOP}";
            for my $f (glob "$laptop_path/*.bin") {
                sp('smbios', "file=$f");
            }
        }
        if ($vars->{NBF}) {
            die "Need variable WORKER_HOSTNAME\n" unless $vars->{WORKER_HOSTNAME};
            sp('kernel', -e '/usr/share/ipxe/ipxe.lkrn' ? '/usr/share/ipxe/ipxe.lkrn' : '/usr/share/qemu/ipxe.lkrn');
            my $worker_ip = inet_ntoa(inet_aton($vars->{WORKER_HOSTNAME}));
            die "Unable to determine worker IP from WORKER_HOSTNAME\n" unless $worker_ip;
            sp('append', "dhcp && sanhook iscsi:${worker_ip}::3260:1:$vars->{NBF}", no_quotes => 1);
        }

        $self->setup_tpm($arch);

        my @boot_args;
        # Enable boot menu for aarch64 workaround, see bsc#1022064 for details
        $vars->{BOOT_MENU} //= 1 if ($vars->{BOOTFROM} && ($arch eq 'aarch64'));
        push @boot_args, ('menu=on,splash-time=' . ($vars->{BOOT_MENU_TIMEOUT} // '5000')) if $vars->{BOOT_MENU};
        if ($arch_supports_boot_order) {
            if ($vars->{PXEBOOT}) {
                push @boot_args, ($vars->{PXEBOOT} eq 'once' ? 'once=n' : 'n');
            }
            elsif ($vars->{BOOTFROM}) {
                push @boot_args, "order=$vars->{BOOTFROM}";
            }
            else {
                push @boot_args, 'once=d';
            }
        }
        sp('boot', join(',', @boot_args)) if @boot_args;

        if (!$vars->{UEFI} && $vars->{BIOS}) {
            sp("bios", $vars->{BIOS});
        }

        foreach my $attribute (qw(KERNEL INITRD APPEND)) {
            sp(lc($attribute), $vars->{$attribute}) if $vars->{$attribute};
        }

        unless ($vars->{QEMU_NO_TABLET}) {
            sp('device', ($vars->{OFW} || $arch eq 'aarch64') ? 'nec-usb-xhci' : $is_s390x ? 'virtio-tablet' : 'qemu-xhci');
            sp('device', 'usb-tablet') unless $is_s390x;
        }

        sp('device', 'usb-kbd') if $use_usb_kbd;
        sp('device', 'virtio-keyboard') if $use_virtio_kbd;

        my $smp_config = [$vars->{QEMUCPUS}];
        for my $key (qw(QEMUSOCKETS QEMUDIES QEMUCLUSTERS QEMUCORES QEMUTHREADS)) {
            my $qkey = lc($key =~ s/^QEMU//r);
            push @$smp_config, "$qkey=$vars->{$key}" if exists $vars->{$key};
        }
        sp('smp', $smp_config);

        if ($vars->{QEMU_NUMA}) {
            for my $i (0 .. ($vars->{QEMUCPUS} - 1)) {
                my $m = int($vars->{QEMURAM} / $vars->{QEMUCPUS});
                # add the rest to the first node to ensure all memory is
                # allocated
                $m += $vars->{QEMURAM} % $vars->{QEMUCPUS} if $i == 0;
                sp('object', "memory-backend-ram,size=${m}m,id=m$i");
                sp('numa', [qv "node nodeid=$i,memdev=m$i,cpus=$i"]);
            }
        }

        sp('enable-kvm') if -r '/dev/kvm' && !$vars->{QEMU_NO_KVM};
        sp('no-shutdown');

        if ($vars->{VNC}) {
            my $vncport = $vars->{VNC} !~ /:/ ? ":$vars->{VNC}" : $vars->{VNC};
            my $extravars = $vars->{VNC_EXTRA_VARS};
            $extravars = defined $extravars ? " $extravars" : '';
            sp('vnc', [qv "$vncport share=force-shared$extravars"]);
            sp('k', $vars->{VNCKB}) if $vars->{VNCKB};
        }

        my @virtio_consoles = virtio_console_names;
        if (@virtio_consoles) {
            sp('device', 'virtio-serial');
            for my $name (@virtio_consoles) {
                sp('chardev', [qv "pipe id=$name path=$name logfile=$name.log logappend=on"]);
                sp('device', [qv "virtconsole chardev=$name name=org.openqa.console.$name"]);
            }
        }

        my $qmpid = 'qmp_socket';
        sp('chardev', [qv "socket path=$qmpid server=on wait=off id=$qmpid logfile=$qmpid.log logappend=on"]);
        sp('qmp', "chardev:$qmpid");
        sp('S');
    }

    # Add parameters from QEMU_APPEND var, if any.
    # The first item will have '-' prepended to it.
    if ($vars->{QEMU_APPEND}) {
        # Split multiple options, if needed
        my @spl = split(' -', $vars->{QEMU_APPEND});
        sp(split(' ', $_)) for @spl;
    }

    create_virtio_console_fifo();
    my $qemu_pipe = $self->{qemupipe} = $self->{proc}->exec_qemu();
    return bmwqemu::fctinfo('Not connecting to QEMU as requested by QEMU_ONLY_EXEC') if $vars->{QEMU_ONLY_EXEC};
    $self->{qmpsocket} = $self->{proc}->connect_qmp();
    my $init = myjsonrpc::read_json($self->{qmpsocket});
    my $hash = $self->handle_qmp_command({execute => 'qmp_capabilities'});

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname => 'localhost',
            connect_timeout => 3,
            port => 5900 + $bmwqemu::vars{VNC},
            description => "QEMU's VNC"});

    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    if ($vars->{NICTYPE} eq "tap") {
        $self->{allocated_networks} = $num_networks;
        $self->{allocated_tap_devices} = \@tapdev;
        $self->{allocated_vlan_tags} = \@nicvlan;
        for (my $i = 0; $i < $num_networks; $i++) {
            $self->_dbus_call('set_vlan', $tapdev[$i], $nicvlan[$i]);
        }
        $self->{proc}->_process->on(collected => sub {
                $self->{proc}->_process->emit('cleanup') unless exists $self->{stop_only_qemu} && $self->{stop_only_qemu} == 1;
        });

        $self->{proc}->_process->on(cleanup => sub {
                eval {
                    for (my $i = 0; $i < $self->{allocated_networks}; $i++) {
                        $self->_dbus_call('unset_vlan', (@{$self->{allocated_tap_devices}})[$i], (@{$self->{allocated_vlan_tags}})[$i]);
                    }
                }
        });

        if (exists $vars->{OVS_DEBUG} && $vars->{OVS_DEBUG} == 1) {
            my (undef, $output) = $self->_dbus_call('show');
            bmwqemu::diag "Open vSwitch networking status:";
            bmwqemu::diag $output;
        }
    }

    if ($bmwqemu::vars{DELAYED_START}) {
        bmwqemu::diag("DELAYED_START set, not starting CPU, waiting for resume_vm()");
    }
    else {
        bmwqemu::diag("Start CPU");
        $self->handle_qmp_command({execute => 'cont'});
    }

    $self->{select_read}->add($qemu_pipe, 'qemu::start_qemu::qemu_pipe');
    $self->{select_write}->add($qemu_pipe, 'qemu::start_qemu::qemu_pipe');
}

=head2 handle_qmp_command

Send a QMP command and wait for the result

Pass fatal => 1 to die on failure.
Pass send_fd => $fd to send $fd to QEMU using SCM rights. Probably only useful
with the getfd command.

=cut
sub handle_qmp_command ($self, $cmd, %optargs) {
    $optargs{fatal} ||= 0;
    my $sk = $self->{qmpsocket};

    my $line = Mojo::JSON::to_json($cmd) . "\n";
    if ($bmwqemu::vars{QEMU_ONLY_EXEC}) {
        bmwqemu::fctinfo("Skipping the following qmp_command because QEMU_ONLY_EXEC is enabled:\n$line");
        return undef;
    }
    my $wb = defined $optargs{send_fd} ? tinycv::send_with_fd($sk, $line, $optargs{send_fd}) : syswrite($sk, $line);
    die "handle_qmp_command: syswrite failed $!" unless ($wb == length($line));

    my $hash;
    do {
        $hash = myjsonrpc::read_json($sk);
        if ($hash->{event}) {
            bmwqemu::diag "EVENT " . Mojo::JSON::to_json($hash);
            # ignore
            $hash = undef;
        }
    } until ($hash);
    die "QMP command $cmd->{execute} failed: $hash->{error}->{class}; $hash->{error}->{desc}"
      if $optargs{fatal} && defined($hash->{error});
    return $hash;
}

sub process_qemu_output ($buffer) {
    for my $line (split(/\n/, $buffer)) {
        die "QEMU: Shutting down the job" if $line =~ m/key event queue full/;
        if ($line =~ /^\s*qemu-system-[^:]+: (?!terminating on signal)/) {
            bmwqemu::fctwarn $line, '';
        }
        else {
            bmwqemu::diag "QEMU: $line";
        }
    }
}

sub read_qemupipe ($self) {
    my $buffer;
    my $bytes = sysread($self->{qemupipe}, $buffer, 1000);
    chomp $buffer;
    process_qemu_output($buffer);
    return $bytes;
}

sub close_pipes ($self) {
    $self->do_stop_vm() if $self->{started};

    if (my $qemu_pipe = $self->{qemupipe}) {
        # one last word?
        fcntl($qemu_pipe, Fcntl::F_SETFL, Fcntl::O_NONBLOCK);
        $self->read_qemupipe();
        $self->{select_read}->remove($qemu_pipe);
        $self->{select_write}->remove($qemu_pipe);
        close($qemu_pipe);
        $self->{qemupipe} = undef;
    }

    if ($self->{qmpsocket}) {
        close($self->{qmpsocket}) || die "close $!\n";
        $self->{qmpsocket} = undef;
    }

    $self->SUPER::close_pipes() unless exists $self->{stop_only_qemu} && $self->{stop_only_qemu};
}

sub is_shutdown ($self, @) {
    my $ret = $self->handle_qmp_command({execute => 'query-status'})->{return}->{status}
      || 'unknown';

    diag("QEMU status is not 'shutdown', it is '$ret'") if $ret ne 'shutdown';

    return $ret eq 'shutdown';
}

# this is called for all sockets ready to read from. return 1 if socket
# detected and -1 if there was an error
sub check_socket ($self, $fh, $write = undef) {

    if ($self->{qemupipe} && $fh == $self->{qemupipe}) {
        $self->close_pipes() if !$write && !$self->read_qemupipe();
        return 1;
    }
    return $self->SUPER::check_socket($fh);
}

sub freeze_vm ($self, @) {
    # qemu specific - all other backends will crash
    my $ret = $self->handle_qmp_command({execute => 'stop'}, fatal => 1);
    # once we stopped, there is no point in querying VNC
    if (!defined $self->{_qemu_saved_request_interval}) {
        $self->{_qemu_saved_request_interval} = $self->update_request_interval;
        $self->update_request_interval(1000);
    }
    return $ret;
}

sub cont_vm ($self, @) {
    $self->update_request_interval(delete $self->{_qemu_saved_request_interval}) if $self->{_qemu_saved_request_interval};
    return $self->handle_qmp_command({execute => 'cont'});
}

1;
