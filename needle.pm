package needle;

use strict;
use warnings;
use Cwd qw/abs_path/;
use File::Find;
use File::Spec;
use JSON;
use File::Basename;
require IPC::System::Simple;
use autodie qw(:all);

our %needles;
our %tags;
our $needledir;
our $cleanuphandler;

sub new {
    my ($classname, $jsonfile) = @_;

    my $json;
    if (ref $jsonfile eq 'HASH') {
        $json = $jsonfile;
        $jsonfile = join('/', $needledir, $json->{name} . '.json');
    }
    else {
        local $/;
        # TODO preserving old behaviour, why should failing read be allowed?
        no autodie qw(open);
        open(my $fh, '<', $jsonfile);
        eval { $json = decode_json(<$fh>) };
        close($fh);
        if (!$json || $@) {
            warn "broken json $jsonfile: $@";
            return;
        }
    }
    my $self = {tags => ($json->{tags} || [])};
    $self->{properties} = $json->{properties} || [];

    my $gotmatch;
    for my $area (@{$json->{area}}) {
        my $a = {};
        for my $tag (qw/xpos ypos width height/) {
            $a->{$tag} = $area->{$tag} || 0;
        }
        for my $tag (qw/processing_flags max_offset/) {
            $a->{$tag} = $area->{$tag} if $area->{$tag};
        }
        $a->{match} = $area->{match} if $area->{match};
        $a->{type}   = $area->{type}   || 'match';
        $a->{margin} = $area->{margin} || 50;

        $gotmatch = 1 if $a->{type} eq 'match';

        $self->{area} ||= [];
        push @{$self->{area}}, $a;
    }

    # one match is mandatory
    unless ($gotmatch) {
        warn "$jsonfile missing match area\n";
        return;
    }

    $self->{file} = $jsonfile;
    $self->{name} = basename($jsonfile, '.json');
    my $png = $self->{png} || $self->{name} . ".png";
    $self->{png} = File::Spec->catpath('', dirname($jsonfile), $png);
    if (!-s $self->{png}) {
        warn "Can't find $self->{png}";
        return;
    }

    $self = bless $self, $classname;
    $self->register();
    return $self;
}

sub save {
    my ($self, $fn) = @_;
    $fn ||= $self->{file};
    my @area;
    for my $a (@{$self->{area}}) {
        my $aa = {};
        for my $tag (qw/xpos ypos width height max_offset processing_flags match type margin/) {
            $aa->{$tag} = $a->{$tag} if defined $a->{$tag};
        }
        push @area, $aa;
    }
    my $json = JSON->new->pretty->utf8->canonical->encode(
        {
            tags       => [sort(@{$self->{tags}})],
            area       => \@area,
            properties => [sort(@{$self->{properties}})],
        });
    open(my $fh, '>', $fn);
    print $fh $json;
    close $fh;
}

sub unregister {
    my ($self) = @_;
    for my $g (@{$self->{tags}}) {
        @{$tags{$g}} = grep { $_ != $self } @{$tags{$g}};
        delete $tags{$g} unless (@{$tags{$g}});
    }
}

sub register {
    my ($self) = @_;
    my %check_dups;
    for my $g (@{$self->{tags}}) {
        if ($check_dups{$g}) {
            bmwqemu::diag("$self->{name} contains $g twice");
            next;
        }
        $check_dups{$g} = 1;
        $tags{$g} ||= [];
        push(@{$tags{$g}}, $self);
    }
}

sub get_image {
    my ($self, $area) = @_;

    if (!$self->{img}) {
        $self->{img} = tinycv::read($self->{png});
        for my $a (@{$self->{area}}) {
            next unless $a->{type} eq 'exclude';
            $self->{img}->replacerect($a->{xpos}, $a->{ypos}, $a->{width}, $a->{height});
        }
    }

    return $self->{img} unless $area;

    if (!$area->{img}) {
        $area->{img} = $self->{img}->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height});
    }
    return $area->{img};
}

sub has_tag {
    my ($self, $tag) = @_;
    for my $t (@{$self->{tags}}) {
        return 1 if ($t eq $tag);
    }
    return 0;
}

sub has_property {
    my ($self, $tag) = @_;
    for my $t (@{$self->{properties}}) {
        return 1 if ($t eq $tag);
    }
    return 0;
}

sub TO_JSON {
    my ($self) = @_;

    my $hash = {
        tags       => $self->{tags},
        properties => $self->{properties},
        area       => $self->{area},
        file       => $self->{file},
        png        => $self->{png},
        name       => $self->{name}};
    return $hash;
}

sub wanted_ {
    return unless (m/.json$/);
    my $needle = needle->new($File::Find::name);
    if ($needle) {
        $needles{$needle->{name}} = $needle;
    }
}

sub init {
    $needledir = shift if @_;
    $needledir //= "$bmwqemu::vars{CASEDIR}/needles/";
    $needledir = abs_path($needledir) // die "needledir not found: $needledir (check vars.json?)";

    %needles = ();
    %tags    = ();
    bmwqemu::diag("init needles from $needledir");
    find({no_chdir => 1, wanted => \&wanted_, follow => 1}, $needledir);
    bmwqemu::diag(sprintf("loaded %d needles", scalar keys %needles));

    if ($cleanuphandler) {
        &$cleanuphandler();
    }
}

sub tags {
    my @tags      = split(/ /, shift);
    my $first_tag = shift @tags;
    my $goods     = $tags{$first_tag};

    # go out early if there is nothing to do
    if (!$goods || !@tags) {
        return $goods || [];
    }
    my @results;

    # now check that it contains all the other tags too
  NEEDLE: for my $n (@$goods) {
        for my $t (@tags) {
            next NEEDLE if (!$n->has_tag($t));
        }
        print "adding ", $n->{name}, "\n";
        push(@results, $n);
    }
    return \@results;
}

sub all {
    return values %needles;
}

1;

# vim: set sw=4 et:

