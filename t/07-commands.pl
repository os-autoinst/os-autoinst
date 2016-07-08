#!/usr/bin/perl
#
# Copyright (c) 2016 SUSE LLC
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


use strict;
use warnings;

use FindBin;
use File::Find;
require IPC::System::Simple;
use autodie qw(:all);


BEGIN {
    unshift @INC, '..';
}

use commands;
use Mojo::IOLoop::Server;
use Time::HiRes qw(sleep);
use Test::More tests => 4;
use POSIX qw(_exit);

our $mojoport = Mojo::IOLoop::Server->generate_port;

sub wait_for_server {
    my ($ua) = @_;
    for (my $counter = 0; $counter < 20; $counter++) {
        return if (($ua->get("http://localhost:$mojoport/NEVEREVER")->res->code // 0) == 404);
        sleep .1;
    }
    return 1;
}

$bmwqemu::vars{JOBTOKEN} = 'Hallo';

# now this is a game of luck
my ($cpid, $cfd) = commands::start_server($mojoport);

my $spid = fork();
if ($spid == 0) {
    # we need to fake isotovideo here
    my $h = myjsonrpc::read_json($cfd);
    if ($h->{cmd} eq 'version') {
        myjsonrpc::send_json($cfd, {VERSION => 'COOL'});
    }
    _exit(0);
}

my $ua = Mojo::UserAgent->new;
if (wait_for_server($ua)) {
    exit(0);
}

is($ua->get("http://localhost:$mojoport/NEVEREVER")->res->code,          404);
is($ua->get("http://localhost:$mojoport/isotovideo/version")->res->code, 404);
my $get = $ua->get("http://localhost:$mojoport/Hallo/isotovideo/version");
is($get->res->code, 200);
is_deeply($get->res->json, {VERSION => 'COOL'});

END {
    kill($spid);
    kill($cpid);
}
