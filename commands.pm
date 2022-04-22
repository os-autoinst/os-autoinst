# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package commands;

use Mojo::Base -strict;
use autodie ':all';

require IPC::System::Simple;
use Try::Tiny;
use Socket;
use POSIX '_exit', 'strftime';
use myjsonrpc;
use bmwqemu;
use Mojo::JSON 'to_json';
use Mojo::File 'path';

BEGIN {
    $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

# Automatically enables "strict", "warnings", "utf8" and Perl 5.10 features
use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::IOLoop::ReadWriteProcess 'process';
use Mojo::IOLoop::ReadWriteProcess::Session 'session';
use Mojo::Server::Daemon;
use File::Basename;
use Time::HiRes 'gettimeofday';

# borrowed from obs with permission from mls@suse.de to license as
# GPLv2+
sub _makecpiohead {
    my ($name, $s) = @_;
    return
"07070100000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000b00000000TRAILER!!!\0\0\0\0"
      if !$s;
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
    return $self->reply->not_found unless -d $base;

    $self->res->headers->content_type('application/x-cpio');

    my $data = '';
    for my $file (path($base)->list_tree->each) {
        $file = $file->to_string();
        my @s = stat $file;
        unless (@s) {
            $self->app->log->error("Error stating test distribution file '$file': $!");
            next;
        }
        my $fn = 'data/' . substr($file, length($base));
        local $/;    # enable localized slurp mode
        my $fd;
        eval { (open($fd, '<:raw', $file)) };
        if (my $E = $@) {
            $self->app->log->error("Error reading test distribution file '$file': $!");
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

    my $filetype;
    if ($file =~ m/\.([^\.]+)$/) {
        my $ext = $1;
        $filetype = $self->app->types->type($ext);
    }

    $filetype ||= 'application/octet-stream';
    $self->res->headers->content_type($filetype);
    return $self->reply->asset(Mojo::Asset::File->new(path => $file));
}

sub _is_allowed_path {
    my ($path) = @_;
    return !(!defined $path || $path =~ /^(.*\/)*\.\.(\/.*)*$/);    # do not allow .. in path
}

sub test_data {
    my ($self) = @_;

    my $path = path($bmwqemu::vars{CASEDIR}, 'data');
    my $relpath = $self->param('relpath');
    if (defined $relpath) {
        return $self->reply->not_found unless _is_allowed_path($relpath);
        $path = $path->child($relpath);
    }

    $self->app->log->info("Test data requested: $path");
    return _test_data_dir($self, $path) if -d $path;
    return _test_data_file($self, $path) if -f $path;
    return $self->reply->not_found;
}

sub get_asset {
    my ($self) = @_;

    my $asset_name = $self->param('assetname');
    my $asset_type = $self->param('assettype');
    return $self->reply->not_found unless _is_allowed_path($asset_name) && _is_allowed_path($asset_type);

    # check for the asset within the current working directory because the worker cache will store it here; otherwise
    # fallback to $bmwqemu::vars{ASSETDIR} for legacy setups (see poo#70723)
    my $relpath = $self->param('relpath');
    my $path = path($asset_name);
    $path = path($bmwqemu::vars{ASSETDIR}, $asset_type, $asset_name) unless -f $path;
    if (defined $relpath) {
        return $self->reply->not_found unless _is_allowed_path($relpath);
        $path = $path->child($relpath);
    }

    $self->app->log->info("Asset requested: $path");
    return _test_data_file($self, $path) if -f $path;
    return $self->reply->not_found;
}

# store the file in $pooldir/$target
sub upload_file {
    my ($self) = @_;

    my $req = $self->req;
    return $self->render(text => (($req->error // {})->{message} // 'Limit exceeded'), status => 400)
      if $req->is_limit_exceeded;
    return $self->render(text => 'Upload file content missing', status => 400)
      unless my $upload = $req->upload('upload');

# choose 'target' field from curl form, otherwise default 'assets_private', assume the pool directory is the current working dir
    my $target = $self->param('target') || 'assets_private';
    eval { mkdir $target unless -d $target };
    if (my $error = $@) { return $self->render(text => "Unable to create directory for upload: $error", status => 500) }

    my $upname = $self->param('upname');
    my $filename = basename($upname ? $upname : $self->param('filename'));
# note: Only renaming the file if upname parameter is present, e.g. from upload_logs(). With this it won't rename the file in
    #       case of upload_assert() and autoyast profiles as those are not done via upload_logs().

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

sub _handle_isotovideo_response {
    my ($app, $response) = @_;

    return undef unless $response->{stop_processing_isotovideo_commands};

    # stop processing isotovideo commands if isotovideo says so
    $app->log->debug('cmdsrv: stop processing isotovideo commands');
    $app->defaults(isotovideo => undef);
}

sub isotovideo_command {
    my ($mojo_lite_controller, $commands) = @_;

    my $cmd = $mojo_lite_controller->param('command');
    return $mojo_lite_controller->reply->not_found unless grep { $cmd eq $_ } @$commands;

    my $app = $mojo_lite_controller->app;
    return unless my $isotovideo = $app->defaults('isotovideo');

    # send command to isotovideo and block until a response arrives
    myjsonrpc::send_json($isotovideo, {cmd => $cmd, params => $mojo_lite_controller->req->query_params->to_hash});
    my $response = myjsonrpc::read_json($isotovideo);
    _handle_isotovideo_response($app, $response);

    return $mojo_lite_controller->render(json => $response);
}

sub isotovideo_get {
    my ($c) = @_;
    return isotovideo_command($c, [qw(version)]);
}

sub isotovideo_post {
    my ($c) = @_;
    return isotovideo_command($c, []);
}

sub get_temp_file {
    my ($self) = @_;
    my $relpath = $self->param('relpath');
    my $path = testapi::hashed_string($relpath);
    return _test_data_file($self, $path) if -f $path;
    return $self->reply->not_found;
}

sub run_daemon {
    my ($port, $isotovideo) = @_;

    # allow up to 20 GiB for uploads of big hdd images
    $ENV{MOJO_MAX_MESSAGE_SIZE} //= ($bmwqemu::vars{UPLOAD_MAX_MESSAGE_SIZE_GB} // 0) * 1024**3;
    $ENV{MOJO_INACTIVITY_TIMEOUT} //= ($bmwqemu::vars{UPLOAD_INACTIVITY_TIMEOUT} // 300);
    $ENV{MOJO_TMPDIR} //= path('command-server-tmp')->make_path;

    # avoid leaking token
    app->mode('production');
    app->log->level('info');
    app->log->debug('cmdsrv: run daemon ' . $isotovideo);
    # abuse the defaults to store singletons for the server
    app->defaults(isotovideo => $isotovideo);
    app->defaults(clients => {});

    my $r = app->routes;
    $r->namespaces(['OpenQA']);
    my $token_auth = $r->any("/$bmwqemu::vars{JOBTOKEN}");

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
    $token_auth->get('/assets/#assettype/#assetname' => \&get_asset);
    $token_auth->get('/assets/#assettype/#assetname/*relpath' => \&get_asset);

    # get vars
    $token_auth->get('/vars' => \&get_vars);

    $token_auth->get('/isotovideo/#command' => \&isotovideo_get);
    $token_auth->post('/isotovideo/#command' => \&isotovideo_post);

    # websocket related routes
    $token_auth->websocket('/ws')->name('ws')->to('commands#start_ws');
    $token_auth->post('/broadcast')->name('broadcast')->to('commands#broadcast_message_to_websocket_clients');

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
    # Use same log format as isotovideo
    app->log->format(\&bmwqemu::log_format_callback);
    # process json messages from isotovideo
    Mojo::IOLoop->singleton->reactor->io(
        $isotovideo => sub {
            my ($reactor, $writable) = @_;

            my @isotovideo_responses = myjsonrpc::read_json($isotovideo, undef, 1);
            my $clients = app->defaults('clients');
            for my $response (@isotovideo_responses) {
                _handle_isotovideo_response(app, $response);
                delete $response->{json_cmd_token};

                app->log->debug(
                    'cmdsrv: broadcasting message from os-autoinst to all ws clients: ' . to_json($response));
                for (keys %$clients) {
                    $clients->{$_}->send({json => $response});
                }
            }
        })->watch($isotovideo, 1, 0);    # watch only readable (and not writable)

    app->log->info("cmdsrv: daemon reachable under http://*:$port/$bmwqemu::vars{JOBTOKEN}/");
    try {
        $daemon->run;
    }
    catch {
        print "cmdsrv: failed to run daemon $_\n";
        _exit(1);
    };
}

sub start_server {
    my ($port) = @_;

    my ($child, $isotovideo);
    socketpair($child, $isotovideo, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
      or die "cmdsrv: socketpair: $!";

    $child->autoflush(1);
    $isotovideo->autoflush(1);

    my $process = process(
        sub {
            $SIG{TERM} = 'DEFAULT';
            $SIG{INT} = 'DEFAULT';
            $SIG{HUP} = 'DEFAULT';
            $SIG{CHLD} = 'DEFAULT';

            close($child);
            $0 = "$0: commands";
            run_daemon($port, $isotovideo);
            Devel::Cover::report() if Devel::Cover->can('report');
            _exit(0);
        },
        sleeptime_during_kill => 0.1,
        total_sleeptime_during_kill => 5,
        blocking_stop => 1,
        internal_pipes => 0,
        set_pipes => 0
    )->start;

    close($isotovideo);
    $process->on(collected => sub { bmwqemu::diag("commands process exited: " . shift->exit_status); });
    return ($process, $child);
}


1;
