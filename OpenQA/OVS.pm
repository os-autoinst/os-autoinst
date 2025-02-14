# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::OVS;

sub usage ($r) {
    my $service = $bus->export_service("org.opensuse.os_autoinst.switch");
    my $object = OVS->new($service);
    eval { require Pod::Usage; Pod::Usage::pod2usage($r) };
    die "cannot display help, install perl(Pod::Usage)\n" if $@;
}

sub init_switch ($self) {
    $self->{BRIDGE} = $ENV{OS_AUTOINST_USE_BRIDGE};
    $self->{BRIDGE} //= 'br0';

    until (-e "/sys/class/net/$self->{BRIDGE}") {
        print "Waiting for bridge '$self->{BRIDGE}' to be created and configured...\n";
        sleep 1;
    }
    system('ovs-vsctl', 'br-exists', $self->{BRIDGE});

    for (my $timeout = INIT_TIMEOUT; $timeout > 0; --$timeout) {
        my $bridge_conf = qx{ip addr show $self->{BRIDGE}};
        $self->{MAC} = $1 if $bridge_conf =~ /ether\s+(([0-9a-f]{2}:){5}[0-9a-f]{2})\s/;
        $self->{IP} = $1 if $bridge_conf =~ /inet\s+(([0-9]+.){3}[0-9]+\/[0-9]+)\s/;
        last if $self->{IP};
        print "Waiting for IP on bridge '$self->{BRIDGE}', ${timeout}s left ...\n";
        sleep 1;
    }

    die "can't parse bridge local port MAC" unless $self->{MAC};
    die "can't parse bridge local port IP" unless $self->{IP};

    my $local_ip = $ENV{OS_AUTOINST_BRIDGE_LOCAL_IP} // '10.0.2.2';
    my $netmask = $ENV{OS_AUTOINST_BRIDGE_NETMASK} // 15;
    my $rewrite_target = $ENV{OS_AUTOINST_BRIDGE_REWRITE_TARGET} // '10.1.0.0';
    # we also need a hex-converted form of the rewrite target, thanks
    # https://www.perlmonks.org/?node_id=704295
    my $rewrite_target_hex = unpack('H*', pack('C*', split('\.', $rewrite_target)));

    # the VM have unique MAC that differs in the last 16 bits (see /usr/lib/os-autoinst/backend/qemu.pm)
    # the IP can conflict across vlans
    # to allow connection from VM  to host os-autoinst ($local_ip), we have to do some IP translation
    # we use simple scheme, e.g.:
    # MAC 52:54:00:12:XX:YY -> IP 10.1.XX.YY

    # br0 has IP $local_ip and netmask $netmask. E.g. '/15' covers 10.0.2.2 and 10.1.0.0 ranges
    # this should be also configured permanently in /etc/sysconfig/network
    die "bridge local port IP is expected to be $local_ip/$netmask" unless $self->{IP} eq "$local_ip/$netmask";

    # openflow rules don't survive reboot so they must be installed on each startup
    for my $rule (
        # openflow ports:
        #  LOCAL = br0
        #  1,2,3 ... tap devices

        # default: normal action
        'table=0,priority=0,action=normal',

        # reply packets from local port are handled by learned rules in table 1
        'table=0,priority=1,in_port=LOCAL,actions=resubmit(,1)',


        # arp e.g. 10.0.2.2 - learn rule for handling replies, rewrite ARP sender IP to e.g. 10.1.x.x range and send to local
        # the learned rule rewrites ARP target to the original IP and sends the packet to the original port
        "table=0,priority=100,dl_type=0x0806,nw_dst=$local_ip,actions=" .
'learn(table=1,priority=100,in_port=LOCAL,dl_type=0x0806,NXM_OF_ETH_DST[]=NXM_OF_ETH_SRC[],load:NXM_OF_ARP_SPA[]->NXM_OF_ARP_TPA[],output:NXM_OF_IN_PORT[]),' .
        "load:0x$rewrite_target_hex->NXM_OF_ARP_SPA[],move:NXM_OF_ETH_SRC[0..$netmask]->NXM_OF_ARP_SPA[0..$netmask]," .
        'local',

        # tcp to $self->{MAC} syn - learn rule for handling replies, rewrite source IP to e.g. 10.1.x.x range and send to local
        # the learned rule rewrites DST to the original IP and sends the packet to the original port
        "table=0,priority=100,dl_type=0x0800,tcp_flags=+syn-ack,dl_dst=$self->{MAC},actions=" .
'learn(table=1,priority=100,in_port=LOCAL,dl_type=0x0800,NXM_OF_ETH_DST[]=NXM_OF_ETH_SRC[],load:NXM_OF_IP_SRC[]->NXM_OF_IP_DST[],output:NXM_OF_IN_PORT[]),' .
        "mod_nw_src:$rewrite_target,move:NXM_OF_ETH_SRC[0..$netmask]->NXM_OF_IP_SRC[0..$netmask]," .
        'local',

        # tcp to $self->{MAC} other - rewrite source IP to e.g. 10.1.x.x range and send to local
        "table=0,priority=99,dl_type=0x0800,dl_dst=$self->{MAC},actions=" .
        "mod_nw_src:$rewrite_target,move:NXM_OF_ETH_SRC[0..$netmask]->NXM_OF_IP_SRC[0..$netmask],local",
      )
    {
        system('ovs-ofctl', 'add-flow', $self->{BRIDGE}, $rule);
    }
}

