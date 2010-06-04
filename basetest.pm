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
	# TODO analyse_screenshot $filename;
}

1;
