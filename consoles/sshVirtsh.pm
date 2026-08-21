# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshVirtsh;

use Mojo::Base 'consoles::sshXtermVt', -signatures;
use autodie ':all';
require IPC::System::Simple;
use XML::LibXML;
use Feature::Compat::Try;
use File::Temp 'tempfile';
use File::Basename;
use File::Which;
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Mojo::Util;
use Time::Seconds;
use Carp 'croak';
use backend::svirt;

has [qw(instance name vmm_family vmm_type vmm_firmware)];

sub new ($class, $testapi_console = undef, $args = {}) {
    my $self = $class->SUPER::new($testapi_console, $args);

    $self->instance($bmwqemu::vars{VIRSH_INSTANCE} // 1);
    # default name
    $self->name('openQA-SUT-' . $self->instance);
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
    $features->appendChild($doc->createElement('acpi')) if ($bmwqemu::vars{ARCH} // '') ne 's390x';
    $features->appendChild($doc->createElement($_)) for qw(apic pae);

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

    if ($bmwqemu::vars{UEFI} and $bmwqemu::vars{ARCH} eq 'x86_64' and $bmwqemu::vars{VIRSH_VMM_FAMILY} ne 'hyperv' and $bmwqemu::vars{VIRSH_VMM_FAMILY} ne 'vmware') {
        foreach my $firmware (@bmwqemu::ovmf_locations) {
            if (!$self->run_cmd("test -e $firmware")) {
                $elem = $doc->createElement('loader');
                $elem->appendTextNode($firmware);
                $os->appendChild($elem);
                last;
            }
        }
        if (!$bmwqemu::vars{UEFI}) {
            # We know this won't go well.
            my $virsh_hostname = $bmwqemu::vars{VIRSH_HOSTNAME} // '';    # uncoverable statement
            die "No UEFI firmware can be found on hypervisor '$virsh_hostname'. Please specify UEFI or install an appropriate package."; # uncoverable statement
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
            foreach my $key (keys %$tag) {
                $elem->setAttribute($key => $tag->{$key});
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

sub add_usb_hub ($self) {
    my $doc = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $controller = $doc->createElement('controller');
    $controller->setAttribute(type => 'usb');
    $controller->setAttribute(index => '0');
    $controller->setAttribute(ports => '8');
    $devices->appendChild($controller);
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

sub _free_lock_forcefully ($self) {
    bmwqemu::diag('Lock is still held. Attempting active recovery by force-killing lingering processes for ' . $self->name);
    $self->run_cmd(sprintf "%s destroy '%s'", backend::svirt::virsh, $self->name);
    $self->run_cmd(sprintf "pkill -9 -f '%s'", $self->name);
}

sub _do_create_disk ($self, $file, $size, $args = undef) {
    my $bucket = 5;
    my $active_recovery_attempted = 0;
    my @cmd = "qemu-img create '$file' -f qcow2";
    push @cmd, $args->{additional_args} if $args->{additional_args};
    push @cmd, $size;

    # Avoid qemu-img's failure to get a write lock to be the reason for a job to fail
    while (1) {
        my ($ret, $stdout, $stderr) = $self->run_cmd((join ' ', @cmd), wantarray => 1);
        if (($stderr // '') =~ /lock/i) {
            $bucket--;
            if (!$bucket) {
                if (!$active_recovery_attempted) {
                    $self->_free_lock_forcefully;
                    $active_recovery_attempted = 1;
                    $bucket = 2;    # allow 2 more attempts after active recovery
                }
                else {
                    die 'Too many attempts to create disk';
                }
            }
            bmwqemu::diag("Resource is still not free, waiting a bit more. $bucket attempts left");
            sleep 5;
            next;
        }
        last unless $ret;
    }
}

sub _create_disk ($self, $args, $vmware_openqa_datastore, $file, $name, $basedir) {
    my $size = $args->{size} || '20G';
    if ($self->vmm_family eq 'vmware') {
        my $vmware_disk_path = $vmware_openqa_datastore . $file;
        # Power VM off, delete it's disk image, and create it again.
        # Poll the power state until the VM is *really* turned off.
        my $cmd =
          "( set -x; vmid=\$(vim-cmd vmsvc/getallvms | awk \'/$name/ { print \$1 }\');" .
          'if [ $vmid ]; then ' .
          'vim-cmd vmsvc/power.off $vmid;' .
          'for i in $(seq 1 10); do vim-cmd vmsvc/power.getstate $vmid | grep -q "Powered off" && break; sleep 1; done;' .
          'vim-cmd vmsvc/destroy $vmid;' .
          "else rm -f $name*;" .
          'fi;' .
          "vmkfstools -v1 -U $vmware_disk_path;" .
          "vmkfstools -v1 -c $size --diskformat thin $vmware_disk_path; sleep 10 ) 2>&1";
        my $retval = $self->run_cmd($cmd, domain => 'sshVMwareServer');
        die "Can't create VMware image $vmware_disk_path" if $retval;
    }
    else {
        $file = $basedir . $file;
        $self->_do_create_disk($file, $size);
    }
    return $file;
}

# Verifies that vmware image is present in the host datastore, otherwhise copies from input
sub provide_image_vmware_in_ds ($self, $input_file, $vmware_openqa_datastore, %args) {
    my $nfs_dir = ($args{backingfile}) ? 'hdd' : 'iso';
    my $vmware_nfs_datastore = $bmwqemu::vars{VMWARE_NFS_DATASTORE} or die 'Need variable VMWARE_NFS_DATASTORE';
    my $debug = ($bmwqemu::vars{VMWARE_NFS_DATASTORE_DEBUG} // 0) ? 'set -x;' : '';
    my $base_dir = $bmwqemu::vars{VIRSH_OPENQA_BASEDIR} // '/vmfs/volumes';
    my $basefile = basename($input_file);
    # expected name of uncompressed image
    my $baseimage = basename($input_file) =~ s/\.xz$//r;
    my $dest_image = "$vmware_openqa_datastore/${baseimage}";
    # Use the standard folder for an input file without full path
    my $file_origin = ($input_file eq $basefile) ? "$base_dir/$vmware_nfs_datastore/$nfs_dir/$basefile" : $input_file;
    # check image is present
    # Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
    my $cmd = <<~"EOF";
    $debug
    input_file="$input_file"
    if [ -e "$dest_image" ]; then
        echo "Waiting while $input_file is loading:"
        while ps -v | grep -F -e "$baseimage" -e "$basefile" | grep -v grep
            do sleep 5; done
        echo "VMware image $dest_image ready"
    elif [ "\${input_file##*.}" = "xz" ]; then
        if [ -e "$dest_image.xz" ] || cp "$file_origin" "$vmware_openqa_datastore"; then
            xz --decompress --keep "$dest_image.xz"
        fi
    else
        cp "$file_origin" "$vmware_openqa_datastore"
    fi
    echo "Done: origin:" $file_origin* " ; dest.:" $dest_image*
    EOF

    my $ret = $self->run_cmd($cmd, domain => 'sshVMwareServer');
    croak "Error on VMware image $input_file preparation." if $ret;
    return $dest_image;
}

# Returns the checksum an image is expected to have, or undef if the job does
# not carry one for it. The expected value is in the job variable CHECKSUM_<VAR>
# belonging to the <VAR> that names the image, e.g. CHECKSUM_ISO for ISO. This
# is the same convention the test distribution's verify_checksum() follows.
#   - $file_basename: file name of the image
sub _expected_checksum ($file_basename) {
    for my $checksum_var (sort grep { /^CHECKSUM_/ } keys %bmwqemu::vars) {
        my $image = $bmwqemu::vars{$checksum_var =~ s/^CHECKSUM_//r};
        next unless defined $image && basename($image) eq $file_basename;
        # a variable that is set but carries no value means the job has no
        # checksum for the image, the same as not setting it at all
        my $checksum = $bmwqemu::vars{$checksum_var} // '';
        next unless length $checksum;
        # the value ends up in a shell script, so only a plain digest is usable
        return $checksum if $checksum =~ /^[0-9a-fA-F]+$/;
        bmwqemu::diag "Ignoring $checksum_var, '$checksum' is not a checksum";
    }
    return undef;
}

sub _copy_image_vmware ($self, $name, $backingfile, $file_basename, $vmware_openqa_datastore, $vmware_disk_path, $vmware_disk_path_thinfile, $copy_timeout = 600) {
    # Provide the image in the host datastore, copying it from the NFS datastore
    # when it is missing or does not match the source. The copy is published by
    # renaming a fully verified temporary file, so an interrupted job can never
    # leave a truncated image behind for the next job to boot from.
    my $nfs_dir = $backingfile ? 'hdd' : 'iso';
    my $vmware_nfs_datastore = $bmwqemu::vars{VMWARE_NFS_DATASTORE} or die 'Need variable VMWARE_NFS_DATASTORE';
    # cmd debugging activable by setting VMWARE_NFS_DATASTORE_DEBUG=1
    my $debug = ($bmwqemu::vars{VMWARE_NFS_DATASTORE_DEBUG} // 0) ? 'set -x;' : '';
    my $base_dir = $bmwqemu::vars{VIRSH_OPENQA_BASEDIR} // '/vmfs/volumes';
    my $source = "$base_dir/$vmware_nfs_datastore/$nfs_dir/$file_basename";
    my $dest = "$vmware_openqa_datastore$file_basename";
    # holds the checksum $dest was verified against when it was published, so a
    # later job can tell whether the cached image is the one it expects without
    # reading it
    my $stamp = "$dest.openqa-checksum";
    # unique per job, so no VM ever has it attached and it is never VMFS-locked
    my $temp = "$dest.tmp.$name";
    my $wait_timeout = $copy_timeout;
    my $checksum = _expected_checksum($file_basename) // '';
    # Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh.
    # It must only ever read $dest while `touch` proves that no VM has it open:
    # a VM booted from that image holds a VMFS lock which makes open() fail with
    # EBUSY, while ls, test and touch keep working.
    my $cmd = <<~"EOF";
    $debug
    checksum="$checksum"

    # size in bytes, empty if it cannot be determined
    fsize() { ls -l "\$1" 2>/dev/null | awk '{print \$5}'; }

    # Whether an image matches the expected checksum, mirroring verify_checksum()
    # of the test distribution: SHA-256 first, SHA-512 only as a fallback and
    # accepted in full as well as truncated to the length of the expected value.
    checksum_matches() {
        [ -z "\$checksum" ] && return 0
        [ "\$(sha256sum "\$1" | awk '{print \$1}')" = "\$checksum" ] && return 0
        case "\$(sha512sum "\$1" | awk '{print \$1}')" in "\$checksum"*) return 0 ;; esac
        return 1
    }

    source_size=\$(fsize "$source")

    # leftover of a copy this job slot did not finish previously
    rm -f "$temp"

    # Wait while another job copies the same image, that is while its temporary
    # file still grows. A dead copier's file stops growing and we take over.
    waited=0
    while [ \$waited -lt $wait_timeout ]; do
        growing=''
        for other in $dest.tmp.*; do
            [ -e "\$other" ] || continue
            before=\$(fsize "\$other")
            sleep 5
            waited=\$((waited + 5))
            after=\$(fsize "\$other")
            [ "\$before" = "\$after" ] || growing=1
        done
        [ -n "\$growing" ] || break
        echo "Another job is copying $file_basename, waited \${waited}s so far"
    done

    if [ -e "$dest" ]; then
        dest_size=\$(fsize "$dest")
        reuse=''
        if [ -z "\$source_size" ]; then
            reuse="source $source is not available"
        elif [ -z "\$dest_size" ]; then
            reuse='its size cannot be determined'
        elif [ "\$dest_size" != "\$source_size" ]; then
            echo "WARNING: $dest is \$dest_size bytes but $source is \$source_size, replacing it"
        elif [ -z "\$checksum" ]; then
            reuse='the job gives no checksum and the size matches the source'
        elif [ "\$(cat "$stamp" 2>/dev/null)" = "\$checksum" ]; then
            reuse='it was published for this checksum'
        elif [ -e "$stamp" ]; then
            echo "WARNING: $dest was published for another checksum, replacing it"
        elif ! touch "$dest" 2>/dev/null; then
            # No publish record, but a VM has it open, so another job is already
            # running off it and reading it to verify would fail anyway.
            reuse='it is in use by another VM and cannot be verified'
        elif checksum_matches "$dest"; then
            # Adopt an image cached before checksums were recorded
            echo "\$checksum" > "$stamp"
            reuse='its checksum has just been verified'
        elif ! touch "$dest" 2>/dev/null; then
            reuse='a VM started using it while it was being verified'
        else
            echo "WARNING: checksum of $dest does not match \$checksum, replacing it"
        fi
        if [ -n "\$reuse" ]; then
            echo "Reusing $dest, \$reuse"
            exit 0
        fi
    fi

    if [ -z "\$source_size" ]; then
        echo "ERROR: cannot determine size of $source"
        exit 1
    fi

    # Copy to a temporary file and only keep it once it is complete and matches
    # the checksum, so a bad image can never take the name of the real one.
    attempt=0
    while true; do
        attempt=\$((attempt + 1))
        error=''
        if ! cp "$source" "$temp"; then
            error="copying $source failed"
        elif [ "\$(fsize "$temp")" != "\$source_size" ]; then
            error="the copy of $source is not \$source_size bytes"
        elif ! checksum_matches "$temp"; then
            error="the copy of $source does not match checksum \$checksum"
        else
            break
        fi
        rm -f "$temp"
        if [ \$attempt -ge 2 ]; then
            echo "ERROR: \$error"
            exit 1
        fi
        echo "WARNING: \$error, copying again"
    done

    # Another job may have published the same image while we were copying. Do
    # not replace it, some VM may already be running off it.
    if [ "\$(fsize "$dest")" = "\$source_size" ] && [ "\$(cat "$stamp" 2>/dev/null)" = "\$checksum" ]; then
        rm -f "$temp"
        echo "$dest has been published by another job in the meantime"
        exit 0
    fi

    # Publish atomically. Replacing an image some VM still has attached fails
    # with EBUSY, so retry a while and leave it to a later job if it persists.
    attempt=0
    while ! mv -f "$temp" "$dest"; do
        attempt=\$((attempt + 1))
        if [ \$attempt -ge 6 ]; then
            rm -f "$temp"
            echo "ERROR: cannot replace $dest, it is still in use"
            exit 1
        fi
        echo "$dest is in use, retrying to replace it (attempt \$attempt)"
        sleep 10
    done
    # The old record must not outlive the image it described
    rm -f "$stamp"
    [ -n "\$checksum" ] && echo "\$checksum" > "$stamp"
    echo "Published $dest, \$source_size bytes"
    EOF

    # budget for waiting on another job, two copy attempts and hashing each copy
    my $retval = $self->run_cmd($cmd, domain => 'sshVMwareServer', timeout => $wait_timeout + 4 * $copy_timeout);
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
    die q{Can't create thin VMware image} if $retval;
}

sub _copy_nvram_vmware ($self, $name, $vmware_openqa_datastore, $vmware_disk_path) {
    # If the nvram exists in the source vmx file, then copy the source file as destination nvram.
    my $vmware_vmx_path = $vmware_disk_path =~ s/\.vmdk/\.vmx/r;
    my $vmware_nvram_path = $vmware_disk_path =~ s/\.vmdk/\.nvram/r;
    my $cmd =
      "set -x; if [ -e $vmware_vmx_path ] && [ -e $vmware_nvram_path ]; then " .
      "cp -f $vmware_nvram_path ${vmware_openqa_datastore}${name}.nvram; fi;";
    my $retval = $self->run_cmd($cmd, domain => 'sshVMwareServer');
    die 'No nvram was set in the source vmx file' if $retval;
}

sub _system (@cmd) { system @cmd }    # uncoverable statement

sub _copy_image_else ($self, $file, $file_basename, $basedir) {
    my $download_timeout_s = ONE_MINUTE * ($bmwqemu::vars{SVIRT_ASSET_DOWNLOAD_TIMEOUT_M} // 15);
    my $inactivity_timeout_s = ONE_MINUTE * ($bmwqemu::vars{SVIRT_ASSET_DOWNLOAD_INACTIVITY_TIMEOUT_M} // 2.5);
    my $rsync_args = "--timeout='$inactivity_timeout_s' --stats --partial --append-verify -av";

    # utilize asset possibly cached by openQA worker, otherwise sync locally on svirt host (usually relying on NFS mount)
    if (($bmwqemu::vars{SVIRT_WORKER_CACHE} // 0) && -e $file_basename && defined which 'rsync') {
        my %c = $self->get_ssh_credentials;
        my $abs = path($file_basename)->to_abs;    # pass abs path so it can contain a colon
        bmwqemu::diag "Syncing '$file_basename' directly from worker host to $c{hostname}";
        _system("sshpass -p '$c{password}' rsync -e 'ssh -o StrictHostKeyChecking=no' $rsync_args '$abs' '$c{username}\@$c{hostname}:$basedir/$file_basename'");
    }
    else {
        $self->run_cmd_retrying_on_timeouts("rsync $rsync_args '$file' '$basedir/$file_basename'", timeout => $download_timeout_s) && die 'rsync failed';
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
            $self->_copy_nvram_vmware($name, $vmware_openqa_datastore, $vmware_disk_path) if ($backingfile);
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
        # $args->{size} is expected to be e.g. '20G' but internally we need it as integer
        my $size = ($args->{size} // 0) =~ tr/G//dr;
        # expected value in Bytes
        my (undef, $json) = $self->run_cmd("qemu-img info --force-share --output=json $args->{file}", wantarray => 1);
        my $image_vsize = decode_json($json)->{'virtual-size'};
        $size = (($size * 1024 * 1024 * 1024) <= $image_vsize) ? $image_vsize : $size . 'G';
        $self->_do_create_disk($file, $size, {additional_args => "-F qcow2 -b '$basedir/$file_basename'"});
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
    return (undef, undef);    # uncoverable statement
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

sub suspend ($self) {
    $self->run_cmd(backend::svirt::virsh() . ' suspend ' . $self->name) && die q{Can't suspend VM };
    bmwqemu::diag 'VM ' . $self->name . ' suspended';
}

sub resume ($self) {
    $self->run_cmd(backend::svirt::virsh() . ' resume ' . $self->name) && die q{Can't resume VM };
    bmwqemu::diag 'VM ' . $self->name . ' resumed';
}

sub get_remote_vmm ($self) { $bmwqemu::vars{VMWARE_REMOTE_VMM} // '' }

sub _encode_config ($self, $config, $key) {
    # expand path
    $config = "$bmwqemu::vars{CASEDIR}/data/$config";

    croak "'$config' either doesn't exist or it is not a file, update the $key variable" unless -f $config;

    my $content = Mojo::File->new($config)->slurp;
    my $gzip = Mojo::Util::gzip $content;
    my $encoded_config = Mojo::Util::b64_encode($gzip);
    $encoded_config =~ s/\R//g;

    return $encoded_config;
}

sub define_and_start ($self, %args) {
    $args{pre_cleanup} //= 1;
    my $remote_vmm;
    if ($self->vmm_family eq 'vmware') {
        my ($fh, $libvirtauthfilename) = File::Temp::tempfile('libvirtauth-XXXX', DIR => '/tmp/');

        # The libvirt esx driver supports connection over HTTP(S) only. When
        # asked to authenticate we provide the password via 'authfile'.
        $self->run_cmd(
            qq{cat > $libvirtauthfilename <<__END
[credentials-vmware]
username=} . ($bmwqemu::vars{VMWARE_USERNAME} or die 'Need variable VMWARE_USERNAME') . '
password=' . ($bmwqemu::vars{VMWARE_PASSWORD} or die 'Need variable VMWARE_PASSWORD') . '
[auth-esx-' . ($bmwqemu::vars{VMWARE_HOST} or die 'Need variable VMWARE_HOST') . ']
credentials=vmware
__END'
        );
        my $user = $bmwqemu::vars{VMWARE_USERNAME} or die 'Need variable VMWARE_USERNAME';
        my $host = $bmwqemu::vars{VMWARE_HOST} or die 'Need variable VMWARE_HOST';
        $remote_vmm = "-c esx://$user\@$host/?no_verify=1\\&authfile=$libvirtauthfilename ";
        $bmwqemu::vars{VMWARE_REMOTE_VMM} = $remote_vmm;
    }

    my $instance = $self->instance;
    my $xmldata = $self->{domainxml}->toString(2);
    my $xmlfilename = '/var/lib/libvirt/images/' . $self->name . '.xml';
    my $ret;
    bmwqemu::diag("Creating libvirt configuration file $xmlfilename:\n$xmldata");
    my ($ssh, $chan) = $self->backend->run_ssh("cat > $xmlfilename", $self->get_ssh_credentials(), keep_open => 1);
    # scp_put is unfortunately unreliable (RT#61771)
    $chan->write($xmldata) || $ssh->die_with_error();
    $chan->send_eof();
    $chan->close();

    # shut down possibly running previous test (just to be sure)
    $self->backend->do_stop_vm_svirt() if $args{pre_cleanup};

    # define the new domain
    my ($stdout, $stderr);
    ($ret, $stdout, $stderr) = $self->run_cmd(backend::svirt::virsh() . " define $xmlfilename", wantarray => 1);
    if ($ret) {
        $stderr =~ s/\s+$// if $stderr;
        die 'virsh define failed: ' . ($stderr || "exit code $ret");
    }
    if ($self->vmm_family eq 'vmware') {
        my $vmx = sprintf '/vmfs/volumes/%s/openQA/%s.vmx', $bmwqemu::vars{VMWARE_DATASTORE} // 'datastore1', $self->name;

        # set default boot delay
        $self->run_cmd(qq{echo 'bios.bootDelay = "10000"' >> $vmx}, domain => 'sshVMwareServer');
        # set default nvram
        my $nvram = $self->name . '.nvram';
        my $nvram_path = sprintf '/vmfs/volumes/%s/openQA/%s', $bmwqemu::vars{VMWARE_DATASTORE} // 'datastore1', $nvram;
        $ret = $self->run_cmd("test -e $nvram_path", domain => 'sshVMwareServer');
        $self->run_cmd(qq{echo 'nvram = "$nvram"' >> $vmx}, domain => 'sshVMwareServer') unless ($ret);
        # set virtual hardware version if specified
        if ($bmwqemu::vars{VMWARE_VM_HWVERSION}) {
            $self->run_cmd(qq{sed -i 's/^virtualHW.version = ".*"/virtualHW.version = "$bmwqemu::vars{VMWARE_VM_HWVERSION}"/' $vmx}, domain => 'sshVMwareServer');
        }

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

sub stop_vm ($self) {
    $self->backend->do_stop_vm_svirt();
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

sub run_cmd_retrying_on_timeouts ($self, $command, @args) {
    my $attempts = $bmwqemu::vars{SVIRT_ASSET_DOWNLOAD_ATTEMPTS} // 1;
    for (my $attempt = 1;;) {
        try {
            return $self->run_cmd($command, @args);
        }
        catch ($e) {
            # retry with a new ssh connection in case a timeout occurred
            die $e if (++$attempt > $attempts) || ($e !~ qr/LIBSSH2_ERROR_TIMEOUT/);
            bmwqemu::diag "Retrying '$command' after running into timeout (attempt $attempt of $attempts)";
            $self->backend->close_ssh_connections;
        }
    }
}

=head2 get_cmd_output

    $stdout = $svirt->get_cmd_output($cmd , $args = {domain => 'default', timeout => undef, wantarray => 0});

With C<<wantarray => 1>> the function returns an array reference containing I<stdout> and
I<stderr>.
This function is B<deprecated>, you should use C<<$svirt->run_cmd()>> instead.
=cut

sub get_cmd_output ($self, $cmd, $args = {}) {
    my (undef, $stdout, $stderr) = $self->backend->run_ssh_cmd($cmd, $self->get_ssh_credentials($args->{domain}), timeout => $args->{timeout}, wantarray => 1);
    return $args->{wantarray} ? [$stdout, $stderr] : $stdout;
}

1;
