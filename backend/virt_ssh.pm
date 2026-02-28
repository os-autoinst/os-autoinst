# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Object::Pad;
use bmwqemu;

# new baseclass that can be used in backend::hyperv.
# TODO:
# 1. move all necessary joint svirt+hyperv+vmware relevant implementation here
# 2. make hyperv and svirt inherit from here
# 3. make use of hyperv backend directly
# 4. deprecate using svirt(hyperv)
# 5. move more hyperv functionality from osado to backend
# 6. repeat the same steps for vmware
# 7. make svirt inherit "roles" hyperv+vmware
# 8. potentially remove virt_ssh baseclass again if hyperv+vmware backends
#    implement all in roles
class backend::virt_ssh : isa(backend::virt);

method do_start_vm (@) {
    my $vars = \%bmwqemu::vars;
    my $n = $vars->{NUMDISKS} // 1;
    $vars->{NUMDISKS} //= defined($vars->{RAIDLEVEL}) ? 4 : $n;
    $self->truncate_serial_file();
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

# TODO duplication from backend::svirt. Should we move to another file with
# utility functions? Later we should replace this with proper inheritance
my method vmm_family () { $bmwqemu::vars{VIRSH_VMM_FAMILY} // '' }
my method is_hyperv () { vmm_family($self) eq 'hyperv' }
my method is_vmware () { vmm_family($self) eq 'vmware' }


method can_handle ($args) {
    $args->{function} eq 'snapshots' && vmm_family($self) =~ qr/kvm|hyperv|vmware/ ? {ret => 1} : undef;
}

my method vmname () { $self->console('svirt')->name }

my method save_snapshot_cmd_hyperv ($vmname, $snapname) {
    my $ps = 'powershell -Command';
    return qq($ps Remove-VMSnapshot -VMName $vmname -Name $snapname; $ps "\$ProgressPreference='SilentlyContinue'; Checkpoint-VM -VMName $vmname -SnapshotName $snapname");
}

my method save_snapshot_cmd_svirt ($vmname, $snapname) {
    my $libvirt_connector = $bmwqemu::vars{VMWARE_REMOTE_VMM} // '';
    return "virsh $libvirt_connector snapshot-delete $vmname $snapname; virsh $libvirt_connector snapshot-create-as $vmname $snapname";
}

method save_snapshot ($args) {
    my $snapname = $args->{name};
    my $vmname = vmname($self);
    my $rsp = $self->run_ssh_cmd(is_hyperv($self) ? save_snapshot_cmd_hyperv($self, $vmname, $snapname) : save_snapshot_cmd_svirt($self, $vmname, $snapname));
    bmwqemu::diag "SAVE VM $vmname as $snapname snapshot, return code=$rsp";
    $self->die('svirt: save_snapshot failed') if $rsp;
    return;
}

my method get_ssh_credentials ($domain = 'default') {
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
        } if is_hyperv($self);
    }
    die "Missing ssh credentials domain '$domain'" unless my $c = $ssh_credentials->{$domain};
    return %$c;
}


method load_snapshot ($args) {
    my $snapname = $args->{name};
    my $vmname = vmname($self);
    my $rsp;
    my $post_load_snapshot_command = '';
    if (is_hyperv($self)) {
        my $ps = 'powershell -Command';
        $rsp = $self->run_ssh_cmd(qq($ps "\$ProgressPreference='SilentlyContinue'; Restore-VMSnapshot -VMName $vmname -Name $snapname -Confirm:\$false"));
        $self->run_ssh_cmd("mv -v xfreerdp_${vmname}_stop xfreerdp_${vmname}_stop.bkp", get_ssh_credentials('hyperv'));

        for my $i (1 .. 5) {
            # Because of FreeRDP issue https://github.com/FreeRDP/FreeRDP/issues/3876,
            # we can't connect too "early". Let's have a nap for a while.
            sleep 10;
            last
              unless $self->run_ssh_cmd(
                "pgrep --full --list-full xfreerdp.*\$(cat xfreerdp_${vmname}_stop.bkp)",
                get_ssh_credentials('hyperv'));
            $self->die("xfreerdp did not start") if ($i eq 5);
        }
    }
    else {
        my $libvirt_connector = $bmwqemu::vars{VMWARE_REMOTE_VMM} // '';
        $rsp = $self->run_ssh_cmd("virsh $libvirt_connector snapshot-revert $vmname $snapname");
        $post_load_snapshot_command = 'vmware_fixup' if is_vmware($self);
    }
    bmwqemu::diag "LOAD snapshot $snapname to $vmname, return code=$rsp";
    $self->die('svirt: load_snapshot failed') if $rsp;
    return $post_load_snapshot_command;
}


1;
