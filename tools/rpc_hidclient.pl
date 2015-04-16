#!/usr/bin/perl -w
use strict;
use MojoX::JSON::RPC::Client;
use Time::HiRes qw(gettimeofday tv_interval);

my $client = MojoX::JSON::RPC::Client->new;
my $url    = 'http://beagle.d.zq1.de:3000/jsonrpc';

sub RPCwrap($) {
    my $callobj = shift;
    #$callobj->{id} = 1;
    my $t = [gettimeofday()];
    my $res = $client->call($url, $callobj);
    print "time: ".tv_interval($t)."\n";

    if($res) {
        if ($res->is_error) { # RPC ERROR
            print 'Error : ', $res->error_message;
        }
        else {
            return $res->result;
        }
    }
    else {
        my $tx_res = $client->tx->res; # Mojo::Message::Response object
        print 'HTTP response '.$tx_res->code.' '.$tx_res->message;
    }
}

sub define_RPC_func($)
{
    my $name=shift;
    eval "sub $name {RPCwrap({method=>'$name', params => [\@_] })}"
}

for (qw(init_usb_gadget send_key change_cd read_serial)) {
    define_RPC_func($_);
}

init_usb_gadget();

#change_cd("/mounts/dist/install/openSUSE-13.2-GM/iso/openSUSE-13.2-NET-x86_64.iso");
#change_cd("/mounts/dist/install/openSUSE-13.2-GM/iso/openSUSE-13.2-NET-i586.iso");
while(<>) { chomp; send_key($_); }
#while(1) { print read_serial()||""; sleep 1; }

