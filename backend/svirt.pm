# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2023 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::svirt;
use Mojo::Base 'backend::virt', -signatures;
use Mojo::File qw(path);
use File::Basename;
use IO::Scalar;
use Time::HiRes 'usleep';
use bmwqemu;

use constant SERIAL_CONSOLE_DEFAULT_PORT => 0;
use constant SERIAL_CONSOLE_DEFAULT_DEVICE => 'console';

# root-sut-serial (ssh-virtsh-serial for root)
use constant SERIAL_TERMINAL_DEFAULT_PORT => 1;
use constant SERIAL_TERMINAL_DEFAULT_DEVICE => 'console';

# user-sut-serial (ssh-virtsh-serial for user)
use constant SERIAL_USER_TERMINAL_DEFAULT_PORT => 2;
use constant SERIAL_USER_TERMINAL_DEFAULT_DEVICE => 'console';

use Exporter 'import';
our @EXPORT_OK = qw(SERIAL_CONSOLE_DEFAULT_PORT SERIAL_CONSOLE_DEFAULT_DEVICE SERIAL_TERMINAL_DEFAULT_PORT SERIAL_TERMINAL_DEFAULT_DEVICE SERIAL_USER_TERMINAL_DEFAULT_PORT SERIAL_USER_TERMINAL_DEFAULT_DEVICE);

# this is a fake backend to some extend. We don't start VMs, but provide ssh access
# to a libvirt running host (KVM for System Z in mind)

use constant SERIAL_TERMINAL_LOG_PATH => 'serial_terminal.txt';

