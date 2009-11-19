$|=1;

package bmwqemu;
use strict;
use warnings;
use Exporter;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw(%cmd autotype sendkey);


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
	$cmd{"mountpoint"}="alt-e";
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

sub sendkey($)
{
	my $key=shift;
	print "sendkey $key\n";
}

1;
