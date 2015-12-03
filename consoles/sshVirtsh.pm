package consoles::sshVirtsh;
use base 'consoles::sshXtermVt';
use strict;
use warnings;
use testapi qw/get_var/;
require IPC::System::Simple;
use autodie qw(:all);
use Net::SSH2;
use XML::LibXML;

use Class::Accessor "antlers";
has instance => (is => "rw");

sub activate {
    my ($self) = @_;

    my $args = $self->{args};

    my $hostname = $args->{hostname} || die('we need a hostname to ssh to');
    my $password = $args->{password} || $testapi::password;

    $self->{ssh} = Net::SSH2->new;
    $self->{ssh}->connect($hostname);
    $self->{ssh}->auth_password('root', $password);

    $self->instance(get_var('VIRSH_INSTANCE') || '1');

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

sub define_domain {
    my ($self, $args) = @_;

    $args ||= {};

    my $instance = $self->instance;
    my $doc      = $self->{domainxml} = XML::LibXML::Document->new;
    my $root     = $doc->createElement('domain');
    $root->setAttribute(type => 'kvm');
    $doc->setDocumentElement($root);

    my $elem;
    $elem = $doc->createElement('name');
    $elem->appendTextNode($self->name);
    $root->appendChild($elem);

    $elem = $doc->createElement('description');
    $elem->appendTextNode("openQA Instance $instance");
    $root->appendChild($elem);

    $elem = $doc->createElement('memory');
    $elem->appendTextNode('512');
    $elem->setAttribute(unit => 'MiB');
    $root->appendChild($elem);

    $elem = $doc->createElement('vcpu');
    $elem->appendTextNode('1');
    $root->appendChild($elem);

    my $os = $doc->createElement('os');
    $root->appendChild($os);

    $elem = $doc->createElement('type');
    $elem->appendTextNode('hvm');
    $os->appendChild($elem);

    for my $tag (qw(kernel initrd cmdline)) {
        if ($args->{$tag}) {
            $elem = $doc->createElement($tag);
            $elem->appendTextNode($args->{$tag});
            $os->appendChild($elem);
        }
    }

    for my $tag (qw(on_poweroff on_reboot)) {
        if ($args->{$tag}) {
            $elem = $doc->createElement($tag);
            $elem->appendTextNode($args->{$tag});
            $root->appendChild($elem);
        }
    }

    $elem = $doc->createElement('devices');
    $root->appendChild($elem);
    return;
}

sub devices_element {
    my ($self) = @_;

    my $doc = $self->{domainxml};
    return $doc->getElementsByTagName('domain')->shift->getElementsByTagName('devices')->shift;
}

sub add_pty {
    my ($self, $args) = @_;

    my $doc     = $self->{domainxml};
    my $devices = $self->devices_element;

    my $console = $doc->createElement('console');
    $console->setAttribute(type => 'pty');
    $devices->appendChild($console);

    my $elem = $doc->createElement('target');
    $elem->setAttribute(type => $args->{type});
    $elem->setAttribute(port => $args->{port});
    $console->appendChild($elem);

    return;
}

# network stuff
sub add_interface {
    my ($self, $args) = @_;

    my $doc     = $self->{domainxml};
    my $devices = $self->devices_element;

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
    my $devices = $self->devices_element;

    my $disk = $doc->createElement('disk');
    $disk->setAttribute(type   => 'file');
    $disk->setAttribute(device => 'disk');
    $devices->appendChild($disk);

    my $elem = $doc->createElement('driver');
    $elem->setAttribute(name => 'qemu');
    $elem->setAttribute(type => 'qcow2');
    $disk->appendChild($elem);

    $elem = $doc->createElement('target');
    $elem->setAttribute(dev => 'vda');
    $elem->setAttribute(bus => 'virtio');
    $disk->appendChild($elem);

    $elem = $doc->createElement('source');
    $elem->setAttribute(file => $file);
    $disk->appendChild($elem);

    return;
}

sub define_and_start {
    my ($self) = @_;

    my $instance = $self->instance;

    my $doc = $self->{domainxml};

    my $xmlfilename = "/var/lib/libvirt/images/" . $self->name . ".xml";
    my $chan        = $self->{ssh}->channel();
    # scp_put is unfortunately unreliable (RT#61771)
    $chan->exec("cat > $xmlfilename");
    $chan->write($doc->toString(2));
    $chan->close();

    # shut down possibly running previous test (just to be sure) - ignore errors
    $self->{ssh}->channel()->exec("virsh destroy " . $self->name);
    $self->{ssh}->channel()->exec("virsh undefine " . $self->name);

    # define the new domain
    $chan = $self->{ssh}->channel();
    $chan->exec("virsh define $xmlfilename");
    bmwqemu::diag $_ while <$chan>;
    $chan->close();
    die "virsh define failed" if $chan->exit_status();

    $chan = $self->{ssh}->channel();
    $chan->exec("virsh start " . $self->name);
    bmwqemu::diag $_ while <$chan>;
    $chan->close();
    die "virsh start failed" if $chan->exit_status();

    return;

}

sub name {
    my ($self) = @_;

    return "openQA-SUT-" . $self->instance;
}

1;
