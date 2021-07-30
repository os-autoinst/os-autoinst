#!/usr/bin/perl

use Test::Most;
use Test::Warnings qw(:all :report_warnings);
use Test::Output;

use consoles::localXvnc;

$consoles::localXvnc::xterm_vt = 'true';
ok my $c = consoles::localXvnc->new(), 'object can be instanciated';
like $c->sshCommand('my_user', 'my_host'), qr/ssh.*my_user\@my_host/, 'sshCommand returns valid command string';
$c->{DISPLAY} = ':42';
$consoles::localXvnc::xterm_vt = 'xterm-console';
#my $ret;
#my ($stdout, $stderr) = output_from { $ret = $c->callxterm('true', 'my_window_name') };
#print "stdout: $stdout\n";
#print "stderr: $stderr\n";
# TODO this fails being unable to find the error string but instead states
# that "xterm PID is …" is found. Why does the output differ depending on how
# I call the stuff?
combined_like { $ret = $c->callxterm('true', 'my_window_name') } qr/xterm.*Can't open display: :42/, 'xterm fails';
#combined_like { $ret = $c->callxterm('true', 'my_window_name') } qr/xterm PID is/, 'xterm fails';
#combined_like { $ret = $c->callxterm('true', 'my_window_name') } qr/foo/, 'xterm fails';
#$ret = $c->callxterm('true', 'my_window_name');
is $ret, 0, 'callxterm returns false result from system command';

done_testing;
