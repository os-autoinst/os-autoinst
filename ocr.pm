package ocr;
use strict;
use warnings;
use cv;

our $gocrbin="/usr/bin/gocr";
if(!-x $gocrbin) {$gocrbin=undef}
# input: image ref
sub get_ocr($$@) {
	my $ppm=shift; my $gocrparams=shift||""; my @ocrrect=@{$_[0]};
	if(!$gocrbin || !@ocrrect) {return ""}
	if(@ocrrect!=4) {return " ocr: bad rect"}
	return unless $ppm;
	my $ppm2=$ppm->copyrect(@ocrrect);
	if(!$ppm2) {return ""}
	my $tempname="ocr.$$-".time.rand(10000).".ppm";
	$ppm2->write($tempname) or return " ocr error writing $tempname";
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
