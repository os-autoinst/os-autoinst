# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshVirtshOVA;

use Mojo::Base 'consoles::sshVirtsh', -signatures;
use autodie ':all';
use Feature::Compat::Try;
use File::Temp 'tempfile';
use Mojo::DOM;
use Mojo::URL;
use Carp 'croak';
use bmwqemu;

sub _shell_escape ($arg) {
    if ($arg =~ m{^[a-zA-Z0-9_.-]+$}) {
        return $arg;
    }
    $arg =~ s{'}{'\\''}g;
    return "'$arg'";
}

sub define_and_start ($self, %args) {
    $args{pre_cleanup} //= 1;

    # 1. Destroy and undefine previous VM if pre_cleanup is set
    $self->backend->do_stop_vm_svirt() if $args{pre_cleanup};

    # 2. Extract parameters for deployment
    my $ova_path = $bmwqemu::vars{OVA} // $bmwqemu::vars{HDD_1} or die 'Need variable OVA or HDD_1';
    my $vmware_host = $bmwqemu::vars{VMWARE_HOST} or die 'Need variable VMWARE_HOST';
    my $vmware_username = $bmwqemu::vars{VMWARE_USERNAME} // 'root';
    my $vmware_password = $bmwqemu::vars{VMWARE_PASSWORD} or die 'Need variable VMWARE_PASSWORD';
    my $vmware_datastore = $bmwqemu::vars{VMWARE_DATASTORE};
    my $vmware_network = $bmwqemu::vars{VMWARE_NETWORK};

    my $target_url = Mojo::URL->new();
    $target_url->scheme('vi');
    $target_url->userinfo("$vmware_username:$vmware_password");
    $target_url->host($vmware_host);

    # Build the ovftool command
    my @ovf_cmd = qw(ovftool --acceptAllEulas --noSSLVerify --overwrite --powerOffTarget);
    push @ovf_cmd, '--name=' . $self->name;
    push @ovf_cmd, '--datastore=' . $vmware_datastore if $vmware_datastore;
    if ($vmware_network) {
        my $source_net = $bmwqemu::vars{VMWARE_SOURCE_NETWORK} // 'VM Network';
        push @ovf_cmd, "--net:$source_net=$vmware_network";
    }
    if (my $extra_args = $bmwqemu::vars{OVFTOOL_ARGS}) {
        push @ovf_cmd, split /\s+/, $extra_args;
    }
    push @ovf_cmd, $ova_path;
    push @ovf_cmd, $target_url->to_unsafe_string;

    my $cmd_str = join ' ', map { _shell_escape($_) } @ovf_cmd;
    bmwqemu::diag("Deploying OVA using ovftool: $cmd_str");

    # Run the command with retries on timeouts if configured
    my $ret = $self->run_cmd_retrying_on_timeouts($cmd_str);
    die "ovftool deployment failed: $ret\n" if $ret;

    # 3. Write guestinfo and other customizations to the .vmx file on ESXi host
    if ($self->vmm_family eq 'vmware') {
        my ($fh, $libvirtauthfilename) = File::Temp::tempfile('libvirtauth-XXXX', DIR => '/tmp/');
        $self->run_cmd(
            qq{cat > $libvirtauthfilename <<__END
[credentials-vmware]
username=$vmware_username
password=$vmware_password
[auth-esx-$vmware_host]
credentials=vmware
__END}
        );
        my $remote_vmm = "-c esx://$vmware_username\@$vmware_host/?no_verify=1\\&authfile=$libvirtauthfilename ";
        $bmwqemu::vars{VMWARE_REMOTE_VMM} = $remote_vmm;

        my $vmx = sprintf '/vmfs/volumes/%s/%s/%s.vmx', $vmware_datastore // 'datastore1', $self->name, $self->name;

        # set default boot delay
        $self->run_cmd(qq{echo 'bios.bootDelay = "10000"' >> $vmx}, domain => 'sshVMwareServer');
        # set default nvram
        my $nvram = $self->name . '.nvram';
        my $nvram_path = sprintf '/vmfs/volumes/%s/%s/%s', $vmware_datastore // 'datastore1', $self->name, $nvram;
        $ret = $self->run_cmd("test -e $nvram_path", domain => 'sshVMwareServer');
        $self->run_cmd(qq{echo 'nvram = "$nvram"' >> $vmx}, domain => 'sshVMwareServer') unless ($ret);
        # set virtual hardware version if specified
        if ($bmwqemu::vars{VMWARE_VM_HWVERSION}) {
            $self->run_cmd(qq{sed -i 's/^virtualHW.version = ".*"/virtualHW.version = "$bmwqemu::vars{VMWARE_VM_HWVERSION}"/' $vmx}, domain => 'sshVMwareServer');
        }

        # provisioning (guestinfo combustion/ignition/cloud-init)
        my $fb_tool = $bmwqemu::vars{GUESTINFO_CONFIG};
        if ($fb_tool && $fb_tool ne 'wizard') {
            my $encoding = 'gzip+base64';
            if ($fb_tool =~ /combustion|ignition/) {
                if ($bmwqemu::vars{GUESTINFO_COMBUSTION}) {
                    my $conf = $self->_encode_config($bmwqemu::vars{GUESTINFO_COMBUSTION}, 'GUESTINFO_COMBUSTION');
                    $self->run_cmd(qq{echo 'guestinfo.combustion.script = "$conf"' >> $vmx}, domain => 'sshVMwareServer');
                }
                if ($bmwqemu::vars{GUESTINFO_IGNITION}) {
                    my $conf = $self->_encode_config($bmwqemu::vars{GUESTINFO_IGNITION}, 'GUESTINFO_IGNITION');
                    $self->run_cmd(qq{echo 'guestinfo.ignition.config.data.encoding = "$encoding"' >> $vmx}, domain => 'sshVMwareServer');
                    $self->run_cmd(qq{echo 'guestinfo.ignition.config.data = "$conf"' >> $vmx}, domain => 'sshVMwareServer');
                }
            } elsif ($fb_tool eq 'cloud-init') {
                croak 'GUESTINFO_CLOUD_INIT is unset, or does not contain user-data and meta-data configs' unless ($bmwqemu::vars{GUESTINFO_CLOUD_INIT});

                my ($conf, $meta) = split /,/, $bmwqemu::vars{GUESTINFO_CLOUD_INIT};
                $self->run_cmd(qq{echo 'guestinfo.userdata.encoding = "$encoding"' >> $vmx}, domain => 'sshVMwareServer');
                $self->run_cmd(qq{echo 'guestinfo.metadata.encoding = "$encoding"' >> $vmx}, domain => 'sshVMwareServer');
                $conf = $self->_encode_config($conf, 'GUESTINFO_CLOUD_INIT');
                $self->run_cmd(qq{echo 'guestinfo.userdata = "$conf"' >> $vmx}, domain => 'sshVMwareServer');
                $meta = $self->_encode_config($meta, 'GUESTINFO_CLOUD_INIT');
                $self->run_cmd(qq{echo 'guestinfo.metadata = "$meta"' >> $vmx}, domain => 'sshVMwareServer');
            } else {
                croak 'Unknown provisioning option has been passed through GUESTINFO_CONFIG test variable';
            }
        }
    }

    # 4. Start the VM using virsh
    $ret = $self->run_cmd(backend::svirt::virsh() . ' start ' . $self->name . ' 2> >(tee /tmp/os-autoinst-' . $self->name . '-stderr.log >&2)');
    bmwqemu::diag('Dump actually used libvirt configuration file ' . ($ret ? '(broken)' : '(working)'));
    my $config = $self->get_cmd_output(backend::svirt::virsh() . ' dumpxml ' . $self->name);
    die "virsh start failed: $ret\n\nvirsh domain XML:\n$config" if $ret;
    my $config_domain = Mojo::DOM->new($config)->at('domain');
    my $vm_id = $config_domain ? $config_domain->attr('id') : '';
    die "virsh domain XML does not specify VM ID which is required from VNC over WebSockets:\n$config" if !$vm_id && $bmwqemu::vars{VMWARE_VNC_OVER_WS};
    $bmwqemu::vars{VIRSH_VM_ID} = $vm_id;

    $self->backend->start_serial_grab($self->name);

    return;
}

1;
