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
	return bless $self,$classname;
}

sub copyrect($$$$)
{
	my $self=shift;
	my ($xstart,$ystart,$xsize,$ysize)=@_;
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
	$self->{data}=~s/[\000-$tc]/\000/g; # black
#	my @a=unpack("C*", $self->{data});
#	foreach(@a) {
#		if($_<$threshold) {$_=0} else {$_=255}
#	}
#	$self->{data}=pack("C*", @a);
}

sub toppm()
{
	my $self=shift;
	return "P6\n$self->{xres} $self->{yres}\n255\n".$self->{data};
}

1;
