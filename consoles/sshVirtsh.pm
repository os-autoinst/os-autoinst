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

# Indents every non-empty line of a shell snippet so it can be interpolated into a
# surrounding script; also strips the trailing newline the here-doc would duplicate
sub _indent ($script, $level = 0) {
    chomp $script;
    return $script unless $level;
    my $indentation = '    ' x $level;
    $script =~ s/^(?=.)/$indentation/mg;
    return $script;
}

# The name of the temporary file an image is copied to before it is renamed into place.
# It contains the VM name so leftovers of a crashed job are removed by the usual
# `rm -f <datastore>/*<name>*` cleanup.
sub _tmp_image_path ($dest, $name) { "$dest.$name.part" }

# The name of the file recording which published checksum an image was verified against.
sub _verified_record_path ($dest) { "$dest.verified" }

# The digest the job expects an image to have, or undef when it published none. Follows
# the CHECKSUM_<VAR> convention of the test distribution: the expected value for the image
# named by the job variable <VAR> is in CHECKSUM_<VAR>, e.g. CHECKSUM_ISO for ISO.
sub _expected_checksum ($file_basename) {
    for my $checksum_var (sort grep { /^CHECKSUM_/ } keys %bmwqemu::vars) {
        my $image = $bmwqemu::vars{$checksum_var =~ s/^CHECKSUM_//r};
        next unless defined $image && basename($image) eq $file_basename;
        my $checksum = $bmwqemu::vars{$checksum_var} // next;
        # the value is interpolated into a shell script, so only a plain digest is usable
        return lc $checksum if $checksum =~ /^(?:[0-9a-f]{64}|[0-9a-f]{128})$/i;
        bmwqemu::diag "Ignoring $checksum_var, '$checksum' is not a SHA-256 or SHA-512 digest";
    }
    return undef;
}

# Leaves the digest of the given file in $_digest so the caller can compare it against the
# expected one, and a description of everything computed in $_digests so a mismatch can
# say which algorithms were tried. A published checksum is either a SHA-256, a full
# SHA-512 or a SHA-512 truncated to its first 64 characters, and the three are
# indistinguishable by length alone, so a 64 character checksum is first tried as SHA-256
# - the same order the test distribution's verify_checksum() uses. That costs a second
# read of the image whenever the checksum turns out to be a truncated SHA-512.
sub _digest_script ($file, $checksum) {
    return <<~"EOF" if length($checksum) == 128;
    _digest=\$(sha512sum "$file" | awk '{print \$1}')
    _digests="SHA-512 \$_digest"
    EOF
    return <<~"EOF";
    _digest=\$(sha256sum "$file" | awk '{print \$1}')
    _digests="SHA-256 \$_digest"
    if [ "\$_digest" != "$checksum" ]; then
        _digest=\$(sha512sum "$file" | awk '{print \$1}' | cut -c1-64)
        _digests="\$_digests, SHA-512 truncated \$_digest"
    fi
    EOF
}

# VMFS offers no atomic copy, so images are copied to a temporary file which is renamed
# only once the copy succeeded. A rename within a datastore is a metadata operation,
# hence the destination is either absent or a complete image. That way a half-copied
# image can never be picked up by a concurrent job or by a later job after this one died
# in the middle of the copy - and it is never visible to a checksum verification either.
# When the job published a checksum for the image, the temporary file is verified against
# it before the rename, so a corrupt image is never published in the first place. The
# temporary file is held by no VM, hence reading it cannot run into the VMFS lock which
# makes verifying an image already in use impossible.
# Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
sub _atomic_copy_script ($source, $dest, $tmp, $checksum = undef) {
    my $copy = <<~"EOF";
    if ! cp "$source" "$tmp"; then
        rm -f "$tmp"
        echo "Unable to copy $source to $dest"
        exit 1
    fi
    EOF
    my $verify = !$checksum ? '' : _digest_script($tmp, $checksum) . <<~"EOF";
    if [ "\$_digest" != "$checksum" ]; then
        rm -f "$tmp"
        echo "Checksum mismatch for $source, expected $checksum but computed \$_digests"
        exit 1
    fi
    echo "Verified $source against its published checksum"
    EOF
    return $copy . $verify . <<~"EOF" . _record_verified_script($dest, $checksum) . qq{echo "Copied $source to $dest"\n};
    if ! mv "$tmp" "$dest"; then
        rm -f "$tmp"
        echo "Unable to publish $dest"
        exit 1
    fi
    EOF
}

# Same as _atomic_copy_script() but decompressing the source on the fly. The decompressed
# image inherits the checksum of the compressed asset it was produced from, as that is
# what a later job publishes for it.
sub _atomic_decompress_script ($source, $dest, $tmp, $checksum = undef) {
    my $record = _indent(_record_verified_script($dest, $checksum), 1);
    return <<~"EOF";
    if xz --decompress --stdout "$source" > "$tmp" && mv "$tmp" "$dest"; then
    $record
        echo "Decompressed $source to $dest"
    else
        rm -f "$tmp"
        echo "Unable to decompress $source to $dest"
        exit 1
    fi
    EOF
}

# Records which published checksum a freshly published image was verified against. An
# unverified copy instead drops the record of an earlier job, which would otherwise vouch
# for an image it does not describe.
sub _record_verified_script ($dest, $checksum = undef) {
    my $record = _verified_record_path($dest);
    return $checksum ? qq{echo "$checksum" > "$record"\n} : qq{rm -f "$record"\n};
}

# An image already in the datastore is only usable when it was verified against the
# checksum this job publishes for it. Re-reading a multi-gigabyte image to find that out
# is not an option - it is exactly what producing the image here avoids, and VMFS locks an
# image exclusively while another job's VM runs from it - so the checksum it was verified
# against is recorded next to it at publish time and only that record is read back.
# Without it an image which an earlier job published unverified, or against a different
# checksum, is booted on trust: the presence check alone cannot tell a good image from a
# corrupt one which happens to be there already.
# Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
sub _verified_script ($checksum = undef) {
    return qq{_verified() { test -e "\$1"; }\n} unless $checksum;
    my $record = _verified_record_path('$1');
    return <<~"EOF";
    _verified() {
        test -e "\$1" || return 1
        test "\$(cat "$record" 2>/dev/null)" = "$checksum"
    }
    EOF
}

# An image the datastore cannot vouch for is not silently overwritten with a fresh copy.
# Whatever put it there - a corrupt transfer, a job killed before this change existed, an
# asset republished under the same name - is an anomaly, and replacing it would hide it and
# leave the next job to run into it again. Fail loudly instead and name the file to remove,
# which is also the one-off cleanup an existing datastore needs after deploying this.
# Only relevant for a job which publishes a checksum, as there is nothing to vouch for
# otherwise; must run behind the copy marker, so that an image being published right now is
# waited for rather than rejected in the moment between its rename and its record.
# Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
sub _reject_unverified_script ($dest, $checksum = undef) {
    return '' unless $checksum;
    return <<~"EOF";
    if [ -e "$dest" ]; then
        echo "$dest is not verified against $checksum, remove it from the datastore to have it copied again"
        exit 1
    fi
    EOF
}

# The name of the marker directory a job claims to announce it is copying an image.
sub _copy_marker_path ($dest) { "$dest.copying" }

# Only one job should transfer a multi-gigabyte image. The right to copy it is claimed
# with `mkdir`, which either creates the marker or fails, so exactly one of the jobs
# arriving together copies while the others wait for the image to appear. Watching for a
# temporary file to grow would not be enough on its own: the scheduler dispatches the jobs
# of a build in one batch, hence they typically all arrive before any of them wrote a
# single byte, and every one of them would start its own copy.
# The marker is an optimization, never a correctness requirement, as every job copies to
# its own temporary file and publishes by rename. A marker whose owner stopped making
# progress - a job which died in the middle of a copy - is therefore taken over rather
# than waited on forever, and the worst case of taking it over too early is that an image
# is transferred twice.
# Leaves 1 in $_claimed if this job is the one which has to copy, and releases the marker
# on exit, including the failure exits of the copy itself.
# Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
sub _claim_copy_script ($dest, $marker, $interval = 10, $stall_timeout = 300) {
    return <<~"EOF";
    _claimed=''
    trap 'test -z "\$_claimed" || rm -rf "$marker"' EXIT
    _copied=-1
    _stalled=0
    until _verified "$dest"; do
        if mkdir "$marker" 2>/dev/null; then
            _claimed=1
            break
        fi
        _size=\$(ls -l "$dest".*.part 2>/dev/null | awk '{size += \$5} END {print size + 0}')
        if [ "\$_size" -gt "\$_copied" ]; then
            _copied=\$_size
            _stalled=0
        else
            _stalled=\$((_stalled + $interval))
        fi
        if [ "\$_stalled" -ge $stall_timeout ]; then
            echo "No progress on $dest for ${stall_timeout}s, taking the copy over"
            rm -rf "$marker"
            _stalled=0
            continue
        fi
        echo "Waiting for another job to copy $dest (\$_size bytes so far)"
        sleep $interval
    done
    EOF
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
    my $dest_xz = "$dest_image.xz";
    my $name = $self->name;
    # a checksum is published for the asset as it is named in the job, which is the
    # compressed file on the xz path and the image itself otherwise
    my $checksum = _expected_checksum($basefile);
    # check image is present and was verified against that checksum; copies and the
    # decompression are done atomically so the presence of the destination already implies
    # it is complete. Claiming the final destination also covers the compressed file on the
    # xz path, as only the job which has to produce the image gets that far.
    # Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
    my $verified = _indent(_verified_script($checksum));
    my $claim = _indent(_claim_copy_script($dest_image, _copy_marker_path($dest_image)));
    my $reject_image = _indent(_reject_unverified_script($dest_image, $checksum), 1);
    my $reject_xz = _indent(_reject_unverified_script($dest_xz, $checksum), 3);
    my $copy_xz = _indent(_atomic_copy_script($file_origin, $dest_xz, _tmp_image_path($dest_xz, $name), $checksum), 3);
    my $decompress = _indent(_atomic_decompress_script($dest_xz, $dest_image, _tmp_image_path($dest_image, $name), $checksum), 2);
    my $copy_image = _indent(_atomic_copy_script($file_origin, $dest_image, _tmp_image_path($dest_image, $name), $checksum), 2);
    my $cmd = <<~"EOF";
    $debug
    input_file="$input_file"
    $verified
    $claim
    if _verified "$dest_image"; then
        echo "VMware image $dest_image ready"
    else
    $reject_image
        if [ "\${input_file##*.}" = "xz" ]; then
            if ! _verified "$dest_xz"; then
    $reject_xz
    $copy_xz
            fi
    $decompress
        else
    $copy_image
        fi
    fi
    echo "Done: origin:" $file_origin* " ; dest.:" $dest_image*
    EOF

    my $ret = $self->run_cmd($cmd, domain => 'sshVMwareServer');
    croak "Error on VMware image $input_file preparation." if $ret;
    return $dest_image;
}

sub _copy_image_vmware ($self, $name, $backingfile, $file_basename, %args) {
    my $vmware_openqa_datastore = $args{vmware_openqa_datastore};
    my $vmware_disk_path = $args{vmware_disk_path};
    my $vmware_disk_path_thinfile = $args{vmware_disk_path_thinfile};
    my $copy_timeout = $args{copy_timeout} // 600;

    # Copy the image from the NFS datastore unless it is already present. The copy is
    # atomic, so an existing destination is always a complete image, and jobs arriving
    # together agree on a single copier instead of guessing from a process list whether
    # someone else is copying it there right now.
    my $nfs_dir = $backingfile ? 'hdd' : 'iso';
    my $vmware_nfs_datastore = $bmwqemu::vars{VMWARE_NFS_DATASTORE} or die 'Need variable VMWARE_NFS_DATASTORE';
    # cmd debugging activable by setting VMWARE_NFS_DATASTORE_DEBUG=1
    my $ds_debug = ($bmwqemu::vars{VMWARE_NFS_DATASTORE_DEBUG} // 0) ? 'set -x;' : '';
    my $dest_image = "$vmware_openqa_datastore$file_basename";
    my $file_origin = "/vmfs/volumes/$vmware_nfs_datastore/$nfs_dir/$file_basename";
    my $checksum = _expected_checksum($file_basename);
    my $verified = _indent(_verified_script($checksum));
    my $claim = _indent(_claim_copy_script($dest_image, _copy_marker_path($dest_image)));
    my $reject_image = _indent(_reject_unverified_script($dest_image, $checksum), 1);
    my $copy_image = _indent(_atomic_copy_script($file_origin, $dest_image, _tmp_image_path($dest_image, $name), $checksum), 1);
    # Note: This script must be in POSIX shell as ESXi uses busybox for /bin/sh
    my $cmd = <<~"EOF";
    $ds_debug
    $verified
    $claim
    if _verified "$dest_image"; then
        echo "VMware image $dest_image is already present and verified"
    else
    $reject_image
    $copy_image
    fi
    EOF
    my $retval = $self->run_cmd($cmd, domain => 'sshVMwareServer', timeout => $copy_timeout);
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

sub _copy_image_to_vm_host ($self, $args, $vmware_openqa_datastore, %opts) {
    my $file = $opts{file};
    my $name = $opts{name};
    my $basedir = $opts{basedir};
    my $cdrom = $opts{cdrom};

    # Copy image to VM host
    die 'No file given' unless $args->{file};
    my $file_basename = basename($args->{file});
    my $backingfile = $args->{backingfile};
    my $vmware_disk_path = $vmware_openqa_datastore . $file_basename;
    my $vmware_disk_path_thinfile = $vmware_disk_path =~ s/\.vmdk/_${name}_thinfile\.vmdk/r;
    if ($cdrom || $backingfile) {
        if ($self->vmm_family eq 'vmware') {
            $self->_copy_image_vmware(
                $name, $backingfile, $file_basename,
                vmware_openqa_datastore => $vmware_openqa_datastore,
                vmware_disk_path => $vmware_disk_path,
                vmware_disk_path_thinfile => $vmware_disk_path_thinfile
            );
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
        $file = $self->_copy_image_to_vm_host(
            $args, $vmware_openqa_datastore,
            file => $file,
            name => $name,
            basedir => $basedir,
            cdrom => $cdrom
        );
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

## no critic (Subroutines::ProhibitExcessComplexity)
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
