#!/usr/bin/perl -w
use strict;

use lib "/home/bernhard/code/cvs/perl/os-autoinst/tools";
use rpc_hidclient;
use CGI ":standard";

print header(), start_html(-title => "remote control", -head => qq!<meta name="viewport" content="width=device-width, initial-scale=1" />!),
    start_form(-method => "post"),
    #textfield(-name => 'action'), " action", br,
    popup_menu(-name => 'action', -values => ["send_key", "type_string", "change_cd", "init_usb_gadget", "macro"]), br,
    textfield(-name => 'param1'), " param", br,
    submit(), br,
    end_form();

if (param()) {
    my $action = param('action');
    my $param1 = param('param1');
    if ($action eq "macro") {
        if ($param1 eq "x") {
            send_key("alt-f2");
            sleep 2;
            type_string("xterm -fn 10x20\n");
        }
        if ($param1 eq "s") {
            send_key("alt-f2");
            sleep 2;
            type_string("setxkbmap us\n");
        }
    }
    else {
        rpc_hidclient::RPCwrap({method => $action, params => [$param1]});
    }
}

print hr, br, '<a href="?action=macro&amp;param1=x">xterm</a>', br;
print qq!<a href="?action=macro&amp;param1=s">setxkbmap</a>!, br;
print qq!<a href="?action=type_string&amp;param1=echo if you can read this, the demo worked...%0a">demo</a>!, br;
foreach (qw(alt-f4 right up down)) {
    print qq!<a href="?action=send_key&amp;param1=$_">$_</a> !;
}
print end_html;
