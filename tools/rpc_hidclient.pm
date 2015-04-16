#!/usr/bin/perl -w
use strict;

package rpc_hidclient;
require Exporter;
use MojoX::JSON::RPC::Client;
use Time::HiRes qw(gettimeofday tv_interval);

our @ISA = qw(Exporter);
our @EXPORT;

my $client = MojoX::JSON::RPC::Client->new;
my $url    = 'http://beagle.d.zq1.de:3000/jsonrpc';

sub RPCwrap($) {
    my $callobj = shift;
    #$callobj->{id} = 1;
    my $t = [gettimeofday()];
    my $res = $client->call($url, $callobj);
    print "time: " . tv_interval($t) . "\n";

    if ($res) {
        if ($res->is_error) {    # RPC ERROR
            print 'Error : ', $res->error_message;
        }
        else {
            return $res->result;
        }
    }
    else {
        my $tx_res = $client->tx->res;
        print 'HTTP response ' . $tx_res->code . ' ' . $tx_res->message;
    }
}

sub define_RPC_func($) {
    my $name = shift;
    eval "sub $name {RPCwrap({method=>'$name', params => [\@_] })}";
    push(@EXPORT, $name);
}

for (qw(init_usb_gadget send_key type_string change_cd read_serial)) {
    define_RPC_func($_);
}

1;
