# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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

package commands;

use strict;
use warnings;
require IPC::System::Simple;
use Try::Tiny;
use Socket;
use POSIX '_exit', 'strftime';
use autodie ':all';
use myjsonrpc;


BEGIN {
    # https://github.com/os-autoinst/openQA/issues/450
    $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

# Automatically enables "strict", "warnings", "utf8" and Perl 5.10 features
use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use File::Basename;
use Time::HiRes 'gettimeofday';

# a socket opened to isotovideo
my $isotovideo;

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

    # choose 'target' field from curl form, otherwise default 'assets_private'
    my $target = $self->param('target') || 'assets_private';

    # global assumption cwd == pooldir
    if (!-d $target) {
        mkdir($target) or die "$!";
    }

    my $upname   = $self->param('upname');
    my $filename = basename($self->param('filename'));
    # Only renaming the file if upname parameter has posted ie. from upload_logs()
    # With this it won't renamed the file in case upload_assert and autoyast profile
    # as those are not called from upload_logs.
    if ($upname) {
        $filename = basename($upname);
    }

    $upload->move_to("$target/$filename");

    return $self->render(text => "OK: $filename\n");
}

sub get_vars {
    my ($self) = @_;

    bmwqemu::load_vars();
    return $self->render(json => {vars => \%bmwqemu::vars});
}

sub current_script {
    my ($self) = @_;
    return $self->reply->asset(Mojo::Asset::File->new(path => 'current_script'));
}

sub isotovideo_command {
    # $c is the lite controller - not the package
    my ($c, $commands) = @_;
    my $cmd = $c->param('command');
    return $c->reply->not_found unless grep { $cmd eq $_ } @$commands;
    myjsonrpc::send_json($isotovideo, {cmd => $cmd, params => $c->req->query_params->to_hash});
    $c->render(json => myjsonrpc::read_json($isotovideo));
    return;
}

sub isotovideo_get {
    my ($c) = @_;
    return isotovideo_command($c, [qw(status version)]);
}

sub isotovideo_post {
    my ($c) = @_;
    return isotovideo_command($c, []);
}

sub get_temp_file {
    my ($self)  = @_;
    my $relpath = $self->param('relpath');
    my $path    = testapi::hashed_string($relpath);
    return _test_data_file($self, $path) if -f $path;
    return $self->reply->not_found;
}


sub run_daemon {
    my ($port) = @_;

    # allow up to 20GB - hdd images
    $ENV{MOJO_MAX_MESSAGE_SIZE}   = 1024 * 1024 * 1024 * 20;
    $ENV{MOJO_INACTIVITY_TIMEOUT} = 300;

    # avoid leaking token
    app->mode('production');
    app->log->level('debug');
    app->stash(isotovideo => $isotovideo);

    my $r = app->routes;
    $r->namespaces(['OpenQA']);
    my $token_auth = $r->route("/$bmwqemu::vars{JOBTOKEN}");

    # for access all data as CPIO archive
    $token_auth->get('/data' => \&test_data);

    # to access a single file or a subdirectory
    $token_auth->get('/data/*relpath' => \&test_data);

    # uploading log files from tests
    $token_auth->post('/uploadlog/#filename' => {target => 'ulogs'} => [target => [qw(ulogs)]] => \&upload_file);

    # uploading assets
    $token_auth->post('/upload_asset/#filename' => [target => [qw(assets_private assets_public)]] => \&upload_file);

    # to get the current bash script out of the test
    $token_auth->get('/current_script' => \&current_script);

    # to get temporary files from the current worker
    $token_auth->get('/files/*relpath' => \&get_temp_file);

    # get asset
    $token_auth->get('/assets/#assettype/#assetname'          => \&get_asset);
    $token_auth->get('/assets/#assettype/#assetname/*relpath' => \&get_asset);

    # get vars
    $token_auth->get('/vars' => \&get_vars);

    $token_auth->get('/isotovideo/#command' => \&isotovideo_get);
    $token_auth->post('/isotovideo/#command' => \&isotovideo_post);

    $token_auth->websocket('/ws')->name('ws')->to('commands#start_ws');
    $token_auth->get('/developer')->to('commands#developer');

    # not known by default mojolicious
    app->types->type(oga => 'audio/ogg');

    # it's unlikely that we will ever use cookies, but we need a secret to shut up mojo
    app->secrets([$bmwqemu::vars{JOBTOKEN}]);

    # listen to all IPv4 and IPv6 interfaces (if ipv6 is supported)
    my $address = '[::]';
    if (!IO::Socket::IP->new(Listen => 5, LocalAddr => $address)) {
        $address = '0.0.0.0';
    }
    my $daemon = Mojo::Server::Daemon->new(app => app, listen => ["http://$address:$port"]);
    $daemon->silent;
    # We need to override the default logging format
    app->log->format(
        sub {
            my ($time, $level, @lines) = @_;
            # Unfortunately $time doesn't have the precision we want. So we need to use Time::HiRes
            $time = gettimeofday;
            return sprintf(strftime("[%FT%T.%%04d %Z] [$level] ", localtime($time)), 1000 * ($time - int($time))) . join("\n", @lines, '');
        });
    app->log->info("Daemon reachable under http://*:$port/$bmwqemu::vars{JOBTOKEN}/");
    try {
        $daemon->run;
    }
    catch {
        print "failed to run daemon $_\n";
        _exit(1);
    };
}

sub start_server {
    my ($port) = @_;

    my $child;
    socketpair($child, $isotovideo, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
      or die "socketpair: $!";

    $child->autoflush(1);
    $isotovideo->autoflush(1);

    my $pid = fork();
    die "fork failed" unless defined $pid;

    if ($pid == 0) {
        $SIG{TERM} = 'DEFAULT';
        $SIG{INT}  = 'DEFAULT';
        $SIG{HUP}  = 'DEFAULT';
        $SIG{CHLD} = 'DEFAULT';

        close($child);
        $0 = "$0: commands";
        run_daemon($port);
        Devel::Cover::report() if Devel::Cover->can('report');
        _exit(0);
    }
    close($isotovideo);

    return ($pid, $child);
}


1;
