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

sub start_audiocapture
{
	my $self=shift;
	++$self->{wav_count};
	my $path=result_dir;
	my $testname=ref($self);
	my $filename="$path/$testname-$self->{wav_count}.wav";
	bmwqemu::do_start_audiocapture($filename);
	sleep(0.1);
}

sub stop_audiocapture
{
	my $self=shift;
	my $index = shift || 0;
	bmwqemu::do_stop_audiocapture($index);
	sleep(0.1);
}

sub checklist
{
	#die "you need to override this method";
	return {}
}

sub wav_checklist
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
	my @wavdumps=<$path/$testname-*.wav>;
	my $checklist=$self->checklist();
	my $wav_checklist=$self->wav_checklist();
	if(!keys %$checklist && !@screenshots && (!@wavdumps || !keys %$wav_checklist)) { return "not-autochecked" }
	my $checkval = '';
	foreach my $h (keys(%$checklist)) {
		if($hashes->{$h}) {
			$checkval = lc $checklist->{$h};
			last;
		}
	}
	my @testreturn = ();
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
	my @wavreturn = ();
	foreach my $audiofile (@wavdumps) {
		my $aid = $audiofile;
		$aid=~s{.*/$testname-(\d+)\.wav}{$1};
		if(defined $wav_checklist->{$aid}) {
			my $decoded_text = bmwqemu::decodewav($audiofile);
			if((uc $wav_checklist->{$aid}) eq $decoded_text) {
				push(@wavreturn, "ok");
			}
			else {
				push(@wavreturn, "fail");
			}
		}
		else {
			push(@wavreturn, "na");
		}
	}
	my $result_string;
	if(@testreturn) {$result_string .= ' ('.join(',',@testreturn).')';}
	if(@wavreturn) {$result_string .= ' ['.join(',',@wavreturn).']';}
	my @returnval = (@testreturn, @wavreturn, $checkval);
	return 'fail'.$result_string if(grep/fail/,@returnval);
	return 'OK'.$result_string if(grep/ok/,@returnval);
	return 'unknown' if(keys %$checklist || grep/unk/,@returnval); # none of our known results matched
	return 'not-autochecked';
}

1;
