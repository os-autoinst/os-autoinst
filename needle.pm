package needle;

use strict;
use warnings;
use File::Find;
use Data::Dumper;
use JSON;
use File::Basename;

our %needles;

sub new($) {
    my $classname=shift;
    my $jsonfile=shift;
    local $/;
    open( my $fh, '<', $jsonfile ) || return undef;
    my $perl_scalar = decode_json( <$fh> );
    close($fh);
    my $self = { xpos => $$perl_scalar{'xpos'},
		 ypos => $$perl_scalar{'ypos'},
		 width => $$perl_scalar{'width'},
		 height => $$perl_scalar{'height'},
		 match => $$perl_scalar{'match'} / 100.,
		 processing_flags => $$perl_scalar{'processing_flags'},
		 max_offset => $$perl_scalar{'max_offset'},
		 matches => $$perl_scalar{'matches'}
    };
    $jsonfile =~ s,\.json$,.png,;
    $self->{png} = $jsonfile;
    $self->{img} = undef;
    $self->{name} = basename($jsonfile, '.png');

    $self = bless $self, $classname;
    return $self;
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
}

sub match($) {
    my $substring = shift;
    my @ret;
    for my $key (grep(/$substring/, keys %needles)) {
	push(@ret, $needles{$key});
    }
    return \@ret;
}

1;
