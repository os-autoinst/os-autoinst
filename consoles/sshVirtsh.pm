# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package consoles::sshVirtsh;
use base 'consoles::sshXtermVt';
use strict;
use warnings;
use testapi qw/get_var get_required_var check_var set_var/;
require IPC::System::Simple;
use autodie qw(:all);
use XML::LibXML;
use File::Temp qw/tempfile/;

use Class::Accessor "antlers";
has instance   => (is => "rw", isa => "Num");
has name       => (is => "rw", isa => "Str");
has vmm_family => (is => "rw", isa => "Str");
has vmm_type   => (is => "rw", isa => "Str");

sub new {
    my ($class, $testapi_console, $args) = @_;
    my $self = $class->SUPER::new($testapi_console, $args);

    $self->instance(get_var('VIRSH_INSTANCE', 1));
    # default name
    $self->name("openQA-SUT-" . $self->instance);
    $self->vmm_family(get_var('VIRSH_VMM_FAMILY', 'kvm'));
    $self->vmm_type(get_var('VIRSH_VMM_TYPE', 'hvm'));
    $self->_init_xml();

    return $self;
}

sub activate {
    my ($self) = @_;

    my $args = $self->{args};

    my $hostname = $args->{hostname} || die('we need a hostname to ssh to');
    my $password = $args->{password};

    $self->{ssh} = $self->backend->new_ssh_connection(hostname => $hostname, password => $password);

    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};
    my $ssh_args        = $self->{args};

    my $sshcommand = $self->sshCommand($hostname);
    my $display    = $self->{DISPLAY};

    $sshcommand = "TERM=xterm " . $sshcommand;
    my $xterm_vt_cmd = "xterm-console";
    my $window_name  = "ssh:$testapi_console";
    eval { system("DISPLAY=$display $xterm_vt_cmd -title $window_name -e bash -c '$sshcommand' & echo \$!") };
    if (my $E = $@) {
        die "cant' start xterm on $display (err: $! retval: $?)";
    }
    # FIXME: assert_screen('xterm_password');
    sleep 3;
    $self->type_string({text => $password . "\n"});
}

