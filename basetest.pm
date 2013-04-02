package basetest;
use bmwqemu;
use ocr;
use Time::HiRes;
use JSON;


sub new() {
	my $class=shift;
	my $self={class=>$class};
	return bless $self, $class;
}

=head1 Methods

=head2 run

Body of the test to be implemented by child classes.
This code is run during test.

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

Can be called from C<run> to have screenshots in addition to the one taken via distri/opensuse/main.pm:installrunfunc after run finishes

=cut
sub take_screenshot() {
	my $self=shift;
	my $filename=$self->next_resultname("png");
	bmwqemu::do_take_screenshot()->write_optimized($filename);
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

=head2 wav_checklist

Return a hashref mapping a DTMF decoding to "OK" 
everything else defaults to "fail"

=cut
sub wav_checklist {
	return {}
}

=head2 ocr_checklist

Optical Character Recognition matching.

Return a listref containing hashrefs like this:

  {
    screenshot=>2,		# nr of screenshot for the test to OCR
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
	my $wav_checklist=$self->wav_checklist();
	my $ocr_checklist=$self->ocr_checklist();

	#if(!keys %$checklist && !@screenshots && (!@wavdumps || !keys %$wav_checklist) && !@$ocr_checklist) { return "not-autochecked" } #FIXME: return properly

	print "CHECK $testname ", @screenshots, "\n";
	# Screenshot Check
	my @screenshot_results = ();
	foreach my $screenimg (@screenshots) {
		my $prefix = $screenimg;
		$prefix=~s{.*/$testname-(\d+)\.ppm}{$testname-$1};
		my @refimgs=<$scriptdir/testimgs/$prefix-*-*-*.ppm>;
		$screenimg=~m/-(\d+)\.ppm$/ or die "invalid screenshot name";
		my $screenshotnr = $1;

		my $screenshot_result = {'refimg_result' => 'unk', 'ocr_result' => 'na'};

		# Reference Image Check
		if(!@refimgs) {
			push(@testreturn, "na");
			$screenshot_result->{refimg_result} = 'na';
		}
		else {
			foreach my $refimg (@refimgs) {
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
				my $c = bmwqemu::checkrefimgs($screenimg,$refimg,$flags);
				print "checkrefimgs $screenimg $refimg $flags $c\n";
				if($c) {
					my ($result, $refimg_id) = ($refimg, $refimg);
					$result=~s/.*-(.*)-.*\.ppm/$1/;
					$refimg_id=~s/.*-([0-9]*)-.*-.*\.ppm/$1/;
					$screenshot_result->{refimg_result} = (($result eq 'good')?'ok':'fail');
					$screenshot_result->{refimg} = {
						'id' => int($refimg_id),
						'match' => [@$c[0], @$c[1]],
						'size' => [@$c[2], @$c[3]]
					};
					last;
				}
			}
		}

		# OCR Check
		if(@$ocr_checklist) {
			my $img = tinycv::read($screenimg);
			foreach my $entry (@$ocr_checklist) {
				next if($entry->{screenshot} != $screenshotnr);
				my @ocrrect = ($entry->{x}, $entry->{y}, $entry->{xs}, $entry->{ys});
				my $ocr = ocr::get_ocr($img, "", \@ocrrect);
				open(OCRFILE, ">$path/$testname-$entry->{screenshot}.txt");
				print OCRFILE $ocr;
				close(OCRFILE);
				print STDERR "\nOCR OUT: $ocr\n";
				if($ocr=~m/$entry->{pattern}/) {
					my $result = $entry->{result};
					$screenshot_result->{ocr_result} = lc($result);
					last;
				}
				else {
					$screenshot_result->{ocr_result} = 'unk';
				}
			}
		}

		push(@screenshot_results, $screenshot_result);

	}

	# Audio Check
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

	my @refimg_results = map($_->{refimg_result}, @screenshot_results);
	my @ocr_results = map($_->{ocr_result}, @screenshot_results);
	my @returnval = (@refimg_results, @ocr_results, @wavreturn, $md5_result);

	my $module_result = 'na';
	if(grep/fail/,@returnval) { $module_result = 'fail' }
	elsif(grep/ok/,@returnval) { $module_result = 'ok' }
	elsif(grep/unk/,@returnval) { $module_result = 'unk' } # none of our known results matched

	my $return_result = {
		'name' => $testname,
		'result' => $module_result,
		'md5_result' => $md5_result,
		'screenshots' => [@screenshot_results],
		'audiodumps' => [@wavreturn]
	};
	print STDERR '--- '.JSON::to_json($return_result)."\n";
	return $return_result;
}

1;
