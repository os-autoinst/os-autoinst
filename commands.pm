package commands;

use threads;
use threads::shared;

# Automatically enables "strict", "warnings", "utf8" and Perl 5.10 features
use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::Server::Daemon;

use File::Basename;

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

    my $local_ip    = $self->tx->local_address;
    $self->app->log->debug("Request to $local_ip.");

    # with TAP devices the address is not translated
    # client 10.0.2.x connects to server 10.0.2.2
    return 1 if ($local_ip eq "10.0.2.2");

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
sub _test_data_dir {
    my ($self, $base) = @_;

    $base .= '/' if $base !~ /\/$/;

    $self->app->log->debug("Request for directory $base.");

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

# serve a file from within data directory
sub _test_data_file {
    my ($self, $file) = @_;

    $self->app->log->debug("Request for file $file.");

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

sub test_data {
    my ($self) = @_;

    my $path = $bmwqemu::vars{'CASEDIR'} . "/data/";
    my $relpath = $self->param('relpath');
    if (defined $relpath) {
        # do not allow .. in path
        return $self->render_not_found if $relpath =~ /^(.*\/)*\.\.(\/.*)*$/;
        $path .= $relpath;
    }

    return _test_data_dir($self, $path) if -d $path;
    return _test_data_file($self, $path) if -f $path;

    return $self->render_not_found;
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


our $current_test_script :shared;

sub current_script {
    my ($self) = @_;
    return $self->render(data => $current_test_script);
}

sub run_daemon {
    my ($port) = @_;

    # we allow only localhost or openQA
    under \&check_authorized;

    # for access all data as CPIO archive
    get '/data' => \&test_data;

    # to access a single file or a subdirectory
    get '/data/*relpath' => \&test_data;

    # uploading log files from tests
    post '/uploadlog/#filename' => \&upload_log;

    # to get the current bash script out of the test
    get '/current_script' => \&current_script;

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
