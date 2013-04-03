package needle;

use strict;
use warnings;
use File::Find;
use Data::Dumper;
use JSON;
use File::Basename;

our %needles;
our %tags;

sub new($) {
    my $classname=shift;
    my $jsonfile=shift;
    local $/;
    open( my $fh, '<', $jsonfile ) || return undef;
    my $perl_scalar = decode_json( <$fh> ) || die "broken json $jsonfile";
    close($fh);
    my $self = { xpos => $$perl_scalar{'xpos'},
		 ypos => $$perl_scalar{'ypos'},
		 width => $$perl_scalar{'width'},
		 height => $$perl_scalar{'height'},
		 match => ($$perl_scalar{'match'} || 100) / 100.,
		 processing_flags => $$perl_scalar{'processing_flags'},
		 max_offset => $$perl_scalar{'max_offset'},
		 tags => ($$perl_scalar{'tags'} || [])
    };
    push (@{$self->{tags}}, @{$$perl_scalar{'good'}}) if $$perl_scalar{'good'};
    $self->{file} = $jsonfile;
    $jsonfile =~ s,\.json$,.png,;
    $self->{png} = $jsonfile;
    $self->{img} = undef;
    $self->{name} = basename($jsonfile, '.png');

    $self = bless $self, $classname;
    $self->register();
    return $self;
}

sub unregister($)
{
    my $self = shift;
    for my $g (@{$self->{tags}}) {
	@{$tags{$g}} = grep { $_ != $self } @{$tags{$g}};
    }
}

sub register($)
{
    my $self = shift;
    for my $g (@{$self->{tags}}) {
      $tags{$g} ||= [];
      push(@{$tags{$g}}, $self);
    }
}

sub get_image($) {
    my $self=shift;
    if (!$self->{img}) {
	my $img = tinycv::read($self->{png});
	$self->{img} = $img->copyrect($self->{xpos}, $self->{ypos}, $self->{width}, $self->{height});
    }
    return $self->{img};
}

sub wanted_($) {
    return unless (m/.json$/);
    my $needle = needle->new($File::Find::name);
    if ($needle) {
	$needles{$needle->{name}} = $needle;
    }
}

sub init($) {
    my $dirname=shift;
    find( { no_chdir => 1, wanted => \&wanted_ }, $dirname );
    for my $k (keys %tags) {
	    print "$k\n";
	    for my $p (@{$tags{$k}}) {
		    print "  ", $p->{'name'}, "\n";
	    }
    }
}

sub tag($) {
    my $g = shift;
    return $tags{$g};
}

1;
