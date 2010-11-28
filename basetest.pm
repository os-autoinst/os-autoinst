package basetest;
use bmwqemu;

sub new()
{
	my $class=shift;
	my $self={class=>$class};
	return bless $self, $class;
}

sub is_applicable()
{
	return 1;
}

sub take_screenshot()
{
	my $self=shift;
	++$self->{count};
	my $path="testresults";
	my $version=$testedversion;
	mkdir $path;
	mkdir "$path/$version";
	my $testname=ref($self);
        my $filename="$path/$version/$testname-$self->{count}.ppm";
        qemusend "screendump $filename";
	# TODO analyze_screenshot $filename;
}

sub checklist
{
	#die "you need to override this method";
	return {}
}

sub check(%)
{
	my $self=shift;
	my $hashes=shift;
	my $checklist=$self->checklist();
	if(!keys %$checklist) { return "not-autochecked" }
	foreach my $h (keys(%$checklist)) {
		if($hashes->{$h}) {
			return $checklist->{$h};
		}
	}
	return undef;
}

1;
