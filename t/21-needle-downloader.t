#!/usr/bin/perl

use strict;
use warnings;

use File::Touch;
use File::Path qw(make_path remove_tree);
use Test::More;
use Test::MockModule;
use Test::Warnings;
use Test::Output 'stderr_like';
use Mojo::File qw(path tempdir);
use OpenQA::Isotovideo::NeedleDownloader;

BEGIN {
    unshift @INC, '..';
}

# mock user agent and file
my $user_agent_mock = Test::MockModule->new('Mojo::UserAgent');
my @queried_urls;
$user_agent_mock->mock(get => sub {
        my ($self, $url) = @_;
        push(@queried_urls, $url);
        return $user_agent_mock->original('get')->(@_);
});

# setup needle directory
my $needle_dir = path(tempdir, 'needle_dir');
ok(make_path($needle_dir), 'create test needle dir under ' . $needle_dir);

subtest 'deduce URL for needle download from test variable OPENQA_URL' => sub {
    $bmwqemu::vars{OPENQA_URL} = 'https://openqa1-opensuse';
    is(OpenQA::Isotovideo::NeedleDownloader->new()->openqa_url, 'https://openqa1-opensuse', 'existing scheme not overridden');
    $bmwqemu::vars{OPENQA_URL} = 'not/a/proper/hostname';
    is(OpenQA::Isotovideo::NeedleDownloader->new()->openqa_url, 'http:not/a/proper/hostname', 'hostname not present');
    $bmwqemu::vars{OPENQA_HOSTNAME} = 'openqa1-opensuse';
    is(OpenQA::Isotovideo::NeedleDownloader->new()->openqa_url, 'http://openqa1-opensuse', 'hostname taken from OPENQA_HOSTNAME if not present');
    $bmwqemu::vars{OPENQA_URL} = 'openqa';
    is(OpenQA::Isotovideo::NeedleDownloader->new()->openqa_url, 'http://openqa', 'domain is treated as host (and not relative path)');
    $bmwqemu::vars{OPENQA_URL} = 'localhost:9526';
    is(OpenQA::Isotovideo::NeedleDownloader->new()->openqa_url, 'http://localhost:9526', 'domain:port is treated as host + port (and not protocol + path)');
};

# setup a NeedleDownloader instance
$bmwqemu::vars{OPENQA_URL} = 'openqa';
my $downloader = OpenQA::Isotovideo::NeedleDownloader->new(
    needle_dir => $needle_dir,
);
is($downloader->download_limit, 150, 'by default limited to 150 downloads');

subtest 'add relevant downloads' => sub {
    my @new_needles = (
        {
            id         => 1,
            name       => 'foo',
            directory  => 'fixtures',
            tags       => [qw(some tag)],
            json_path  => '/needles/1/json',
            image_path => '/needles/1/image',
            t_created  => '2018-01-01T00:00:00Z',
            t_updated  => '2018-01-01T00:00:00Z',
        },
        {
            id         => 2,
            name       => 'bar',
            directory  => 'fixtures',
            tags       => [qw(yet another tag)],
            json_path  => '/needles/2/json',
            image_path => '/needles/2/image',
            t_created  => '2018-01-01T00:00:00Z',
            t_updated  => '2018-01-01T00:00:00Z',
        },
    );

    # pretend that ...
    # ... one file is already up to date (to the exact second)
    File::Touch->new(mtime => 1514764800)->touch($needle_dir . '/foo.png');
    # ... one file is present but outdated (by one second)
    File::Touch->new(mtime => 1514764799)->touch($needle_dir . '/bar.json');

    # define expected downloads: everything from @new_needles except foo.png
    my @expected_downloads = (
        {
            target => $needle_dir . '/foo.json',
            url    => 'http://openqa/needles/1/json',
        },
        {
            target => $needle_dir . '/bar.json',
            url    => 'http://openqa/needles/2/json',
        },
        {
            target => $needle_dir . '/bar.png',
            url    => 'http://openqa/needles/2/image',
        }
    );

    # actually add the downloads
    stderr_like(
        sub {
            $downloader->add_relevant_downloads(\@new_needles);
        },
        qr/.*skipping downloading new needle: $needle_dir\/foo\.png seems already up-to-date.*/,
        'skipped downloads logged'
    );
    is_deeply($downloader->files_to_download, \@expected_downloads, 'downloads added')
      or diag explain $downloader->files_to_download;

    subtest 'limit applied' => sub {
        $downloader->download_limit(3);
        $downloader->add_relevant_downloads(\@new_needles);
        is_deeply($downloader->files_to_download, \@expected_downloads, 'no more downloads added')
          or diag explain $downloader->files_to_download;
    };
};

subtest 'download added URLs' => sub {
    is_deeply(\@queried_urls, [], 'no URLs queried so far');

    stderr_like(
        sub {
            $downloader->download();
        },
        qr/.*download new needle.*\n.*failed to download.*server returned 404.*/,
        'errors logged'
    );

    is_deeply(\@queried_urls, [
            'http://openqa/needles/1/json',
            'http://openqa/needles/2/json',
            'http://openqa/needles/2/image',
    ], 'right URLs queried');
};

remove_tree($needle_dir);

done_testing;
