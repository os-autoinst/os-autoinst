# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package needle;

use strict;
use warnings;
use autodie ':all';

use Cwd 'cwd';
use File::Find;
use File::Spec;
use Mojo::File;
use Mojo::JSON 'decode_json';
use Cpanel::JSON::XS ();
use File::Basename;
use Try::Tiny;
require IPC::System::Simple;
use OpenQA::Benchmark::Stopwatch;
use OpenQA::Isotovideo::Utils 'checkout_git_refspec';

our %needles;
our %tags;
our $cleanuphandler;

my $needles_dir;

sub is_click_point_valid {
    my ($click_point) = @_;
    return (ref $click_point eq 'HASH'
          && $click_point->{xpos}
          && $click_point->{ypos})
      || $click_point eq 'center';
}

sub new {
    my ($classname, $jsonfile) = @_;

    die 'needles not initialized via needle::init() before needle constructor called' unless defined $needles_dir;

    my $json;
    if (ref $jsonfile eq 'HASH') {
        $json     = $jsonfile;
        $jsonfile = $json->{file} || File::Spec->catfile($needles_dir, $json->{name} . '.json');
    }

    my $self = {};

    # locate the needle's JSON file within the needle directory
    # - This code initializes $json->{file} so it contains the path within the needle directory.
    # - $jsonfile is re-assigned to contain the absolute path the the JSON file.
    # - The needle must be within the needle directory.
    if (index($jsonfile, $needles_dir) == 0) {
        $self->{file} = substr($jsonfile, length($needles_dir) + 1);
    }
    elsif (-f File::Spec->catfile($needles_dir, $jsonfile)) {
        # json file path already relative
        $self->{file} = $jsonfile;
        $jsonfile = File::Spec->catfile($needles_dir, $jsonfile);
    }
    else {
        die "Needle $jsonfile is not under needle directory $needles_dir";
    }

    if (!$json) {
        try {
            $json = decode_json(Mojo::File->new($jsonfile)->slurp);
        }
        catch {
            warn "broken json $jsonfile: $_";
        };
        return undef unless $json;
    }

    $self->{tags}       = $json->{tags}       || [];
    $self->{properties} = $json->{properties} || [];

    my $gotmatch;
    my $got_click_point;
    for my $area_from_json (@{$json->{area}}) {
        my $area = {};
        for my $tag (qw(xpos ypos width height)) {
            $area->{$tag} = $area_from_json->{$tag} || 0;
        }
        for my $tag (qw(processing_flags max_offset)) {
            $area->{$tag} = $area_from_json->{$tag} if $area_from_json->{$tag};
        }
        $area->{match}  = $area_from_json->{match} if $area_from_json->{match};
        $area->{type}   = $area_from_json->{type}   || 'match';
        $area->{margin} = $area_from_json->{margin} || 50;
        if (my $click_point = $area_from_json->{click_point}) {
            if ($got_click_point) {
                warn "$jsonfile has more than one area with a click point\n";
                return;
            }
            if (!is_click_point_valid($click_point)) {
                warn "$jsonfile has an area with invalid click point\n";
                return;
            }
            $got_click_point = 1;
            $area->{click_point} = $click_point;
        }

        $gotmatch = 1 if $area->{type} =~ /match|ocr/;

        $self->{area} ||= [];
        push @{$self->{area}}, $area;
    }

    # one match is mandatory
    unless ($gotmatch) {
        warn "$jsonfile missing match area\n";
        return;
    }

    $self->{name} = basename($jsonfile, '.json');
    my $png = $self->{png} || $self->{name} . ".png";

    $self->{png} = File::Spec->catdir(dirname($jsonfile), $png);

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
    for my $area_from_json (@{$self->{area}}) {
        my $area = {};
        for my $tag (qw(xpos ypos width height max_offset processing_flags match type margin)) {
            $area->{$tag} = $area_from_json->{$tag} if defined $area_from_json->{$tag};
        }
        push @area, $area;
    }
    my $json = Cpanel::JSON::XS->new->pretty->utf8->canonical->encode(
        {
            tags       => [sort(@{$self->{tags}})],
            area       => \@area,
            properties => [$self->{properties}],
        });
    open(my $fh, '>', $fn);
    print $fh $json;
    close $fh;
}

sub unregister {
    my ($self, $reason) = @_;
    for my $g (@{$self->{tags}}) {
        @{$tags{$g}} = grep { $_ != $self } @{$tags{$g}};
        delete $tags{$g} unless (@{$tags{$g}});
    }
    $self->{unregistered} //= $reason || 'unknown reason';
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

sub _load_image {
    my ($self, $image_path) = @_;

    # read PNG file measuring required time
    my $watch = OpenQA::Benchmark::Stopwatch->new();
    $watch->start();
    my $image = tinycv::read($image_path);
    $watch->stop();
    if ($watch->as_data()->{total_time} > 0.1) {
        bmwqemu::diag(sprintf("load of $image_path took %.2f seconds", $watch->as_data()->{total_time}));
    }
    return undef unless $image;

    # call replacerect for exclude areas
    for my $area (@{$self->{area}}) {
        next unless $area->{type} eq 'exclude';
        $image->replacerect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height});
    }

    return {
        image      => $image,
        image_path => $image_path,
    };
}

