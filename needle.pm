package needle;

use strict;
use warnings;
use File::Find;
use File::Spec;
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
    # TODO: for compat only. remove when all tests are converted
    push (@{$self->{tags}}, @{$$perl_scalar{'good'}}) if $$perl_scalar{'good'};
    $self->{file} = $jsonfile;
    $self->{name} = basename($jsonfile, '.json');
    my $png = $self->{png} || $self->{name} . ".png";
    $self->{png} = File::Spec->catpath('', dirname($jsonfile), $png);
    if (! -s $self->{png}) {
      die "Can't find $self->{png}";
    }
    $self->{img} = undef;

    $self = bless $self, $classname;
    $self->register();
    return $self;
}

sub unregister($)
{
    my $self = shift;
    print "unregister $self->{name}\n";
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

sub glob($) {
    my $self=shift;
    if (!$self->{img}) {
	my $img = tinycv::read($self->{png});
	$self->{img} = $img->copyrect($self->{xpos}, $self->{ypos}, $self->{width}, $self->{height});
    }
    return $self->{img};
}

sub has_tag($$) {
	my $self = shift;
	my $tag = shift;
	for my $t (@{$self->{tags}}) {
		return 1 if ($t eq $tag);
	}
	return 0;
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
	#for my $k (keys %tags) {
	#	print "$k\n";
	#	for my $p (@{$tags{$k}}) {
	#		print "  ", $p->{'name'}, "\n";
	#	}
	#}
}

sub tags($) {
    my @tags = split(/ /, shift);
    my $first_tag = shift @tags;
    my $goods = $tags{$first_tag};
    # go out early if there is nothing to do
    return $goods if (!$goods || !@tags);
    my @results;
    # now check that it contains all the other tags too
    NEEDLE: for my $n (@$goods) {
	    for my $t (@tags) {
		    last NEEDLE if (!$n->has_tag($t));
	    }
	    print "adding ", $n->{name}, "\n";
	    push(@results, $n);
    }
    return \@results;
}

sub all() {
	return values %needles;
}

1;
