# Copyright © 2018-2021 SUSE LLC
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

package OpenQA::Isotovideo::NeedleDownloader;
use Mojo::Base -base, -signatures;

use Mojo::UserAgent;
use Mojo::URL;
use Mojo::File;
use File::stat;
use Try::Tiny;
use POSIX 'strftime';
use bmwqemu;
use needle;

has files_to_download => sub { [] };
has openqa_url        => sub {
    # deduce the default openQA URL from OPENQA_URL/OPENQA_HOSTNAME
    # note: OPENQA_URL is sometimes just the hostname (eg. e212.suse.de) but might be a proper URL
    #       as well (eg. http://openqa1-opensuse).
    my $url  = Mojo::URL->new($bmwqemu::vars{OPENQA_URL});
    my $host = $bmwqemu::vars{OPENQA_HOSTNAME};

    # determine host if not present in OPENQA_URL
    if (!$url->host) {
        my $path_parts = $url->path->parts;
        if (scalar @$path_parts == 1) {
            if ($url->scheme) {
                # treat URLs like 'localhost:9526' in the way that 'localhost' is the hostname (and not the protocol)
                $url->host($url->scheme);
                $url->port($path_parts->[0]);
                $url->scheme('');
            }
            else {
                # treat URLs like just 'e212.suse.de' in the way that 'e212.suse.de' is the hostname (and not a relative path)
                $url->host($path_parts->[0]);
            }
            $url->path(Mojo::Path->new);
        }
        elsif ($host) {
            # build a default URL from OPENQA_HOSTNAME if no host in OPENQA_URL is missing
            $url = Mojo::URL->new();
            $url->scheme('');
            $url->host($host);
        }
    }

    # assume 'http' if scheme is missing
    if (!$url->scheme) {
        $url->scheme('http');
    }

    return $url;
};
has ua             => sub { Mojo::UserAgent->new };
has download_limit => 150;

sub _add_download ($self, $needle, $extension, $path_param) {
    my $needle_name     = $needle->{name};
    my $latest_update   = $needle->{t_updated};
    my $needles_dir     = needle::needles_dir();
    my $download_target = "$needles_dir/$needle_name.$extension";

    if (my $target_stat = stat($download_target)) {
        if (my $target_last_modified = $target_stat->[9] // $target_stat->[8]) {
            $target_last_modified = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($target_last_modified));
            if ($target_last_modified ge $latest_update) {
                bmwqemu::diag("skipping downloading new needle: $download_target seems already up-to-date (last update: $target_last_modified > $latest_update)");
                return;
            }
        }
    }

    push(@{$self->files_to_download}, {
            target => $download_target,
            url    => Mojo::URL->new($self->openqa_url . $needle->{$path_param}),
    });
}

sub _download_file ($self, $download) {
    my $download_url    = $download->{url};
    my $download_target = $download->{target};
    bmwqemu::diag("download new needle: $download_url => $download_target");

    # download the file
    my $download_res;
    try {
        $download_res = $self->ua->get($download_url)->result;
        if (!$download_res->is_success) {
            my $return_code = $download_res->code;
            bmwqemu::diag("failed to download $download_url, server returned $return_code");
            $download_res = undef;
        }
    }
    catch {
        bmwqemu::diag("internal error occurred when downloading $download_url: $_");
    };

    # store the file on disk
    return unless ($download_res);
    try {
        unlink($download_target);
        Mojo::File->new($download_target)->spurt($download_res->body);
    }
    catch {
        bmwqemu::diag("unable to store download under $download_target");
    };
}

# adds downloads for the specified $new_needles if those are missing/outdated locally
sub add_relevant_downloads ($self, $new_needles) {
    my $download_limit  = $self->download_limit;
    my $added_downloads = $self->files_to_download;
    for my $needle (@$new_needles) {
        last if (scalar @$added_downloads >= $download_limit);
        $self->_add_download($needle, 'json', 'json_path');
        $self->_add_download($needle, 'png',  'image_path');
    }
}

# downloads previously added downloads
sub download ($self) { $self->_download_file($_) for (@{$self->files_to_download}) }

# downloads missing needles considering $new_needles
# (see t/21-needle-downloader.t for an example of $new_needles)
sub download_missing_needles ($self, $new_needles) {
    $self->add_relevant_downloads($new_needles);
    $self->download();
}

1;
