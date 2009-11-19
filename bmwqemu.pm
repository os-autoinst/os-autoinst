$|=1;

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