sub _init_xml {
    my ($self, $args) = @_;

    $args ||= {};

    my $instance = $self->instance;
    my $doc      = $self->{domainxml} = XML::LibXML::Document->new;
    my $root     = $doc->createElement('domain');
    $root->setAttribute(type => $self->vmm_family);
    $doc->setDocumentElement($root);

    my $elem;
    $elem = $doc->createElement('name');
    $elem->appendTextNode($self->name);
    $root->appendChild($elem);

    $elem = $doc->createElement('description');
    $elem->appendTextNode("openQA Instance $instance");
    $root->appendChild($elem);

    $elem = $doc->createElement('memory');
    $elem->appendTextNode(get_required_var('QEMURAM'));
    $elem->setAttribute(unit => 'MiB');
    $root->appendChild($elem);

    $elem = $doc->createElement('vcpu');
    $elem->appendTextNode(get_required_var('QEMUCPUS'));
    $root->appendChild($elem);

    my $os = $doc->createElement('os');
    $root->appendChild($os);

    $elem = $doc->createElement('type');
    $elem->appendTextNode($self->vmm_type);
    $os->appendChild($elem);

    if (($self->vmm_family eq 'xen' and $self->vmm_type eq 'hvm') or get_var('UEFI')) {
        my $features = $doc->createElement('features');
        $root->appendChild($features);
        $elem = $doc->createElement('acpi');
        $features->appendChild($elem);
        $elem = $doc->createElement('apic');
        $features->appendChild($elem);
        if ($self->vmm_family eq 'xen' and $self->vmm_type eq 'hvm') {
            $elem = $doc->createElement('pae');
            $features->appendChild($elem);
        }
    }

    if ($self->vmm_family eq 'xen' and $self->vmm_type eq 'linux') {
        $elem = $doc->createElement('kernel');
        $elem->appendTextNode('/usr/lib/grub2/x86_64-xen/grub.xen');
        $os->appendChild($elem);
    }

    if (get_var('UEFI') and check_var('ARCH', 'x86_64') and !get_var('BIOS')) {
        # These are known locations for openSUSE and Fedora (respectively).
        my @known = ('/usr/share/qemu/ovmf-x86_64-ms.bin', '/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd');
        foreach my $firmware (@known) {
            if (!run_cmd($self, "test -e $firmware")) {
                set_var('BIOS', $firmware);
                $elem = $doc->createElement('loader');
                $elem->appendTextNode($firmware);
                $os->appendChild($elem);
                last;
            }
        }
        if (!get_var('BIOS')) {
            # We know this won't go well.
            die "No UEFI firmware can be found on hypervisor " . get_var('VIRSH_HOSTNAME') . "\n. Please specify BIOS or UEFI_BIOS or install an appropriate package.";
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
sub change_domain_element {
    # we don't know the number of arguments
    my $self = shift @_;

    my $doc  = $self->{domainxml};
    my $elem = $doc->getElementsByTagName('domain')->[0];

    while (@_ > 1) {
        my $parent   = $elem;
        my $tag_name = shift @_;
        $elem = $parent->getElementsByTagName($tag_name)->[0];
        # create it if not existant
        if (!$elem) {
            $elem = $doc->createElement($tag_name);
            $parent->appendChild($elem);
        }
    }
    my $tag = $_[0];
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

sub add_pty {
    my ($self, $args) = @_;

    my $doc     = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $console = $doc->createElement($args->{pty_dev} || 'console');
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
        $elem->setAttribute(mode    => 'bind');
        $elem->setAttribute(host    => '0.0.0.0');
        $elem->setAttribute(service => get_var('VMWARE_SERIAL_PORT'));
        $console->appendChild($elem);
    }

    return;
}

# this is an equivalent of QEMU's '-vnc' option for tests where we watch
# the system from boot on (e.g. JeOS)
sub add_vnc {
    my ($self, $args) = @_;

    my $doc     = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $graphics = $doc->createElement('graphics');
    $graphics->setAttribute(type        => 'vnc');
    $graphics->setAttribute(port        => $args->{port});
    $graphics->setAttribute(autoport    => 'no');
    $graphics->setAttribute(listen      => '0.0.0.0');
    $graphics->setAttribute(sharePolicy => 'force-shared');
    $graphics->setAttribute(passwd      => $testapi::password);
    $devices->appendChild($graphics);

    my $elem = $doc->createElement('listen');
    $elem->setAttribute(type    => 'address');
    $elem->setAttribute(address => '0.0.0.0');
    $graphics->appendChild($elem);

    return;
}

sub add_input {
    my ($self, $args) = @_;

    my $doc     = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $input = $doc->createElement('input');
    $input->setAttribute(type => $args->{type});
    $input->setAttribute(bus  => $args->{bus});
    $devices->appendChild($input);

    return;
}

# network stuff
sub add_interface {
    my ($self, $args) = @_;

    my $doc     = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $type      = delete $args->{type};
    my $interface = $doc->createElement('interface');
    $interface->setAttribute(type => $type);
    $devices->appendChild($interface);

    for my $key (keys %$args) {
        my $elem  = $doc->createElement($key);
        my $value = $args->{$key};
        for my $attr (keys %$value) {
            $elem->setAttribute($attr => $value->{$attr});
        }
        $interface->appendChild($elem);
    }

    return;
}

sub add_disk {
    my ($self, $args) = @_;

    my $file = $args->{file} || "/var/lib/libvirt/images/" . $self->name . ".img";

    if ($args->{create}) {
        my $size = $args->{size} || '4G';
        my $chan = $self->{ssh}->channel();
        my $ret  = $chan->exec("qemu-img create $file $size -f qcow2");
        bmwqemu::diag $_ while <$chan>;
        $chan->close();
        die "qemu-img create failed" if $chan->exit_status();
    }

    my $doc     = $self->{domainxml};
    my $devices = $self->{devices_element};

    my $disk = $doc->createElement('disk');
    $disk->setAttribute(type => 'file');
    if ($args->{cdrom}) {
        $disk->setAttribute(device => 'cdrom');
    }
    else {
        $disk->setAttribute(device => 'disk');
    }
    $devices->appendChild($disk);

    my $elem;

    # there's no <driver> property on VMware
    if ($self->vmm_family ne 'vmware') {
        $elem = $doc->createElement('driver');
        $elem->setAttribute(name => 'qemu');
        if ($args->{cdrom}) {
            $elem->setAttribute(type => 'raw');
        }
        else {
            $elem->setAttribute(type => 'qcow2');
        }
        $disk->appendChild($elem);
    }

    my $dev_type;
    my $bus_type;
    if ($self->vmm_family eq 'xen' || $self->vmm_family eq 'vmware') {
        if ($self->vmm_type eq 'hvm') {
            if ($args->{cdrom}) {
                $dev_type = 'hdb';
            }
            else {
                $dev_type = 'hda';
            }
            $bus_type = 'ide';
        }
        elsif ($self->vmm_type eq 'linux') {
            if ($args->{cdrom}) {
                $dev_type = 'xvdb';
            }
            else {
                $dev_type = 'xvda';
            }
            $bus_type = 'xen';
        }
    }
    elsif ($self->vmm_family eq 'kvm') {
        if ($args->{cdrom}) {
            $dev_type = 'hda';
            $bus_type = 'ide';
        }
        else {
            $dev_type = 'vda';
            $bus_type = 'virtio';
        }
    }
    $elem = $doc->createElement('target');
    $elem->setAttribute(dev => $dev_type);
    $elem->setAttribute(bus => $bus_type);
    $disk->appendChild($elem);

    $elem = $doc->createElement('source');
    $elem->setAttribute(file => $file);
    $disk->appendChild($elem);

    $elem = $doc->createElement('boot');
    if ($args->{cdrom}) {
        $elem->setAttribute(order => 2);
    }
    else {
        $elem->setAttribute(order => 1);
    }
    $disk->appendChild($elem);

    return;
}

# In list context returns pair ($stdout, $stderr). In void (and scalar)
# context just logs stdout and stderr, returns nothing.
sub get_ssh_output {
    my ($chan) = @_;

    my ($stdout, $errout) = ('', '');
    while (!$chan->eof) {
        if (my ($o, $e) = $chan->read2) {
            $stdout .= $o;
            $errout .= $e;
        }
    }
    if (wantarray) {
        return ($stdout, $errout);
    }
    else {
        bmwqemu::diag "Command's stdout:\n$stdout";
        bmwqemu::diag "Command's stderr:\n$errout";
    }
}

sub suspend {
    my ($self) = @_;
    $self->{ssh}->channel()->exec("virsh suspend " . $self->name);
    bmwqemu::diag "VM " . $self->name . " suspended";
}

sub resume {
    my ($self) = @_;
    $self->{ssh}->channel()->exec("virsh resume " . $self->name);
    bmwqemu::diag "VM " . $self->name . " resumed";
}

sub define_and_start {
    my ($self) = @_;

    my $remote_vmm = "";
    if ($self->vmm_family eq 'vmware') {
        my ($fh, $libvirtauthfilename) = tempfile(DIR => "/tmp/");
        my $chan = $self->{ssh}->channel();

        # The libvirt esx driver supports connection over HTTP(S) only. When
        # asked to authenticate we provide the password via 'authfile'.
        $chan->exec(
            "cat > $libvirtauthfilename <<__END
[credentials-vmware]
username=" . get_var('VMWARE_USERNAME') . "
password=" . get_var('VMWARE_PASSWORD') . "
[auth-esx-" . get_var('VMWARE_HOST') . "]
credentials=vmware
__END"
        );
        $chan->close();
        $remote_vmm = "-c vpx://" . get_var('VMWARE_USERNAME') . "@" . get_var('VMWARE_HOST') . "/" . get_var('VMWARE_DATACENTER') . "/" . get_var('VMWARE_SERVER') . "/?no_verify=1\\&authfile=$libvirtauthfilename ";
    }

    my $instance = $self->instance;

    my $doc = $self->{domainxml};

    my $xmlfilename = "/var/lib/libvirt/images/" . $self->name . ".xml";
    my $chan        = $self->{ssh}->channel();
    # scp_put is unfortunately unreliable (RT#61771)
    $chan->exec("cat > $xmlfilename");
    $chan->write($doc->toString(2));
    $chan->close();

    # shut down possibly running previous test (just to be sure) - ignore errors
    $self->{ssh}->channel()->exec("virsh $remote_vmm destroy " . $self->name);
    $self->{ssh}->channel()->exec("virsh $remote_vmm undefine " . $self->name);

    # define the new domain
    $chan = $self->{ssh}->channel();
    $chan->exec("virsh $remote_vmm define $xmlfilename");
    $chan->send_eof;
    get_ssh_output($chan);
    $chan->close();
    die "virsh define failed" if $chan->exit_status();

    $chan = $self->{ssh}->channel();
    $chan->exec("virsh $remote_vmm start " . $self->name);
    $chan->send_eof;
    get_ssh_output($chan);
    $chan->close();
    die "virsh start failed" if $chan->exit_status();

    $self->backend->start_serial_grab($self->name);

    return;
}

sub attach_to_running {
    my ($self, $name) = @_;

    $self->name($name) if $name;
    $self->backend->start_serial_grab($self->name);
}

# Sends command to libvirt host, logs stdout and stderr of the command,
# returns exit status.
#
# Example:
#   my $ret = $svirt->run_cmd("virsh snapshot-create-as snap1");
#   die "snapshot creation failed" unless $ret == 0;
sub run_cmd {
    my ($self, $cmd) = @_;

    my $chan = $self->{ssh}->channel();
    $chan->exec($cmd);
    get_ssh_output($chan);
    $chan->close();
    return $chan->exit_status();
}

# returns stdout of provided command
sub get_cmd_output {
    my ($self, $cmd) = @_;

    my $chan = $self->{ssh}->channel();
    $chan->exec($cmd);
    my @cmd_output = get_ssh_output($chan);
    $chan->send_eof;
    $chan->close();
    return $cmd_output[0];
}

1;