sub _vmm_family () { $bmwqemu::vars{VIRSH_VMM_FAMILY} // '' }
sub _is_hyperv () { _vmm_family() eq 'hyperv' }
sub _is_vmware () { _vmm_family() eq 'vmware' }

sub new ($class) {
    my $self = $class->SUPER::new;
    defined $bmwqemu::vars{WORKER_HOSTNAME} or die 'Need variable WORKER_HOSTNAME';

    return $self;
}

sub vmname ($self) { $self->console('svirt')->name }

# we don't do anything actually
sub do_start_vm ($self, @) {
    my $vars = \%bmwqemu::vars;
    my $n = $vars->{NUMDISKS} // 1;
    $vars->{NUMDISKS} //= defined($vars->{RAIDLEVEL}) ? 4 : $n;
    $self->truncate_serial_file;
    my $ssh = $testapi::distri->add_console(
        'svirt',
        'ssh-virtsh',
        {
            hostname => $bmwqemu::vars{VIRSH_HOSTNAME} || die('Need variables VIRSH_HOSTNAME'),
            username => $bmwqemu::vars{VIRSH_USERNAME},
            password => $bmwqemu::vars{VIRSH_PASSWORD},
        });

    $ssh->backend($self);

    bmwqemu::save_vars();    # update variables
    return {};
}

sub do_stop_vm_hyperv ($self) {
    my $vmname = $self->vmname;
    my $ps = 'powershell -Command';
    $self->run_ssh_cmd("$ps Stop-VM -Force -VMName $vmname -TurnOff");
    $self->run_ssh_cmd(qq($ps "\$ProgressPreference='SilentlyContinue'; Remove-VM -Force -VMName $vmname"));
}

sub do_stop_vm_svirt ($self) {
    my $vmname = $self->vmname;
    my $virsh = 'virsh';
    $virsh .= ' ' . $bmwqemu::vars{VMWARE_REMOTE_VMM} if $bmwqemu::vars{VMWARE_REMOTE_VMM};
    $self->run_ssh_cmd("$virsh destroy $vmname");
    $self->run_ssh_cmd("$virsh undefine --snapshots-metadata $vmname");
}

sub do_stop_vm ($self, @) {
    $self->stop_serial_grab;

    unless ($bmwqemu::vars{SVIRT_KEEP_VM_RUNNING}) {
        my $vmname = $self->vmname;
        bmwqemu::diag "Destroying $vmname virtual machine";
        _is_hyperv ? $self->do_stop_vm_hyperv : $self->do_stop_vm_svirt;
    }

    # TODO: stream serial_terminal.txt with scp on the fly instead
    if ($self->{need_delete_log}) {
        $self->scp_get($self->serial_terminal_log_file(), SERIAL_TERMINAL_LOG_PATH);
        $self->delete_log();
    }

    return {};
}

# Log stdout and stderr and return them in a list (comped).
sub scp_get ($self, $src, $dest) {
    bmwqemu::log_call($self, $src, $dest);

    my %credentials = $self->get_ssh_credentials(_is_hyperv ? 'hyperv' : 'default');
    my $ssh = $self->new_ssh_connection(%credentials);

    bmwqemu::diag("SCP file: '$src' => '$dest'");
    my $output = IO::Scalar->new;
    $ssh->scp_get($src, $output) or die "SCP failed";
    path($dest)->spew($output);
    $ssh->disconnect();
}

sub can_handle ($self, $args) {
    $args->{function} eq 'snapshots' && _vmm_family =~ qr/kvm|hyperv|vmware/ ? {ret => 1} : undef;
}

sub is_shutdown_cmd_hyperv ($vmname) { "powershell -Command \"if (\$(Get-VM -VMName $vmname \| Where-Object {\$_.state -eq 'Off'})) { exit 1 } else { exit 0 }\"" }

sub is_shutdown_cmd_svirt ($vmname) {
    my $libvirt_connector = $bmwqemu::vars{VMWARE_REMOTE_VMM} // '';
    return "! virsh $libvirt_connector dominfo $vmname | grep -w 'shut off'";
}

sub is_shutdown ($self, @) {
    my $vmname = $self->vmname;
    return $self->run_ssh_cmd(_is_hyperv ? is_shutdown_cmd_hyperv($vmname) : is_shutdown_cmd_svirt($vmname));
}

sub save_snapshot_cmd_hyperv ($vmname, $snapname) {
    my $ps = 'powershell -Command';
    return qq($ps Remove-VMSnapshot -VMName $vmname -Name $snapname; $ps "\$ProgressPreference='SilentlyContinue'; Checkpoint-VM -VMName $vmname -SnapshotName $snapname");
}

sub save_snapshot_cmd_svirt ($vmname, $snapname) {
    my $libvirt_connector = $bmwqemu::vars{VMWARE_REMOTE_VMM} // '';
    return "virsh $libvirt_connector snapshot-delete $vmname $snapname; virsh $libvirt_connector snapshot-create-as $vmname $snapname";
}

sub save_snapshot ($self, $args) {
    my $snapname = $args->{name};
    my $vmname = $self->vmname;
    my $rsp = $self->run_ssh_cmd(_is_hyperv ? save_snapshot_cmd_hyperv($vmname, $snapname) : save_snapshot_cmd_svirt($vmname, $snapname));
    bmwqemu::diag "SAVE VM $vmname as $snapname snapshot, return code=$rsp";
    $self->die if $rsp;
    return;
}

sub load_snapshot ($self, $args) {
    my $snapname = $args->{name};
    my $vmname = $self->vmname;
    my $rsp;
    my $post_load_snapshot_command = '';
    if (_is_hyperv) {
        my $ps = 'powershell -Command';
        $rsp = $self->run_ssh_cmd(qq($ps "\$ProgressPreference='SilentlyContinue'; Restore-VMSnapshot -VMName $vmname -Name $snapname -Confirm:\$false"));
        $self->run_ssh_cmd("mv -v xfreerdp_${vmname}_stop xfreerdp_${vmname}_stop.bkp", $self->get_ssh_credentials('hyperv'));

        for my $i (1 .. 5) {
            # Because of FreeRDP issue https://github.com/FreeRDP/FreeRDP/issues/3876,
            # we can't connect too "early". Let's have a nap for a while.
            sleep 10;
            last
              unless $self->run_ssh_cmd(
                "pgrep --full --list-full xfreerdp.*\$(cat xfreerdp_${vmname}_stop.bkp)",
                $self->get_ssh_credentials('hyperv'));
            $self->die("xfreerdp did not start") if ($i eq 5);
        }
    }
    else {
        my $libvirt_connector = $bmwqemu::vars{VMWARE_REMOTE_VMM} // '';
        $rsp = $self->run_ssh_cmd("virsh $libvirt_connector snapshot-revert $vmname $snapname");
        $post_load_snapshot_command = 'vmware_fixup' if _is_vmware;
    }
    bmwqemu::diag "LOAD snapshot $snapname to $vmname, return code=$rsp";
    $self->die if $rsp;
    return $post_load_snapshot_command;
}

sub get_ssh_credentials ($self, $domain = 'default') {
    my $ssh_credentials = $self->{ssh_credentials};
    unless ($ssh_credentials) {
        $ssh_credentials = $self->{ssh_credentials} = {
            default => {
                hostname => $bmwqemu::vars{VIRSH_HOSTNAME} || die('Need variable VIRSH_HOSTNAME'),
                username => $bmwqemu::vars{VIRSH_USERNAME} // 'root',
                password => $bmwqemu::vars{VIRSH_PASSWORD} || die('Need variable VIRSH_PASSWORD'),
            }
        };
        # read/require credentials for Hyper-V intermediary host
        $ssh_credentials->{hyperv} = {
            hostname => $bmwqemu::vars{VIRSH_GUEST} || die('Need variable VIRSH_GUEST'),
            password => $bmwqemu::vars{VIRSH_GUEST_PASSWORD} || die('Need variable VIRSH_GUEST_PASSWORD'),
            username => 'root',
        } if _is_hyperv;
    }
    die "Missing ssh credentials domain '$domain'" unless my $c = $ssh_credentials->{$domain};
    return %$c;
}

# Hyper-V does not support serial console export via TCP, just
# windows named pipes (e.g. \\.\pipe\mypipe). Such a named pipe
# has to be enabled by a namedpipe-to-TCP on HYPERV_SERVER application.
sub serial_grab_cmd_hyperv ($) { 'socat - TCP4:' . $bmwqemu::vars{HYPERV_SERVER} . ':' . $bmwqemu::vars{HYPERV_SERIAL_PORT} . ',crnl' }

# libvirt esx driver does not support `virsh console', so
# we have to connect to VM's serial port via TCP which is
# provided by ESXi server.
sub serial_grab_cmd_vmware ($) { 'socat - TCP4:' . $bmwqemu::vars{VMWARE_HOST} . ':' . $bmwqemu::vars{VMWARE_SERIAL_PORT} . ',crnl' }

sub serial_grab_cmd_svirt ($name) { 'virsh console ' . $name }

sub start_serial_grab ($self, $name) {
    bmwqemu::log_call(name => $name);

    my %credentials = $self->get_ssh_credentials(_is_hyperv ? 'hyperv' : 'default');
    my ($ssh, $chan) = $self->start_ssh_serial(%credentials);
    my $cmd = _is_hyperv ? serial_grab_cmd_hyperv($name) : _is_vmware ? serial_grab_cmd_vmware($name) : serial_grab_cmd_svirt($name);
    bmwqemu::diag('svirt: grabbing serial console');
    $ssh->blocking(1);
    if (!$chan->exec($cmd)) {
        bmwqemu::fctwarn('svirt: unable to grab serial console at this point: ' . ($ssh->error // 'unknown SSH error'));
    }
    $ssh->blocking(0);
}

=head2 open_serial_console_via_ssh

  ($ssh, $chan) = open_serial_console_via_ssh($name[, port => ''][, devname => ''])

Opens SSH connection to grab serial terminal log
(using consoles::serial_screen, saved into serial_terminal.txt).

This method is not supposed to be called twice for test run due logging
into file.

C<$args{port}> used non-default port
C<$args{devname}> used device name
=cut

sub open_serial_console_via_ssh ($self, $name, %args) {
    bmwqemu::log_call(name => $name, %args);
    my ($chan, $cmd, $cmd_full, $ret, $ssh, $stderr, $stdout);
    my $port = $args{port} // '';
    my $devname = $args{devname} // '';
    my $marker = "CONSOLE_EXIT_" . $bmwqemu::vars{JOBTOKEN} or die 'Need variable JOBTOKEN' . ":";
    my $log = $self->serial_terminal_log_file();
    my $max_tries = 10;

    if (_is_vmware) {
        # libvirt esx driver does not support `virsh console', so
        # we have to connect to VM's serial port via TCP which is
        # provided by ESXi server.
        $cmd = 'socat - TCP4:' . $bmwqemu::vars{VMWARE_HOST} . ':' . $port . ',crnl';
    }
    elsif (_is_hyperv) {
        # Hyper-V does not support serial console export via TCP, just
        # windows named pipes (e.g. \\.\pipe\mypipe). Such a named pipe
        # has to be enabled by a namedpipe-to-TCP on HYPERV_SERVER application.
        $cmd = 'socat - TCP4:' . $bmwqemu::vars{HYPERV_SERVER} . ':' . $port . ',crnl';
    }
    else {
        $cmd = "virsh console $name $devname$port";
    }

    $cmd_full = "script -f $log -c '$cmd; echo \"$marker \$?\"'";
    bmwqemu::diag("Starting SSH connection to connect to libvirt domain '$name' (cmd: '$cmd'), full cmd: '$cmd_full'");

    ($ssh, $chan) = $self->run_ssh($cmd_full, blocking => 0);
    usleep(500) while ($self->run_ssh_cmd("test -e $log") != 0 && $max_tries-- > 0);
    $self->die("Command 'script' did not create logfile $log") if ($max_tries < 1);
    $self->{need_delete_log} = 1;

    $ret = $self->run_ssh_cmd("grep -q '^$marker' $log");
    if (!$ret) {
        (undef, $stdout, undef) = $self->run_ssh_cmd("cat $log", wantarray => 1);
        $self->die("problem with virsh: cmd: '$cmd', output of script wrapper: '$stdout')");
    }

    return ($ssh, $chan);
}

sub delete_log ($self) {
    my $log = $self->serial_terminal_log_file();
    $self->run_ssh_cmd("[ -f '$log' ] && rm -v $log");
}

# Intent to use CORE::GLOBAL::die, that does not have $self.
sub die ($self, $err = '') {
    if ($self->{need_delete_log}) {
        bmwqemu::fctwarn("error, cleanup logs before die");
        $self->delete_log();
    }
    die $err;
}

sub serial_terminal_log_file ($self) {
    defined $bmwqemu::vars{JOBTOKEN} || CORE::die 'Need variable JOBTOKEN';
    return '/tmp/' . SERIAL_TERMINAL_LOG_PATH . '.' . $bmwqemu::vars{JOBTOKEN};
}

sub check_socket ($self, $fh, $write = undef) { $self->check_ssh_serial($fh, $write) || $self->SUPER::check_socket($fh, $write) }    # uncoverable statement

sub stop_serial_grab ($self, @) {
    $self->stop_ssh_serial;
    return;
}

sub get_wait_still_screen_on_here_doc_input ($self, $args) {
    # We encountered a sporadic error when type into the here-document in the
    # distribution::script_output() function (poo#60566). This issue was only
    # seen by svirt backends from VMM_FAMILY hyperv or vmware.
    #
    # With wait_still_screen we actually do a sleep, but the given duration is
    # the minimum and will be extended till there is no change on the screen.
    # by comparing the screen and checking that nothing else will write on it.
    # So if the here-document input is really slow, we hope the wait_still_screen
    # takes even longer.
    _vmm_family() =~ qr/^(hyperv|vmware)$/ ? 1 : 0;
}

1;
