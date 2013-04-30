package needle;

use strict;
use warnings;
use File::Find;
use File::Spec;
use Data::Dump;
use JSON;
use File::Basename;

our %needles;
our %tags;

sub new($) {
    my $classname=shift;
    my $jsonfile=shift;
    local $/;
    open( my $fh, '<', $jsonfile ) || return undef;
    my $json = decode_json( <$fh> ) || die "broken json $jsonfile";
    close($fh);
    my $self = {
	tags => ($json->{'tags'} || [])
    };

    my $gotmatch;
    for my $area (@{$json->{'area'}}) {
	my $a = {};
	for my $tag (qw/xpos ypos width height/) {
	    $a->{$tag} = $area->{$tag} || 0;
	}
	for my $tag (qw/processing_flags max_offset/) {
	    $a->{$tag} = $area->{$tag} if $area->{$tag};
	}
	$a->{'match'} = $area->{'match'} if $area->{'match'};
	$a->{'type'} = $area->{'type'} || 'match';

	$gotmatch = 1 if $a->{'type'} eq 'match';

	$self->{'area'} ||= [];
	push @{$self->{'area'}}, $a;
    }

    # one match is mandatory
    unless ($gotmatch) {
	warn "$jsonfile missing match area\n";
	return undef;
    }

    $self->{file} = $jsonfile;
    $self->{name} = basename($jsonfile, '.json');
    my $png = $self->{png} || $self->{name} . ".png";
    $self->{png} = File::Spec->catpath('', dirname($jsonfile), $png);
    if (! -s $self->{png}) {
      die "Can't find $self->{png}";
    }

    $self = bless $self, $classname;
    $self->register();
    return $self;
}

sub save($;$)
{
    my $self = shift;
    my $fn = shift || $self->{'file'};
    my @area;
    for my $a (@{$self->{'area'}}) {
	my $aa = {};
	for my $tag (qw/xpos ypos width height max_offset processing_flags match type/) {
	    $aa->{$tag} = $a->{$tag} if defined $a->{$tag};
	}
	push @area, $aa;
    }
    my $json = JSON->new->pretty->utf8->canonical->encode(
      {
	tags => [sort(@{$self->{'tags'}})],
	area => \@area,
      }
    );
    open(my $fh, '>', $fn) || die "can't open $fn for writing: $!\n";
    print $fh $json;
    close $fh;
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

sub get_image($$) {
    my $self=shift;
    my $area = shift;

    if (!$self->{'img'}) {
	$self->{'img'} = tinycv::read($self->{'png'});
	for my $a (@{$self->{'area'}}) {
	    next unless $a->{'type'} eq 'exclude';
	    $self->{'img'}->replacerect(
		$a->{'xpos'}, $a->{'ypos'},
		$a->{'width'}, $a->{'height'});
	}
    }

    return $self->{'img'} unless $area;

    if (!$area->{'img'}) {
	$area->{'img'} = $self->{'img'}->copyrect(
	    $area->{'xpos'},
	    $area->{'ypos'},
	    $area->{'width'},
	    $area->{'height'}
	);
    }
    return $area->{'img'};
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

our $needledir;

sub get_needle_dir {
  return $needledir;
}

sub init($) {
	$needledir=shift;
	find( { no_chdir => 1, wanted => \&wanted_ }, $needledir );
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

# Local Variables:
# tab-width: 8
# cperl-indent-level: 8
# End:
