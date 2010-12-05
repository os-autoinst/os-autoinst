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
	my $path=result_dir;
	my $testname=ref($self);
        my $filename="$path/$testname-$self->{count}.ppm";
        bmwqemu::do_take_screenshot($filename);
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
