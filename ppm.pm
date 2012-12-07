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
	my $d=$self->{xres}*$self->{yres}*BPP-length($self->{data});
	if($d) {
		warn "incomplete/corrupt ppm of size ".length($self->{data});
		return undef if $d<0;
		$self->{data}.="\x00" x $d; # pad data to make a valid ppm
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

our $inline=eval "use Inline C=>q{
	void thresholdC(SV* s, unsigned char thresholdval)
	{
		long i; STRLEN len; unsigned char *c=SvPV(s,len);
		for(i=len-1; i>=0; i--)
			c[i]=((c[i]<thresholdval)? 0 : 0xff);
	}
	long addpixels(SV* s, int offset)
	{
		long sum=0; long i; STRLEN len; unsigned char *c=SvPV(s,len);
		for(i=len-3+offset; i>=0; i-=3)
			sum += c[i];
		return sum;
	}
	bool maxbytediffC(SV* sva, SV* svb, unsigned char maxdiff)
	{
		long i;
		STRLEN alen; unsigned char *ca=SvPV(sva,alen);
		STRLEN blen; unsigned char *cb=SvPV(svb,blen);
		for(i=alen-1; i>=0; i--) {
			if (abs(ca[i] - cb[i]) > maxdiff)
				return 0;
		}
		return 1;
	}
	long getmaxbytediffC(SV* sva, SV* svb)
	{
		long i;
		unsigned char diff, maxdiff=0;
		STRLEN alen; unsigned char *ca=SvPV(sva,alen);
		STRLEN blen; unsigned char *cb=SvPV(svb,blen);
		for(i=0; i<alen; i++) {
			diff=abs(ca[i] - cb[i]);
			printf(\"%c\", diff);
			if (diff > maxdiff)
				maxdiff = diff;
		}
		return maxdiff;
	}
	long searchC(SV* svs, SV* svr, long svsxlen, long svrxlen, unsigned char maxdiff)
	{
		STRLEN slen; unsigned char *cs=SvPV(svs,slen);
		STRLEN rlen; unsigned char *cr=SvPV(svr,rlen);
		// divide by 3 because of 3 byte per pix
		// substract 1 to be able to add color-byte offset by hand
		long slen_pix = slen / 3;
		long rlen_pix = rlen / 3;
		long newlineoffset = svsxlen - svrxlen;
		long svrxlen_check = rlen_pix - 1;
		long i, my_i, j, remaining_sline;
		long byteoffset_s, byteoffset_r;
		long rs, bs, gs, rr, br, gr;
		for(i=0; i<slen_pix; i++) {
			remaining_sline = (svsxlen - (i % svsxlen));
			if ( remaining_sline < svrxlen ) {
				// a refimg line would not fit
				// into remaining selfimg line
				// jump to next line
				i += remaining_sline - 1; // ugly but faster
				continue;
			}
			// refimg does fit in remaining img check?
			my_i = i;
			for(j=0; j<rlen_pix; j++) {
				if (j > 0 && j % svrxlen == 0) {
					// we have reached end of a line in refimg
					// pos 0 in refimg does not mean end of line
					my_i += newlineoffset;
				}
				if (my_i >= slen_pix)
					break;

				byteoffset_s = (my_i+j)*3;
				byteoffset_r = j*3;
				if (
					abs(cs[byteoffset_s+0] - cr[byteoffset_r+0]) > maxdiff ||
					abs(cs[byteoffset_s+1] - cr[byteoffset_r+1]) > maxdiff ||
					abs(cs[byteoffset_s+2] - cr[byteoffset_r+2]) > maxdiff
				) {
					//printf(\"x: %d\\n\", (my_i+j) % svsxlen);
					//printf(\"y: %d\\n\", (my_i+j) / svsxlen);
					//printf(\"byte_offset: %d\\n\", byteoffset_s);
					//printf(\"s: %x - r: %x\\n\", cs[byteoffset_s+0], cr[byteoffset_r+0]);
					//printf(\"break\\n\\n\\n\");
					break;
				}
				if (j == svrxlen_check) {
					// last iteration - refimg processed without break
					// return i which is startpos of match (in pixels)
					return i;
				}
			}
		}
		return -1;
	}
}; 1;";

# in-place op: change all values to 0 (if below threshold) or 255 otherwise
sub threshold($)
{
	my $self=shift;
	my $threshold=shift;
	if($inline) {
		thresholdC($self->{data}, $threshold);
	} else {
		my $tc=chr($threshold);
		$self->{data}=~s/[$tc-\xff]/\xff/g; # white
		$self->{data}=~s/[\000-\xfe]/\000/g; # black
	}
}

# calculate average color values
# out: (r,g,b) in range 0..1
sub avgcolor()
{
	my $self=shift;
	my @c=(0,0,0);
	my $n=0;
	if($inline) {
		for my $i (0..2) {
			$c[$i]=addpixels($self->{data}, $i);
		}
	} else {
		my @d=unpack("C*",$self->{data});
		foreach my $value (@d) {
			$c[$n % BPP]+=$value;
			$n++;
		}
	}
	$n=length($self->{data})*255/3;
	return map {$_/$n} @c;
}

sub maxbytediff($;$) {
	my $self = shift;
	my $comp = shift;
	my $maxdiff = shift || 0;
	return 0 unless(length($self->{data}) == length($comp->{data}));
	if($inline) {
		return maxbytediffC($self->{data}, $comp->{data}, $maxdiff);
	} else {
		die "FIXME: perl fallback";
	}
}

sub getmaxbytediff($)
{
	my $self = shift;
	my $comp = shift;
	if($inline) {
		print "P6\n$self->{xres} $self->{yres}\n255\n";
		return getmaxbytediffC($self->{data}, $comp->{data});
	} else {
		die "FIXME: perl fallback";
	}
}

# in: needle to search [ppm object]
# out: (x,y) coords if found, undef otherwise
# inspired by OCR::Naive
sub search($;$)
{
	my $self=shift;
	my $needle=shift;
	my $maxdiff = shift || 0;
	my $xneedle=$needle->{xres};
	my $xhay=$self->{xres};
	if($inline) {
		my $pos = searchC($self->{data}, $needle->{data}, $self->{xres}, $needle->{xres}, $maxdiff);
		if ($pos ne -1) {
			my($x,$y)=($pos % $xhay, int($pos/$xhay));
			return($x,$y);
		}
	}
	else {
		#FIXME: this is old - port the code from the searchC
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
	}
	return undef;
}

sub toppm()
{
	my $self=shift;
	return "P6\n$self->{xres} $self->{yres}\n255\n".$self->{data};
}

1;
