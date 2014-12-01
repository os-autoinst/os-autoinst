package commands;

use threads;
use threads::shared;

# Automatically enables "strict", "warnings", "utf8" and Perl 5.10 features
use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::Server::Daemon;

use File::Basename;
use Data::Dump;

# make sure only our local VMs access
sub check_authorized {
    my ($self) = @_;

    # allow remote access if they set a password and use it
    return 1 if ($bmwqemu::vars{'CONNECT_PASSWORD'}
        && $self->param('connect_password')
        && $bmwqemu::vars{'CONNECT_PASSWORD'} eq $self->param('connect_password'));

    my $ip    = $self->tx->remote_address;
    $self->app->log->debug("Request from $ip.");

    return 1 if ($ip eq "127.0.0.1" || $ip eq "::1");

    # forbid everyone else
    $self->render(text => "IP $ip is denied", status => 403);
    return undef;
}

# borrowed from obs with permission from mls@suse.de to license as
# GPLv2+
sub _makecpiohead {
    my ($name, $s) = @_;
    return "07070100000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000b00000000TRAILER!!!\0\0\0\0" if !$s;
    #        magic ino
    my $h = "07070100000000";
    # mode                S_IFREG
    $h .= sprintf("%08x", 0100000 | $s->[2]&0777);
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
sub test_data {
    my $self = shift;
    my $base = $bmwqemu::vars{'CASEDIR'} . "/data/";

    return $self->render_not_found unless -d $base;

    $self->res->headers->content_type('application/x-cpio');

    my $data = '';
    for my $file (glob $base.'*') {
        next unless -f $file;
        my @s = stat _;
        unless (@s) {
            $self->app->log->error("error stating $file: $!");
            next;
        }
        my $fn = 'data/'.substr($file, length($base));
        local $/; # enable localized slurp mode
        my $fd;
        unless (open($fd, '<:raw', $file)) {
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

# store the log file in $pooldir/ulogs
sub upload_log {
    my ($self) = @_;

    if ($self->req->is_limit_exceeded) {
        return $self->render(
            message => 'File is too big.',
            status => 400
        );
    }

    my $upload = $self->req->upload('upload');
    if (!$upload) {
        return $self->render(message => 'upload file content missing', status => 400);
    }

    # global assumption cwd == pooldir
    if (!-d 'ulogs') {
        mkdir("ulogs") or die "$!";
    }

    my $upname = basename($self->param('filename'));

    $upload->move_to("ulogs/$upname");

    return $self->render(text => "OK: $upname\n");
}

# serve a file from within data directory
sub test_file {
    my ($self) = @_;

    my $file = $self->param('filename');
    $file = $bmwqemu::vars{'CASEDIR'} . "/data/" . $file;

    $self->app->log->debug("Request for $file.");

    my $fd;
    unless (open($fd, '<:raw', $file)) {
        # ERROR HANDLING
        $self->render(text => "Can't open $file", status => 404);
        return;
    }
    local $/ = undef; # slurp mode
    my $data = <$fd>;
    close($fd);

    my $filetype;

    if ($file =~ m/\.([^\.]+)$/) {
        my $ext = $1;
        $filetype = $self->app->types->type($ext);
    }

    $filetype ||= "application/octet-stream";
    $self->res->headers->content_type($filetype);

    return $self->render(data => $data);
}

sub live_log {
    my ($self) = @_;

    my $file = $bmwqemu::liveresultpath . "/autoinst-log.txt";

    my $fd;
    unless (open($fd, '<:raw', $file)) {
        # ERROR HANDLING
        $self->render(text => "Can't open $file", status => 404);
        return;
    }
    # only transfer a small portion of the file
    my $limit = $self->param('limit') || 10000;
    my $offset = $self->param('offset');

    my $seeked;
    $seeked = sysseek($fd, $offset, Fcntl::SEEK_SET) if defined $offset;

    # if the seek failed, go to the end
    sysseek($fd, -$limit, Fcntl::SEEK_END) unless $seeked;

    sysread($fd, my $buf = '', $limit);
    $offset = sysseek($fd, 0, 1);
    close($fd);

    $self->res->headers->content_type("text/plain");
    $self->res->headers->add('X-New-Offset' => $offset);
    return $self->render(data => $buf);
}

sub run_daemon {
    my ($port) = @_;

    # we allow only localhost or openQA
    under \&check_authorized;

    get '/data' => \&test_data;

    get '/data/#filename' => \&test_file;

    post '/uploadlog/#filename' => \&upload_log;

    get '/live_log' => \&live_log;

    # not known by default mojolicious
    app->types->type(oga => 'audio/ogg');

    # it's unlikely that we will ever use cookies, but we need a secret to shut up mojo
    my $secret = $bmwqemu::vars{'CONNECT_PASSWORD'} || 'notsosecret';
    app->secrets([$secret]);

    my $daemon = Mojo::Server::Daemon->new(app => app, listen => ["http://*:$port"]);

    $daemon->run;

}

sub start_server($) {
    my ($port) = @_;

    my $thr = threads->create(\&run_daemon, $port);
    return $thr;
}

1;

# vim: set sw=4 et:
