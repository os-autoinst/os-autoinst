package commands;

use threads;
use threads::shared;

use strict;
use warnings;
require IPC::System::Simple;
use autodie qw(:all);

BEGIN {
    # https://github.com/os-autoinst/openQA/issues/450
    $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

# Automatically enables "strict", "warnings", "utf8" and Perl 5.10 features
use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::Server::Daemon;

use File::Basename;

# borrowed from obs with permission from mls@suse.de to license as
# GPLv2+
sub _makecpiohead {
    my ($name, $s) = @_;
    return "07070100000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000b00000000TRAILER!!!\0\0\0\0" if !$s;
    #        magic ino
    my $h = "07070100000000";
    # mode                S_IFREG
    $h .= sprintf("%08x", oct(100000) | $s->[2] & oct(777));
    #      uid     gid     nlink
    $h .= "000000000000000000000001";
    $h .= sprintf("%08x%08x", $s->[9], $s->[7]);
    $h .= "00000000000000000000000000000000";
    $h .= sprintf("%08x", length($name) + 1);
    $h .= "00000000$name\0";
    $h .= substr("\0\0\0\0", (length($h) & 3)) if length($h) & 3;
    my $pad = '';
    $pad = substr("\0\0\0\0", ($s->[7] & 3)) if $s->[7] & 3;
    return ($h, $pad);
}

# send test data as cpio archive
sub _test_data_dir {
    my ($self, $base) = @_;

    $base .= '/' if $base !~ /\/$/;

    $self->app->log->debug("Request for directory $base.");

    return $self->reply->not_found unless -d $base;

    $self->res->headers->content_type('application/x-cpio');

    my $data = '';
    for my $file (glob $base . '*') {
        next unless -f $file;
        my @s = stat _;
        unless (@s) {
            $self->app->log->error("error stating $file: $!");
            next;
        }
        my $fn = 'data/' . substr($file, length($base));
        local $/;    # enable localized slurp mode
        my $fd;
        eval { (open($fd, '<:raw', $file)) };
        if (my $E = $@) {
            $self->app->log->error("error reading $file: $!");
            next;
        }
        my ($header, $pad) = _makecpiohead($fn, \@s);
        $data .= $header;
        $data .= <$fd>;
        close $fd;
        $data .= $pad if $pad;
    }
    $data .= _makecpiohead();
    return $self->render(data => $data);
}

# serve a file from within data directory
sub _test_data_file {
    my ($self, $file) = @_;

    $self->app->log->debug("Request for file $file.");

    my $filetype;

    if ($file =~ m/\.([^\.]+)$/) {
        my $ext = $1;
        $filetype = $self->app->types->type($ext);
    }

    $filetype ||= "application/octet-stream";
    $self->res->headers->content_type($filetype);

    return $self->reply->asset(Mojo::Asset::File->new(path => $file));
}

sub test_data {
    my ($self) = @_;

    my $path    = $bmwqemu::vars{CASEDIR} . "/data/";
    my $relpath = $self->param('relpath');
    if (defined $relpath) {
        # do not allow .. in path
        return $self->reply->not_found if $relpath =~ /^(.*\/)*\.\.(\/.*)*$/;
        $path .= $relpath;
    }

    return _test_data_dir($self, $path) if -d $path;
    return _test_data_file($self, $path) if -f $path;

    return $self->reply->not_found;
}

sub get_asset {
    my ($self) = @_;

    my $path = join '/', $bmwqemu::vars{ASSETDIR}, $self->param('assettype'), $self->param('assetname');
    my $relpath = $self->param('relpath');
    if (defined $relpath) {
        # do not allow .. in path
        return $self->reply->not_found if $relpath =~ /^(.*\/)*\.\.(\/.*)*$/;
        $path .= '/' . $relpath;
    }

    return _test_data_file($self, $path) if -f $path;

    return $self->reply->not_found;
}

# store the file in $pooldir/$target
sub upload_file {
    my ($self) = @_;

    if ($self->req->is_limit_exceeded) {
        return $self->render(
            message => 'File is too big.',
            status  => 400
        );
    }

    my $upload = $self->req->upload('upload');
    if (!$upload) {
        return $self->render(message => 'upload file content missing', status => 400);
    }

    my $target = $self->param('target');

    # global assumption cwd == pooldir
    if (!-d $target) {
        mkdir($target) or die "$!";
    }

    my $upname = basename($self->param('filename'));

    $upload->move_to("$target/$upname");

    return $self->render(text => "OK: $upname\n");
}


our $current_test_script : shared;

sub current_script {
    my ($self) = @_;
    return $self->render(data => $current_test_script);
}

sub run_daemon {
    my ($port) = @_;

    # avoid leaking token
    app->mode('production');

    my $r          = app->routes;
    my $token_auth = $r->route("/$bmwqemu::vars{JOBTOKEN}");

    # for access all data as CPIO archive
    $token_auth->get('/data' => \&test_data);

    # to access a single file or a subdirectory
    $token_auth->get('/data/*relpath' => \&test_data);

    # uploading log files from tests
    $token_auth->post('/uploadlog/#filename' => {target => 'ulogs'} => [target => [qw(ulogs)]] => \&upload_file);

    # uploading assets
    $token_auth->post('/upload_asset/#filename' => {target => 'assets_private'} => [target => [qw(assets_private assets_public)]] => \&upload_file);

    # to get the current bash script out of the test
    $token_auth->get('/current_script' => \&current_script);

    # get asset
    $token_auth->get('/assets/#assettype/#assetname'          => \&get_asset);
    $token_auth->get('/assets/#assettype/#assetname/*relpath' => \&get_asset);

    # not known by default mojolicious
    app->types->type(oga => 'audio/ogg');

    # it's unlikely that we will ever use cookies, but we need a secret to shut up mojo
    app->secrets([$bmwqemu::vars{JOBTOKEN}]);

    my $daemon = Mojo::Server::Daemon->new(app => app, listen => ["http://*:$port"]);
    $daemon->silent;
    app->log->info("Daemon reachable under http://*:$port/$bmwqemu::vars{JOBTOKEN}/");
    $daemon->run;
}

sub start_server {
    my ($port) = @_;

    my $thr = threads->create(\&run_daemon, $port);
    return $thr;
}

1;

# vim: set sw=4 et:
