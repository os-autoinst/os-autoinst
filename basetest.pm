package basetest;
use bmwqemu;
use ocr;
use Time::HiRes;


sub new() {
	my $class=shift;
	my $self={class=>$class};
	return bless $self, $class;
}

=head1 Methods

=head2 run

Body of the test?

=head2 is_applicable

Return false if the test should be skipped.

Can eg. check ENV{BIGTEST}, ENV{LIVETEST}

=cut
sub is_applicable() {
	return 1;
}

sub next_resultname($) {
	my($self,$type)=@_;
	my $count=++$self->{$type."_count"};
	my $path=result_dir;
	my $testname=ref($self);
	return "$path/$testname-$count.$type";
}

=head2 take_screenshot

Must be called at least once from C<run> to have screenshots for L</checklist>

=cut
sub take_screenshot() {
	my $self=shift;
	my $filename=$self->next_resultname("ppm");
	bmwqemu::do_take_screenshot($filename);
	sleep(0.1);
	# TODO analyze_screenshot $filename;
}

sub start_audiocapture {
	my $self=shift;
	my $filename=$self->next_resultname("wav");
	bmwqemu::do_start_audiocapture($filename);
	sleep(0.1);
}

sub stop_audiocapture {
	my $self=shift;
	my $index = shift || 0;
	bmwqemu::do_stop_audiocapture($index);
	sleep(0.1);
}

=head2 checklist

Return a hashref mapping the digests of screenshots to "OK" or "fail"

=cut
sub checklist {
	return {}
}

=head2 wav_checklist

Return a hashref mapping FIXME to FIXME

=cut
sub wav_checklist {
	return {}
}

=head2 ocr_checklist

Optical Character Recognition matching.

Return a listref containing hashrefs like this:

  {
    screenshot=>2,		# ?
    x=>104, y=>201,		# position
    xs=>380, ys=>150,		# size
    pattern=>"H ?ello",		# regex to match the OCR result

    result=>"OK"		# or "fail"
  }

=cut
sub ocr_checklist {
	return []
}

=head2 check($hashes) [protected]

After C<run> is done, evaluate the screen dumps according to checklists.

Return a string "STATUS DESCRIPTION"
where STATUS is one of: OK fail unknown not-autochecked

=cut
sub check(%) {
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
	my $ocr_checklist=$self->ocr_checklist();
	if(!keys %$checklist && !@screenshots && (!@wavdumps || !keys %$wav_checklist) && !@$ocr_checklist) { return "not-autochecked" }
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
		my @refimgs=<$scriptdir/testimgs/$prefix-*-*-*.ppm>;
		if(!@refimgs) {
			push(@testreturn, "na");
		}
		else {
			my $matched=0;
			foreach my $refimg (@refimgs) {
				#my $t=[Time::HiRes::gettimeofday()];
				my $match = $refimg;
				$match=~s/.*-(.*)\.ppm/$1/;
				my $flags = '';
				if ($match eq 'strict') {$flags = ''}
				elsif ($match eq 'diff') {$flags = 'd'}
				elsif ($match eq 'fuzzy') {$flags = 'f'}
				elsif ($match eq 'hwfuzzy') {
					if(defined $ENV{'HW'} && $ENV{'HW'}) {
						$flags = 'f';
					}
					else {
						$flags = 'd';
					}
				}
				my $c=bmwqemu::checkrefimgs($screenimg,$refimg,$flags);
				#print "$refimg: ".Time::HiRes::tv_interval($t)."\n";
				if(defined $c) {
					my $result=$refimg;
					$result=~s/.*-(.*)-.*\.ppm/$1/;
					print STDERR "   $prefix: $match => $result\n";
					push(@testreturn, (($result eq 'good')?'ok':'fail'));
					$matched=1;
					last;
				}
			}
			push(@testreturn, "unk") if !$matched;
		}
	}
	my @ocrreturn = ();
	foreach my $screenimg (@screenshots) {
		if(!@$ocr_checklist) {
			#	push(@ocrreturn, "na");
		}
		else {
			$screenimg=~m/-(\d+)\.ppm$/ or die "invalid screenshot name";
			my $screenshotnr=$1;
			my $data=fileContent($screenimg);
			my $matched;
			foreach my $entry (@$ocr_checklist) {
				next if($entry->{screenshot} != $screenshotnr);
				$matched=0;
				my @ocrrect=($entry->{x}, $entry->{y}, $entry->{xs}, $entry->{ys});
				my $ocr=ocr::get_ocr(\$data, "", \@ocrrect);
				open(OCRFILE, ">$path/$testname-$entry->{screenshot}.txt");
				print OCRFILE $ocr;
				close(OCRFILE);
				print STDERR "\nOCR OUT: $ocr\n";
				if($ocr=~m/$entry->{pattern}/) {
					my $result=$entry->{result};
					push(@ocrreturn, lc($result));
					$matched=1;
					last;
				}
			}
			if(!defined($matched)) {push(@ocrreturn, "na")}
			elsif(!$matched) { push(@ocrreturn, "unk")}
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
	my $result_string = '';
	if(@testreturn) {$result_string .= ' ('.join(',',@testreturn).')';}
	if(@wavreturn) {$result_string .= ' ['.join(',',@wavreturn).']';}
	if(@ocrreturn) {$result_string .= ' {'.join(',',@ocrreturn).'}';}
	my @returnval = (@testreturn, @ocrreturn, @wavreturn, $checkval);
	return 'fail'.$result_string if(grep/fail/,@returnval);
	return 'OK'.$result_string if(grep/ok/,@returnval);
	return 'unknown'.$result_string if(keys %$checklist || grep/unk/,@returnval); # none of our known results matched
	return 'not-autochecked';
}

1;
