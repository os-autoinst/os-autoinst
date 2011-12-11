#!/usr/bin/perl -w
use strict;
# perl port by Bernhard M. Wiedemann from work
# © 2009 – 2011, Kees Cook. This work is licensed under a Creative Commons Attribution-ShareAlike 3.0 License.
my $wav=shift;
my $pactl=`pactl list`;
my $monitor;
foreach my $m (($pactl=~m/Source #\d+\s+State: \w+\s+Name: (\S+)/)) {
	$monitor=$m;
}
#print "$monitor\n";
# mono capture
#system(qq'parec -d "$monitor" | sox -t raw -r 44100 -sLb 16 -c 2 - -c 1 "$wav"');
# had to rewrite this line because bash clears alarm signal
my $pid=fork();
if($pid==0) { # child
	alarm 60;
	pipe READHANDLE,WRITEHANDLE;
	my $p2=fork();
	if($p2>0) { # parent
		close READHANDLE;
		open(STDOUT, ">&", \*WRITEHANDLE);
		exec('parec', '-d', $monitor);
		die "error executing parec";
	} elsif($p2==0) {
		close WRITEHANDLE;
		open(STDIN, "<&", \*READHANDLE);
		exec(qw(sox -t raw -r 44100 -sLb 16 -c 2 - -c 1), $wav);
		die "error executing sox";
	} else { die "could not fork"}
}
waitpid($pid,0);
