package ocr;
use strict;
use warnings;
use ppm;

our $gocrbin="/usr/bin/gocr";
if(!-x $gocrbin) {$gocrbin=undef}
# input: ref on PPM data
sub get_ocr($$@)
{ my $dataref=shift; my $gocrparams=shift||""; my @ocrrect=@{$_[0]};
	if(!$gocrbin || !@ocrrect) {return ""}
	if(@ocrrect!=4) {return " ocr: bad rect"}
	my $ppm=ppm->new($$dataref);
	return unless $ppm;
	my $ppm2=$ppm->copyrect(@ocrrect);
	if(!$ppm2) {return ""}
	my $tempname="/dev/shm/$$-".time.rand(10000).".ppm";
	open(my $tempfile, ">", $tempname) or return " ocr error writing $tempname";
	print $tempfile $ppm2->toppm;
	close $tempfile;
	# init DB file:
	if(!-e "db/db.lst") {
		mkdir "db";
		open(my $fd, ">db/db.lst");
		close $fd;
	}

	open(my $pipe, "$gocrbin -l 128 -d 0 $gocrparams $tempname |") or return "failed to exec $gocrbin: $!";
	local $/;
	my $ocr=<$pipe>;
	close($pipe);
	unlink $tempname;
	return $ocr;
}

1;
