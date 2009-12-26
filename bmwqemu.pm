$|=1;

package bmwqemu;
use strict;
use warnings;
use Time::HiRes qw(sleep);
use Exporter;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw(%cmd &sendkey &sendautotype &autotype);


our %cmd=qw(
next alt-n
install alt-i
finish alt-f
accept alt-a
createpartsetup alt-c
custompart alt-c
addpart alt-d
donotformat alt-d
addraid alt-i
add alt-a
raid0 alt-0
raid1 alt-1
raid6 alt-6
raid10 alt-i
mountpoint alt-m
filesystem alt-s
);

$ENV{INSTLANG}||="us";
if($ENV{INSTLANG} eq "de") {
	$cmd{"next"}="alt-w";
	$cmd{"createpartsetup"}="alt-e";
	$cmd{"custompart"}="alt-b";
	$cmd{"addpart"}="alt-h";
	$cmd{"finish"}="alt-b";
	$cmd{"accept"}="alt-r";
	$cmd{"donotformat"}="alt-n";
	$cmd{"add"}="alt-h";
	$cmd{"raid6"}="alt-d";
	$cmd{"raid10"}="alt-r";
	$cmd{"mountpoint"}="alt-e";
}

sub sendkey($)
{
	my $key=shift;
	print "sendkey $key\n";
	sleep(0.05);
}

my %charmap=("."=>"dot", "/"=>"slash", 
   "\t"=>"tab", "\n"=>"ret", " "=>"spc", "\b"=>"backspace");

sub sendautotype($)
{
	my $string=shift;
	foreach my $letter (split("", $string)) {
		if($charmap{$letter}) { $letter=$charmap{$letter} }
		sendkey $letter;
	}
}

sub autotype($)
{
	my $string=shift;
	my $result="";
	foreach my $letter (split("", $string)) {
		$result.="sendkey $letter\n";
	}
	return $result;
}

1;