my %image_cache;
my $image_cache_tick = 0;

sub _load_image_with_caching {
    my ($self) = @_;

    # insert newly loaded image to cache or recycle previously cached image
    my $image_path       = $self->{png};
    my $image_cache_item = $image_cache{$image_path};
    if (!$image_cache_item) {
        my $new_image_cache_item = $self->_load_image($image_path);
        return undef unless $new_image_cache_item;

        $image_cache_item = $image_cache{$image_path} = $new_image_cache_item;
    }

    $image_cache_item->{last_use} = ++$image_cache_tick;

    return $image_cache_item->{image};
}

sub clean_image_cache {
    my ($limit) = @_;
    $limit //= 30;

    # compute the number of images to delete
    my @cache_items = values %image_cache;
    my $cache_size  = scalar @cache_items;
    my $to_delete   = $cache_size - $limit;
    return unless $to_delete > 0 && $to_delete <= $cache_size;

    # sort the cache items by their last use (ascending)
    my @sorted_cache_items = sort { $a->{last_use} <=> $b->{last_use} } @cache_items;

    # determine the minimum last use to lower the cache tick (so it won't overflow)
    my $min_last_use = $to_delete == $cache_size ? $image_cache_tick : $sorted_cache_items[$to_delete]->{last_use};
    $image_cache_tick -= $min_last_use;

    my $index = -1;
    for my $image_cache_item (@sorted_cache_items) {
        if (++$index < $to_delete) {
            # delete cache items up to the number of items to delete
            delete $image_cache{$image_cache_item->{image_path}};
        }
        else {
            # adapt last_use of items to keep to new $image_cache_tick
            $image_cache_item->{last_use} -= $min_last_use;
        }
    }
}

sub image_cache_size {
    return scalar keys %image_cache;
}

sub get_image {
    my ($self, $area) = @_;

    my $image = $self->_load_image_with_caching;
    return undef  unless $image;
    return $image unless $area;
    return $area->{img} //= $image->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height});
}

sub has_tag {
    my ($self, $tag) = @_;
    for my $t (@{$self->{tags}}) {
        return 1 if ($t eq $tag);
    }
    return 0;
}

sub has_property {
    my ($self, $property_name) = @_;

    return grep { ref($_) eq "HASH" ? $_->{name} eq $property_name : $_ eq $property_name } @{$self->{properties}};
}

sub get_property_value {
    my ($self, $property_name) = @_;

    for my $property (@{$self->{properties}}) {
        if (ref($property) eq "HASH") {
            return $property->{value} if ($property->{name} eq $property_name);
        }
    }
    if ($property_name eq "workaround") {
        if ($self->{name} =~ /\S+\-(bsc|poo|bnc|boo)(\d+)\-\S+/) {
            return $1 . "#" . $2;
        }
    }
    return undef;
}

sub TO_JSON {
    my ($self) = @_;

    my %hash = map { $_ => $self->{$_} } qw(tags properties area file png unregistered name);
    return \%hash;
}

sub wanted_ {
    return unless (m/.json$/);
    my $needle = needle->new($File::Find::name);
    if ($needle) {
        $needles{$needle->{name}} = $needle;
    }
}

sub default_needles_dir {
    return "$bmwqemu::vars{PRODUCTDIR}/needles";
}

sub init {
    $needles_dir = ($bmwqemu::vars{NEEDLES_DIR} // default_needles_dir);
    $needles_dir = File::Spec->catdir($bmwqemu::vars{CASEDIR}, $needles_dir) unless -d $needles_dir;
    die "needles_dir not found: $needles_dir (check vars.json?)" unless -d $needles_dir;
    $bmwqemu::vars{NEEDLES_GIT_HASH} = checkout_git_refspec($needles_dir => 'NEEDLES_GIT_REFSPEC');

    %needles = ();
    %tags    = ();
    bmwqemu::diag("init needles from $needles_dir");
    find({no_chdir => 1, wanted => \&wanted_, follow => 1}, $needles_dir);
    bmwqemu::diag(sprintf("loaded %d needles", scalar keys %needles));

    if ($cleanuphandler) {
        &$cleanuphandler();
    }

    return $needles_dir;
}

sub needles_dir { $needles_dir; }

sub set_needles_dir { ($needles_dir) = @_; }

sub tags {
    my ($wanted)  = @_;
    my @wanted    = split(/ /, $wanted);
    my $first_tag = shift @wanted;
    my $goods     = $tags{$first_tag};

    # go out early if there is nothing to do
    if (!$goods || !@wanted) {
        return $goods || [];
    }
    my @results;

    # now check that it contains all the other tags too
  NEEDLE: for my $n (@$goods) {
        for my $t (@wanted) {
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
