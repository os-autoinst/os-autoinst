# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshVirtsh;

use Mojo::Base 'consoles::sshXtermVt', -signatures;
use autodie ':all';
require IPC::System::Simple;
use XML::LibXML;
use File::Temp 'tempfile';
use File::Basename;
use File::Which;
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);

use backend::svirt;

has [qw(instance name vmm_family vmm_type vmm_firmware)];

sub new ($class, $testapi_console = undef, $args = {}) {
    my $self = $class->SUPER::new($testapi_console, $args);

    $self->instance($bmwqemu::vars{VIRSH_INSTANCE} // 1);
    # default name
    $self->name("openQA-SUT-" . $self->instance);
    $self->vmm_family($bmwqemu::vars{VIRSH_VMM_FAMILY} // 'kvm');
    $self->vmm_type($bmwqemu::vars{VIRSH_VMM_TYPE} // 'hvm');
    $self->vmm_firmware($bmwqemu::vars{VIRSH_VMM_FIRMWARE} // 'efi');

    return $self;
}

sub activate ($self) {
    my $args = $self->{args};

    # initialize SSH console(s)
    $self->_init_ssh($args);

    # start Xvnc
    $self->SUPER::activate;

    $self->_init_xml();
}

# initializes the SSH credentials, $domain is used to distinguish between the
# regular SSH and the one to the VMware server
sub _init_ssh ($self, $args) {
    $self->{ssh_credentials} = {
        default => {
            hostname => $args->{hostname} || die('we need a hostname to ssh to'),
            username => $args->{username} // 'root',
            password => $args->{password},
        }
    };
    if ($self->vmm_family eq 'vmware') {
        $self->{ssh_credentials}->{sshVMwareServer} =
          {
            hostname => $bmwqemu::vars{VMWARE_HOST} || die('Need variable VMWARE_HOST'),
            password => $bmwqemu::vars{VMWARE_PASSWORD} || die('Need variable VMWARE_PASSWORD'),
            username => 'root',
          };
    }
}

sub get_ssh_credentials ($self, $domain = undef) {
    $domain //= 'default';
    die "Unknown ssh credentials domain $domain" unless my $c = $self->{ssh_credentials}->{$domain};
    return %$c;
}

# creates an XML document to configure the libvirt domain
# (see https://libvirt.org/formatdomain.html for the specification of that config file)
sub _init_xml ($self, $args = {}) {
    my $instance = $self->instance;
    my $doc = $self->{domainxml} = XML::LibXML::Document->new;
    my $root = $doc->createElement('domain');
    $root->setAttribute(type => $self->vmm_family);
    $doc->setDocumentElement($root);

    my $elem;
    $elem = $doc->createElement('name');
    $elem->appendTextNode($self->name);
    $root->appendChild($elem);

    my $openqa_hostname = $bmwqemu::vars{OPENQA_HOSTNAME} // 'no-webui-set';
    $elem = $doc->createElement('description');
    $elem->appendTextNode("openQA WebUI: $openqa_hostname ($instance): ");
    $elem->appendTextNode($bmwqemu::vars{NAME} // '0-no-scenario');
    $root->appendChild($elem);

    $elem = $doc->createElement('memory');
    $elem->appendTextNode($bmwqemu::vars{QEMURAM} or die 'Need variable QEMURAM');
    $elem->setAttribute(unit => 'MiB');
    $root->appendChild($elem);

    $elem = $doc->createElement('vcpu');
    $elem->appendTextNode($bmwqemu::vars{QEMUCPUS} or die 'Need variable QEMUCPUS');
    $root->appendChild($elem);

    my $os = $doc->createElement('os');
    $os->setAttribute(firmware => $self->vmm_firmware) if ($bmwqemu::vars{UEFI} and $self->vmm_family eq 'vmware');
    $root->appendChild($os);

    $elem = $doc->createElement('type');
    $elem->appendTextNode($self->vmm_type);
    $elem->setAttribute(arch => $bmwqemu::vars{ARCH}) if ($self->vmm_family eq 'vmware');
    $os->appendChild($elem);

    # Following 'features' are required for VM to correctly shutdown
    my $features = $doc->createElement('features');
    $root->appendChild($features);
    $elem = $doc->createElement('acpi');
    $features->appendChild($elem);
    $elem = $doc->createElement('apic');
    $features->appendChild($elem);
    $elem = $doc->createElement('pae');
    $features->appendChild($elem);

    if ($self->vmm_family eq 'xen' and $self->vmm_type eq 'linux') {
        $elem = $doc->createElement('kernel');
        $elem->appendTextNode('/usr/lib/grub2/x86_64-xen/grub.xen');
        $os->appendChild($elem);
    }

    # The root of all problems is this: Xen closes VNC and serial console connections
    # on reboot. Unlike KVM. So, to know when we are restarting if we are in the
    # state before, or after restart we have to configure libvirt to destroy
    # (i.e. turn off) the VM. Then we have to explicitly start it define_and_start.
    # Even if KVM does not need this, from test code POV it's convenient to have it.
    if ($self->vmm_family eq 'xen' || $self->vmm_family eq 'kvm') {
        $elem = $doc->createElement('on_reboot');
        $elem->appendTextNode('destroy');
        $root->appendChild($elem);
    }

    if ($bmwqemu::vars{UEFI} and $bmwqemu::vars{ARCH} eq 'x86_64' and !$bmwqemu::vars{BIOS} and $bmwqemu::vars{VIRSH_VMM_FAMILY} ne 'hyperv' and $bmwqemu::vars{VIRSH_VMM_FAMILY} ne 'vmware') {
        foreach my $firmware (@bmwqemu::ovmf_locations) {
            if (!$self->run_cmd("test -e $firmware")) {
                $bmwqemu::vars{BIOS} = $firmware;
                $elem = $doc->createElement('loader');
                $elem->appendTextNode($firmware);
                $os->appendChild($elem);
                last;
            }
        }
        if (!$bmwqemu::vars{BIOS}) {
            # We know this won't go well.
            my $virsh_hostname = $bmwqemu::vars{VIRSH_HOSTNAME} // '';
            die "No UEFI firmware can be found on hypervisor '$virsh_hostname'. Please specify BIOS or UEFI_BIOS or install an appropriate package.";
        }
    }

    $self->{devices_element} = $doc->createElement('devices');
    $root->appendChild($self->{devices_element});

    return;
}

# allows to add and remove elements in the domain XML
#  - add text node:
#    change_domain_element(funny => guy => 'hello');
# -  remove node:
#    change_domain_element(funny => guy => undef);
# - set attributes:
#    change_domain_element(funny => guy => { hello => 'world' });
sub change_domain_element ($self, @args) {
    my $doc = $self->{domainxml};
    my $elem = $doc->getElementsByTagName('domain')->[0];

    while (@args > 1) {
        my $parent = $elem;
        my $tag_name = shift @args;
        $elem = $parent->getElementsByTagName($tag_name)->[0];
        # create it if not existent
        if (!$elem) {
            $elem = $doc->createElement($tag_name);
            $parent->appendChild($elem);
        }
    }
    my $tag = $args[0];
    if (!$tag) {
        # for undef delete the node
        $elem->unbindNode();
    }
    else {
        if (ref($tag) eq 'HASH') {
            # for hashes set the attributes
            while (my ($key, $value) = each %$tag) {
                $elem->setAttribute($key => $value);
            }
        }
        else {
            $elem->appendTextNode($tag);
        }
    }

    return;
}

# adds the serial console used for the serial log
sub add_pty ($self, $args) {
    my $doc = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $console = $doc->createElement($args->{pty_dev} || backend::svirt::SERIAL_CONSOLE_DEFAULT_DEVICE);
    $console->setAttribute(type => $args->{pty_dev_type} || 'pty');
    $devices->appendChild($console);

    my $elem = $doc->createElement('target');
    if ($args->{target_type}) {
        $elem->setAttribute(type => $args->{target_type});
    }
    $elem->setAttribute(port => $args->{target_port});
    $console->appendChild($elem);

    if ($args->{protocol_type}) {
        my $elem = $doc->createElement('protocol');
        $elem->setAttribute(type => $args->{protocol_type});
        $console->appendChild($elem);
    }

    if ($args->{source}) {
        my $elem = $doc->createElement('source');
        $elem->setAttribute(mode => 'bind');
        $elem->setAttribute(host => '0.0.0.0');
        $elem->setAttribute(service => $bmwqemu::vars{VMWARE_SERIAL_PORT});
        $console->appendChild($elem);
    }

    return;
}

# this is an equivalent of QEMU's '-vnc' option for tests where we watch
# the system from boot on (e.g. JeOS)
sub add_vnc ($self, $args) {
    my $doc = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $graphics = $doc->createElement('graphics');
    $graphics->setAttribute(type => 'vnc');
    $graphics->setAttribute(port => $args->{port});
    $graphics->setAttribute(autoport => 'no');
    $graphics->setAttribute(listen => '0.0.0.0');
    $graphics->setAttribute(sharePolicy => 'force-shared');
    if (my $vnc_password = $testapi::password) {
        $graphics->setAttribute(passwd => $vnc_password);
    }
    $devices->appendChild($graphics);

    my $elem = $doc->createElement('listen');
    $elem->setAttribute(type => 'address');
    $elem->setAttribute(address => '0.0.0.0');
    $graphics->appendChild($elem);

    return;
}

sub add_input ($self, $args) {
    my $doc = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $input = $doc->createElement('input');
    $input->setAttribute(type => $args->{type});
    $input->setAttribute(bus => $args->{bus});
    $devices->appendChild($input);

    return;
}

# network stuff
sub add_interface ($self, $args) {
    my $doc = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $type = delete $args->{type};
    my $interface = $doc->createElement('interface');
    $interface->setAttribute(type => $type);
    $devices->appendChild($interface);

    for my $key (keys %$args) {
        my $elem = $doc->createElement($key);
        my $value = $args->{$key};
        for my $attr (keys %$value) {
            $elem->setAttribute($attr => $value->{$attr});
        }
        $interface->appendChild($elem);
    }

    return;
}

sub _create_disk ($self, $args, $vmware_openqa_datastore, $file, $name, $basedir) {
    my $size = $args->{size} || '20G';
    if ($self->vmm_family eq 'vmware') {
        my $vmware_disk_path = $vmware_openqa_datastore . $file;
        # Power VM off, delete it's disk image, and create it again.
        # Than wait for some time for the VM to *really* turn off.
        my $cmd =
          "( set -x; vmid=\$(vim-cmd vmsvc/getallvms | awk \'/$name/ { print \$1 }\');" .
          'if [ $vmid ]; then ' .
          'vim-cmd vmsvc/power.off $vmid;' .
          'vim-cmd vmsvc/destroy $vmid;' .
          'fi;' .
          "vmkfstools -v1 -U $vmware_disk_path;" .
          "vmkfstools -v1 -c $size --diskformat thin $vmware_disk_path; sleep 10 ) 2>&1";
        my $retval = $self->run_cmd($cmd, domain => 'sshVMwareServer');
        die "Can't create VMware image $vmware_disk_path" if $retval;
    }
    else {
        $file = $basedir . $file;
        my $bucket = 5;
        # Avoid qemu-img's failure to get a write lock to be the reason for a job to fail
        while (1) {
            my ($ret, $stdout, $stderr) = $self->run_cmd("qemu-img create $file $size -f qcow2", wantarray => 1);
            if ($stderr =~ /lock/i) {
                $bucket--;
                die "Too many attempts to format HDD" unless $bucket;
                bmwqemu::diag("Resource is still not free, waiting a bit more. $bucket attempts left");
                sleep 5;
                next;
            }
            last unless $ret;
        }
    }
    return $file;
}

sub _copy_image_vmware ($self, $name, $backingfile, $file_basename, $vmware_openqa_datastore, $vmware_disk_path, $vmware_disk_path_thinfile) {
    # If the file exists, make sure someone else is not copying it there right now,
    # otherwise copy image from NFS datastore.
    my $nfs_dir = $backingfile ? 'hdd' : 'iso';
    my $vmware_nfs_datastore = $bmwqemu::vars{VMWARE_NFS_DATASTORE} or die 'Need variable VMWARE_NFS_DATASTORE';
    my $cmd =
      "if test -e $vmware_openqa_datastore$file_basename; then " .
      "while lsof | grep 'cp.*$file_basename'; do " .
      "echo File $file_basename is being copied by other process, sleeping for 60 seconds; sleep 60;" .
      'done;' .
      'else ' .
      "cp /vmfs/volumes/$vmware_nfs_datastore/$nfs_dir/$file_basename $vmware_openqa_datastore;" .
      'fi;';
    my $retval = $self->run_cmd($cmd, domain => 'sshVMwareServer');
    die "Can't copy VMware image $file_basename" if $retval;
    return unless $backingfile;
    # Power VM off, delete it's disk image, and create it again.
    # Than wait for some time for the VM to *really* turn off.
    $cmd =
      "( set -x; vmid=\$(vim-cmd vmsvc/getallvms | awk \'/$name/ { print \$1 }\');" .
      'if [ $vmid ]; then ' .
      'vim-cmd vmsvc/power.off $vmid;' .
      'fi;' .
      "vmkfstools -v1 -U $vmware_disk_path_thinfile;" .
      "vmkfstools -v1 -i $vmware_disk_path --diskformat thin $vmware_disk_path_thinfile; sleep 10 ) 2>&1";
    $retval = $self->run_cmd($cmd, domain => 'sshVMwareServer');
    die "Can't create thin VMware image" if $retval;
}

sub _system (@cmd) { system @cmd }    # uncoverable statement

sub _copy_image_else ($self, $file, $file_basename, $basedir) {
    # utilize asset possibly cached by openQA worker, otherwise sync locally on svirt host (usually relying on NFS mount)
    if (($bmwqemu::vars{SVIRT_WORKER_CACHE} // 0) && -e $file_basename && defined which 'rsync') {
        my %c = $self->get_ssh_credentials;
        my $abs = path($file_basename)->to_abs;    # pass abs path so it can contain a colon
        bmwqemu::diag "Syncing '$file_basename' directly from worker host to $c{hostname}";
        _system("sshpass -p '$c{password}' rsync -e 'ssh -o StrictHostKeyChecking=no' -av '$abs' '$c{username}\@$c{hostname}:$basedir/$file_basename'");
    }
    else {
        $self->run_cmd("rsync -av '$file' '$basedir/$file_basename'") && die 'rsync failed';
    }
    if ($file_basename =~ /(.*)\.xz$/) {
        $self->run_cmd("nice ionice unxz -f -k '$basedir/$file_basename'");
        $file_basename = $1;
    }
}

sub _copy_image_to_vm_host ($self, $args, $vmware_openqa_datastore, $file, $name, $basedir, $cdrom) {
    # Copy image to VM host
    die 'No file given' unless $args->{file};
    my $file_basename = basename($args->{file});
    my $backingfile = $args->{backingfile};
    my $vmware_disk_path = $vmware_openqa_datastore . $file_basename;
    my $vmware_disk_path_thinfile = $vmware_disk_path =~ s/\.vmdk/_${name}_thinfile\.vmdk/r;
    if ($cdrom || $backingfile) {
        if ($self->vmm_family eq 'vmware') {
            $self->_copy_image_vmware($name, $backingfile, $file_basename, $vmware_openqa_datastore, $vmware_disk_path, $vmware_disk_path_thinfile);
        }
        else {
            $self->_copy_image_else($args->{file}, $file_basename, $basedir);
        }
    }

    # e.g. cdrom
    return ($self->vmm_family eq 'vmware' ? '' : $basedir) . $file_basename unless $backingfile;

    if ($self->vmm_family eq 'vmware') {
        $file = basename($vmware_disk_path_thinfile);
    }
    else {
        $file = $basedir . $file;
        # requested expected value in GBs, if there is any passed as an argument
        my $size = $args->{size} // 0;
        # expected value in Bytes
        my (undef, $json) = $self->run_cmd("qemu-img info --output=json $args->{file}", wantarray => 1);
        my $image_vsize = decode_json($json)->{'virtual-size'};
        $size = (($size * 1024 * 1024 * 1024) <= $image_vsize) ? $image_vsize : $size . 'G';
        $self->run_cmd(sprintf("qemu-img create '${file}' -f qcow2 -F qcow2 -b '$basedir/%s' ${size}", $file_basename))
          && die 'qemu-img create with backing file failed';
    }
    return $file;
}

sub _driver_elem ($doc, $cdrom) {
    my $elem = $doc->createElement('driver');
    $elem->setAttribute(name => 'qemu');
    if ($cdrom) {
        $elem->setAttribute(type => 'raw');
    }
    else {
        $elem->setAttribute(type => 'qcow2');
        $elem->setAttribute(cache => 'unsafe');
    }
    return $elem;
}

sub _handle_disk_type ($vmm_family, $cdrom, $dev_id) {
    return ("sd$dev_id", 'scsi') if $cdrom && $vmm_family eq 'xen';
    return ("xvd$dev_id", 'xen') if $vmm_family eq 'xen';
    return ("hd$dev_id", 'ide') if $vmm_family eq 'vmware';
    return ("hd$dev_id", 'ide') if $cdrom && $vmm_family eq 'kvm';
    return ("vd$dev_id", 'virtio') if $vmm_family eq 'kvm';
    return (undef, undef);
}

sub _bootorder_elem ($doc, $bootorder) {
    my $elem = $doc->createElement('boot');
    $elem->setAttribute(order => $bootorder);
    return $elem;
}

sub add_disk ($self, $args) {
    my $cdrom = $args->{cdrom};
    my $name = $self->name;
    my $file = $name . $args->{dev_id} . ($self->vmm_family eq 'vmware' ? '.vmdk' : '.img');
    my $basedir = '/var/lib/libvirt/images/';
    my $vmware_datastore = $bmwqemu::vars{VMWARE_DATASTORE} // '';
    my $vmware_openqa_datastore = "/vmfs/volumes/$vmware_datastore/openQA/";
    if ($args->{create}) {
        $file = $self->_create_disk($args, $vmware_openqa_datastore, $file, $name, $basedir);
    }
    else {
        $file = $self->_copy_image_to_vm_host($args, $vmware_openqa_datastore, $file, $name, $basedir, $cdrom);
    }

    my $doc = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $disk = $doc->createElement('disk');
    $disk->setAttribute(type => 'file');
    $disk->setAttribute(device => $cdrom ? 'cdrom' : 'disk');
    $devices->appendChild($disk);

    # there's no <driver> property on VMware
    $disk->appendChild(_driver_elem($doc, $cdrom)) if $self->vmm_family ne 'vmware';
    my ($dev_type, $bus_type) = _handle_disk_type($self->vmm_family, $cdrom, $args->{dev_id});
    my $elem = $doc->createElement('target');
    $elem->setAttribute(dev => $dev_type);
    $elem->setAttribute(bus => $bus_type);
    $disk->appendChild($elem);

    $elem = $doc->createElement('source');
    $file =~ s/\.xz$//;
    $elem->setAttribute(file => $self->vmm_family eq 'vmware' ? "[$vmware_datastore] openQA/$file" : $file);
    $disk->appendChild($elem);

    if (my $bootorder = $args->{bootorder}) { $disk->appendChild(_bootorder_elem($doc, $bootorder)) }
    return;
}

sub virsh () {
    my $virsh = 'virsh';
    $virsh .= ' ' . $bmwqemu::vars{VMWARE_REMOTE_VMM} if $bmwqemu::vars{VMWARE_REMOTE_VMM};
    return $virsh;
}

sub suspend ($self) {
    $self->run_cmd(virsh() . " suspend " . $self->name) && die "Can't suspend VM ";
    bmwqemu::diag "VM " . $self->name . " suspended";
}

sub resume ($self) {
    $self->run_cmd(virsh() . " resume " . $self->name) && die "Can't resume VM ";
    bmwqemu::diag "VM " . $self->name . " resumed";
}

sub get_remote_vmm ($self) { $bmwqemu::vars{VMWARE_REMOTE_VMM} // '' }

sub define_and_start ($self) {
    my $remote_vmm = "";
    if ($self->vmm_family eq 'vmware') {
        my ($fh, $libvirtauthfilename) = File::Temp::tempfile('libvirtauth-XXXX', DIR => "/tmp/");

        # The libvirt esx driver supports connection over HTTP(S) only. When
        # asked to authenticate we provide the password via 'authfile'.
        $self->run_cmd(
            "cat > $libvirtauthfilename <<__END
[credentials-vmware]
username=" . ($bmwqemu::vars{VMWARE_USERNAME} or die 'Need variable VMWARE_USERNAME') . "
password=" . ($bmwqemu::vars{VMWARE_PASSWORD} or die 'Need variable VMWARE_PASSWORD') . "
[auth-esx-" . ($bmwqemu::vars{VMWARE_HOST} or die 'Need variable VMWARE_HOST') . "]
credentials=vmware
__END"
        );
        my $user = $bmwqemu::vars{VMWARE_USERNAME} or die 'Need variable VMWARE_USERNAME';
        my $host = $bmwqemu::vars{VMWARE_HOST} or die 'Need variable VMWARE_HOST';
        $remote_vmm = "-c esx://$user\@$host/?no_verify=1\\&authfile=$libvirtauthfilename ";
        $bmwqemu::vars{VMWARE_REMOTE_VMM} = $remote_vmm;
    }

    my $instance = $self->instance;
    my $xmldata = $self->{domainxml}->toString(2);
    my $xmlfilename = "/var/lib/libvirt/images/" . $self->name . ".xml";
    my $ret;
    bmwqemu::diag("Creating libvirt configuration file $xmlfilename:\n$xmldata");
    my ($ssh, $chan) = $self->backend->run_ssh("cat > $xmlfilename", $self->get_ssh_credentials(), keep_open => 1);
    # scp_put is unfortunately unreliable (RT#61771)
    $chan->write($xmldata) || $ssh->die_with_error();
    $chan->send_eof();
    $chan->close();

    # shut down possibly running previous test (just to be sure) - ignore errors
    # just making sure we continue after the command finished
    my $ignore = ' |& grep -v "\(failed to get domain\|Domain not found\)"';
    $self->run_cmd("virsh $remote_vmm destroy " . $self->name . $ignore);
    $self->run_cmd("virsh $remote_vmm undefine --snapshots-metadata " . $self->name . $ignore);

    # define the new domain
    $self->run_cmd("virsh $remote_vmm define $xmlfilename") && die "virsh define failed";
    if ($self->vmm_family eq 'vmware') {
        my $vmx = sprintf('/vmfs/volumes/%s/openQA/%s.vmx', $bmwqemu::vars{VMWARE_DATASTORE} // 'datastore1', $self->name);

        # set default boot delay
        $self->run_cmd(qq{echo 'bios.bootDelay = "10000"' >> $vmx}, domain => 'sshVMwareServer');

        # inject cloud init metadata and userdata required for the image if there are any
        my $ci_meta = $bmwqemu::vars{CLOUD_INIT_META};
        my $ci_user = $bmwqemu::vars{CLOUD_INIT_USER};
        my $ci_encoding = $bmwqemu::vars{CLOUD_INIT_ENCODING};

        if ($ci_meta && $ci_user && $ci_encoding) {
            $self->run_cmd(qq{echo 'guestinfo.metadata = "$ci_meta"' >> $vmx}, domain => 'sshVMwareServer');
            $self->run_cmd(qq{echo 'guestinfo.metadata.encoding = "$ci_encoding"' >> $vmx}, domain => 'sshVMwareServer');
            $self->run_cmd(qq{echo 'guestinfo.userdata = "$ci_user"' >> $vmx}, domain => 'sshVMwareServer');
            $self->run_cmd(qq{echo 'guestinfo.userdata.encoding = "$ci_encoding"' >> $vmx}, domain => 'sshVMwareServer');
        }
    }

    $ret = $self->run_cmd("virsh $remote_vmm start " . $self->name . ' 2> >(tee /tmp/os-autoinst-' . $self->name . '-stderr.log >&2)');
    bmwqemu::diag("Dump actually used libvirt configuration file " . ($ret ? "(broken)" : "(working)"));
    my $config = $self->get_cmd_output("virsh $remote_vmm dumpxml " . $self->name);
    die "virsh start failed: $ret\n\nvirsh domain XML:\n$config" if $ret;
    my $config_domain = Mojo::DOM->new($config)->at('domain');
    my $vm_id = $config_domain ? $config_domain->attr('id') : '';
    die "virsh domain XML does not specify VM ID which is required from VNC over WebSockets:\n$config" if !$vm_id && $bmwqemu::vars{VMWARE_VNC_OVER_WS};
    $bmwqemu::vars{VIRSH_VM_ID} = $vm_id;

    $self->backend->start_serial_grab($self->name);

    return;
}

sub attach_to_running ($self, $args = undef) {
    $args = {name => $args} unless ref $args;

    my $name = $args->{name};
    $self->name($name) if $name;
    $self->backend->start_serial_grab($self->name);

    # Setting SVIRT_KEEP_VM_RUNNING variable prevents destruction of a perhaps valuable VM
    # outside of openQA. Set 'stop_vm' argument should the VM be destroyed at the end.
    $bmwqemu::vars{SVIRT_KEEP_VM_RUNNING} = 1 unless $args->{stop_vm};
}

sub start_serial_grab ($self) { $self->backend->start_serial_grab($self->name) }

sub stop_serial_grab ($self, @) { $self->backend->stop_serial_grab($self->name) }


=head2 run_cmd

    $ret = $svirt->run_cmd($cmd [, domain => 'default'] [, wantarray => 0 ]);

With C<<wantarray => 1 >> you will receive a list containing I<exitcode>,
I<stdout> and I<stderr>.

    ($ret, $stdout, $stderr) = $svirt->run_cmd($cmd, wantarray => 1);


Execute the command via SSH on given C<domain> by default it is the host given
on C<activate()>, normally the libvirt host defined via C<VIRSH_HOSTNAME>,
C<VIRSH_USERNAME> and C<VIRSH_PASSWORD>.
The second domain B<sshVMwareServer> is available if C<VIRSH_VMM_FAMILY> is
B<vmware> and defined via C<VMWARE_HOST>, C<VMWARE_PASSWORD> and 'root' as
username.
For further arguments see C<baseclass:run_ssh_cmd()>.
=cut
sub run_cmd ($self, $cmd, %args) {
    my %credentials = $self->get_ssh_credentials($args{domain});
    delete $args{domain};
    return $self->backend->run_ssh_cmd($cmd, %credentials, %args);
}

=head2 get_cmd_output

    $stdout = $svirt->get_cmd_output($cmd , $args = {domain => 'default', wantarray => 0});

With C<<wantarray => 1>> the function will return a reference to a list which
contains I<stdout> and I<stderr>.
This function is B<deprecated>, you should use C<<$svirt->run_cmd()>> instead.
=cut
sub get_cmd_output ($self, $cmd, $args = {}) {
    my (undef, $stdout, $stderr) = $self->backend->run_ssh_cmd($cmd, $self->get_ssh_credentials($args->{domain}), wantarray => 1);
    return $args->{wantarray} ? [$stdout, $stderr] : $stdout;
}

1;
