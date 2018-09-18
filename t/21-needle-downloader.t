#!/usr/bin/perl

use strict;
use warnings;
use File::Touch;
use File::Path qw(make_path remove_tree);
use Test::More;
use Test::MockModule;
use Test::Warnings;
use Mojo::File qw(path tempdir);
use OpenQA::Isotovideo::NeedleDownloader;

BEGIN {
    unshift @INC, '..';
}

# mock user agent and file
my $user_agent_mock = new Test::MockModule('Mojo::UserAgent');
my @queried_urls;
$user_agent_mock->mock(get => sub {
        my ($self, $url) = @_;
        push(@queried_urls, $url);
        return $user_agent_mock->original('get')->(@_);
});

$bmwqemu::vars{OPENQA_URL} = 'openqa';

# setup a NeedleDownloader instance
my $needle_dir = path(tempdir, 'needle_dir');
ok(make_path($needle_dir), 'create test needle dir under ' . $needle_dir);
my $downloader = OpenQA::Isotovideo::NeedleDownloader->new(
    needle_dir => $needle_dir,
);
is($downloader->openqa_url, 'http://openqa', 'default openQA URL');

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
    $downloader->add_relevant_downloads(\@new_needles);
    is_deeply($downloader->files_to_download, \@expected_downloads, 'downloads added')
      or diag explain $downloader->files_to_download;
};

subtest 'download added URLs' => sub {
    is_deeply(\@queried_urls, [], 'no URLs queried so far');

    $downloader->download();
    is_deeply(\@queried_urls, [
            'http://openqa/needles/1/json',
            'http://openqa/needles/2/json',
            'http://openqa/needles/2/image',
    ], 'right URLs queried');
};

remove_tree($needle_dir);

done_testing;
