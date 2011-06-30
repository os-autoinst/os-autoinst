package basetest;
use bmwqemu;
use Time::HiRes;

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
	sleep(0.1);
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
	my $path=result_dir;
	$path=~s/\.ogv.*//;
	if(!-e $path) {
		my $dir = `cd ../.. ; pwd ..`;
		chomp($dir);
		$path = "$dir/$path";
	}
	my $testname=ref($self);
	my @screenshots=<$path/$testname-*.ppm>;
	my $checklist=$self->checklist();
	if(!keys %$checklist && !@screenshots) { return "not-autochecked" }
	foreach my $h (keys(%$checklist)) {
		if($hashes->{$h}) {
			return $checklist->{$h};
		}
	}
	my @testreturn;
	foreach my $screenimg (@screenshots) {
		my $prefix = $screenimg;
		$prefix=~s{.*/$testname-(\d+)\.ppm}{$testname-$1};
		#my $filename = $prefix.'.ppm';
		my @refimgs=<$scriptdir/testimgs/$prefix-*-*.ppm>;
		if(!@refimgs) {
			push(@testreturn, "na");
		}
		else {
			my $matched=0;
			foreach my $refimg (@refimgs) {
				#my $t=[Time::HiRes::gettimeofday()];
				my $c=bmwqemu::checkrefimgs($screenimg,$refimg,'t');
				#print "$refimg: ".Time::HiRes::tv_interval($t)."\n";
				if(defined $c) {
					my $result=$refimg;
					$result=~s/.*-(.*)\.ppm/$1/;
					push(@testreturn, (($result eq 'good')?'ok':'fail'));
					$matched=1;
					last;
				}
			}
			push(@testreturn, "unk") if !$matched;
		}
	}
	my $result_string = '('.join(',',@testreturn).')';
	return 'fail'.' '.$result_string if(grep/fail/,@testreturn);
	return 'OK'.' '.$result_string if(grep/ok/,@testreturn);
	return 'unknown' if(keys %$checklist || grep/unk/,@testreturn); # none of our known results matched
	return 'not-autochecked';
}

1;
