package ppm;
use strict;
use warnings;
use constant BPP=>3;

sub new($)
{
	my $classname=shift;
	my $ppmdata=shift;
	my $self={};
	if(ref($ppmdata)) {
		# copy another ppm
		($self->{xres},$self->{yres})=($ppmdata->{xres},$ppmdata->{yres});
		$self->{data}=$ppmdata->{data};
		return bless $self,$classname;
	}
#	print "$ppmdata\n";
	my $header=substr($ppmdata,0,30);
	($self->{xres},$self->{yres})=($header=~m/\AP6\n(\d+) (\d+)\n255\n/);
	if(!$self->{xres}) {return undef} # unsupported format
	#$self->{header}=$&;
	$self->{data}=substr($ppmdata,length($&));
	if(length($self->{data})!=$self->{xres}*$self->{yres}*BPP) {
		warn "incomplete/corrupt ppm of size ".length($self->{data});
		return undef;
	}
	return bless $self,$classname;
}

sub copyrect($$$$)
{
	my $self=shift;
	my ($xstart,$ystart,$xsize,$ysize)=@_;
	if($xstart+$xsize>$self->{xres} || $ystart+$ysize>$self->{yres}) {return}
	my $newppm={};
	($newppm->{xres},$newppm->{yres})=($xsize,$ysize);
	my $len=$xsize*BPP;
	my $xres=$self->{xres};
	for my $y ($ystart..($ystart+$ysize-1)) {
		my $offs=BPP*($xstart+$y*$xres);
		$newppm->{data}.=substr($self->{data}, $offs, $len);
	}
	return bless $newppm, ref $self;
}

# zero out a region of a PPM
# in-place op
sub replacerect($$$$)
{
	my $self=shift;
	my ($xstart,$ystart,$xsize,$ysize)=@_;
	my $len=$xsize*BPP;
	my $xres=$self->{xres};
	for my $y ($ystart..($ystart+$ysize-1)) {
		my $offs=BPP*($xstart+$y*$xres);
		substr($self->{data}, $offs, $len, "\000" x $len);
	}
	return $self;
}

# in-place op: change all values to 0 (if below threshold) or 255 otherwise
sub threshold($)
{
	my $self=shift;
	my $threshold=shift;
	my $tc=chr($threshold);
	$self->{data}=~s/[$tc-\xff]/\xff/g; # white
	$self->{data}=~s/[\000-\xfe]/\000/g; # black
#	my @a=unpack("C*", $self->{data});
#	foreach(@a) {
#		if($_<$threshold) {$_=0} else {$_=255}
#	}
#	$self->{data}=pack("C*", @a);
}


# in: needle to search [ppm object]
# out: (x,y) coords if found, undef otherwise
# inspired by OCR::Naive
sub search($)
{
	my $self=shift;
	my $needle=shift;
	my $xneedle=$needle->{xres};
	my $xhay=$self->{xres};
	# build regexp from $needle
	my $offs=0;
	my $linesize=$xneedle*BPP;
	my @lines=();
	for my $n (0..($needle->{yres}-1)) {
		my $line=substr($needle->{data},$offs,$linesize);
		push(@lines,quotemeta($line));
		$offs+=$linesize;
	}
	# any char between lines is ignored
	my $regexp=join(".{".($xhay*BPP-$linesize)."}", @lines);
	# actual search
	if($self->{data}=~m/$regexp/ps) {
		my $pos=length(${^PREMATCH})/BPP;
		my($x,$y)=($pos % $xhay, int($pos/$xhay));
		return($x,$y);
	}
	return undef;
}

sub toppm()
{
	my $self=shift;
	return "P6\n$self->{xres} $self->{yres}\n255\n".$self->{data};
}

1;
