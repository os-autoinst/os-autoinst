#!/usr/bin/perl

# Copyright (C) 2017 SUSE LLC
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


use 5.018;
use warnings;
use strict;
use Test::More;
use Net::DNS::Resolver;
use POSIX;

BEGIN {
    unshift @INC, '..';
}
use backend::component::dnsserver;

my $ip       = '127.0.0.1';
my $port     = "9993";
my $resolver = new Net::DNS::Resolver(
    nameservers => [$ip],
    port        => $port,
    recurse     => 1,
    debug       => 0
);

sub _request {
    my ($qname, $qtype, $qclass) = @_;
    my @ans;

    my $question = $resolver->query($qname, $qtype, $qclass);

    if (defined $question) {
        @ans = map {
            {
                $_->{owner}->string => [$_->class, $_->type, eval { $_->_format_rdata; }]
            }
        } $question->answer();
    }

    return \@ans;
}

sub _start_dnsserver {
    my ($policy, $record_table, $forward_nameserver) = @_;

    $record_table       //= {};
    $forward_nameserver //= [];

    my $server = backend::component::dnsserver->new(
        listening_address  => $ip,
        listening_port     => $port,
        policy             => $policy,
        record_table       => $record_table,
        forward_nameserver => $forward_nameserver,
        verbose            => 0,
        kill_sleeptime     => 1
    )->prepare()->start;
    *bmwqemu::vars = {};
    return $server;
}

subtest 'dns requests in SINK mode' => sub {
    my $dnsserver = _start_dnsserver(
        "SINK",
        {
            'download.opensuse.org' => ['download.opensuse.org. A 127.0.0.1'],
            'foo.bar.baz'           => ['foo.bar.baz. A 0.0.0.0', 'foo.bar.baz. A 1.1.1.1'],
            'my.foo.bar.baz'        => ['my.foo.bar.baz. CNAME foo.bar.baz'],
            'openqa.opensuse.org'   => 'FORWARD'
        },
        ['8.8.8.8']);

    my $ans = _request('download.opensuse.org', 'A', 'IN');
    is_deeply $ans, [{'download.opensuse.org.' => ['IN', 'A', '127.0.0.1']}];

    $ans = _request('foo.bar.baz', 'A', 'IN');
    is_deeply $ans, [{'foo.bar.baz.' => ['IN', 'A', '0.0.0.0']}, {'foo.bar.baz.' => ['IN', 'A', '1.1.1.1']}];

    $ans = _request('my.foo.bar.baz', 'CNAME', 'IN');
    is_deeply $ans, [{"my.foo.bar.baz." => ['IN', 'CNAME', 'foo.bar.baz.']}];

    $ans = _request("foobar.org", 'A', 'IN');
    is scalar(@$ans), 0, 'No answer expected in SINK mode';

    $ans = _request('openqa.opensuse.org', 'A', 'IN');
    ok scalar(@$ans) > 0;

    $dnsserver->stop();
};

subtest 'dns requests in FORWARD mode' => sub {
    my $dnsserver = _start_dnsserver(
        'FORWARD',
        {
            'download.opensuse.org' => ['download.opensuse.org. A 127.0.0.1'],
            'foo.bar.baz'           => ['foo.bar.baz. A 0.0.0.0', 'foo.bar.baz. A 1.1.1.1'],
            'my.foo.bar.baz'        => ['my.foo.bar.baz. CNAME foo.bar.baz'],
            'openqa.opensuse.org'   => 'DROP'
        },
        ['8.8.8.8']);

    my $ans = _request('download.opensuse.org', 'A', 'IN');
    is_deeply $ans, [{'download.opensuse.org.' => ['IN', 'A', '127.0.0.1']}], "Redirect table has precedence";

    $ans = _request('foo.bar.baz', 'A', 'IN');
    is_deeply $ans, [{'foo.bar.baz.' => ['IN', 'A', '0.0.0.0']}, {'foo.bar.baz.' => ['IN', 'A', '1.1.1.1']}], "Redirect table has precedence";

    $ans = _request('my.foo.bar.baz', 'CNAME', 'IN');
    is_deeply $ans, [{"my.foo.bar.baz." => ['IN', 'CNAME', 'foo.bar.baz.']}], "Redirect table has precedence";

    $ans = _request('open.qa', 'A', 'IN');
    ok scalar(@$ans) > 0, 'answer expected in FORWARD mode';

    $ans = _request('openqa.opensuse.org', 'A', 'IN');
    is scalar(@$ans), 0, "Domain rule with DROP won't be forwarded";

    $dnsserver->stop();
};

subtest 'dns server failures' => sub {
    eval {
        my $dnsserver = _start_dnsserver('SSSINK', {}, []);
        $dnsserver->stop();
    };
    ok defined $@;
    like $@, qr/Invalid policy supplied for DNS server./;

    *bmwqemu::vars = {};
    my $dnsserver = _start_dnsserver('FORWARD', {}, []);

    my $ans = _request('download.opensuse.org', 'A', 'IN');
    ok scalar(@$ans) == 0, 'answer expected in FORWARD mode. but is none if no forward servers are defined';
    $dnsserver->stop();
};

subtest 'dns requests with wildcard' => sub {
    my $dnsserver = _start_dnsserver(
        'FORWARD',
        {
            'download.opensuse.org' => ['download.opensuse.org. A 127.0.0.1'],
            'foo.bar.baz'           => ['foo.bar.baz. A 0.0.0.0', 'foo.bar.baz. A 1.1.1.1'],
            'my.foo.bar.baz'        => ['my.foo.bar.baz. CNAME foo.bar.baz'],
            'openqa.opensuse.org'   => 'DROP',
            'open.qa'               => 'FORWARD',
            '*'                     => '2.2.2.2'                                               ## no critic
        },
        ['8.8.8.8']);

    my $ans = _request('download.opensuse.org', 'A', 'IN');
    is_deeply $ans, [{'download.opensuse.org.' => ['IN', 'A', '127.0.0.1']}], "Redirect table has precedence";

    $ans = _request('foo.bar.baz', 'A', 'IN');
    is_deeply $ans, [{'foo.bar.baz.' => ['IN', 'A', '0.0.0.0']}, {'foo.bar.baz.' => ['IN', 'A', '1.1.1.1']}], "Redirect table has precedence";

    $ans = _request('my.foo.bar.baz', 'CNAME', 'IN');
    is_deeply $ans, [{"my.foo.bar.baz." => ['IN', 'CNAME', 'foo.bar.baz.']}], "Redirect table has precedence";

    $ans = _request('open.qa', 'A', 'IN');
    ok scalar(@$ans) > 0, 'answer expected in FORWARD mode';

    $ans = _request('openqa.opensuse.org', 'A', 'IN');
    is scalar(@$ans), 0, "Domain rule with DROP won't be forwarded";

    $ans = _request('foo.opensuse.org', 'A', 'IN');
    is_deeply $ans, [{'foo.opensuse.org.' => ['IN', 'A', '2.2.2.2']}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $ans = _request('baz.org', 'A', 'IN');
    is_deeply $ans, [{'baz.org.' => ['IN', 'A', '2.2.2.2']}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $dnsserver->stop();

    # (almost) same tests but in SINK mode
    $dnsserver = _start_dnsserver(
        "SINK",
        {
            'download.opensuse.org' => ['download.opensuse.org. A 127.0.0.1'],
            'foo.bar.baz'           => ['foo.bar.baz. A 0.0.0.0', 'foo.bar.baz. A 1.1.1.1'],
            'my.foo.bar.baz'        => ['my.foo.bar.baz. CNAME foo.bar.baz'],
            'openqa.opensuse.org'   => 'DROP',
            'open.qa'               => 'FORWARD',
            '*'                     => '2.2.2.2'                                               ## no critic
        },
        ['8.8.8.8']);

    $ans = _request('download.opensuse.org', 'A', 'IN');
    is_deeply $ans, [{'download.opensuse.org.' => ['IN', 'A', '127.0.0.1']}], "Redirect table has precedence";

    $ans = _request('foo.bar.baz', 'A', 'IN');
    is_deeply $ans, [{'foo.bar.baz.' => ['IN', 'A', '0.0.0.0']}, {'foo.bar.baz.' => ['IN', 'A', '1.1.1.1']}], "Redirect table has precedence";

    $ans = _request('my.foo.bar.baz', 'CNAME', 'IN');
    is_deeply $ans, [{"my.foo.bar.baz." => ['IN', 'CNAME', 'foo.bar.baz.']}], "Redirect table has precedence";

    $ans = _request('open.qa', 'A', 'IN');
    ok scalar(@$ans) > 0, 'answer expected, rule specifies FORWARD mode for the specific domain';
    ok defined $ans->[0]->{'open.qa.'}->[2];
    ok $ans->[0]->{'open.qa.'}->[2] ne '2.2.2.2', "domain that are marked to be forwarded does not return the wildcard value";

    $ans = _request('openqa.opensuse.org', 'A', 'IN');
    is scalar(@$ans), 0, "Domain rule with DROP won't be forwarded";

    $ans = _request('foo.opensuse.org', 'A', 'IN');
    is_deeply $ans, [{'foo.opensuse.org.' => ['IN', 'A', '2.2.2.2']}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $ans = _request('baz.org', 'A', 'IN');
    is_deeply $ans, [{'baz.org.' => ['IN', 'A', '2.2.2.2']}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $dnsserver->stop();
};

subtest 'dns requests options' => sub {
    my $dnsserver = _start_dnsserver('FORWARD');
    $dnsserver->stop();

    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT}    = '4050';
    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS} = '0.0.0.0';
    $dnsserver->prepare();
    is $dnsserver->listening_port,    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT};
    is $dnsserver->listening_address, $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS};
    *bmwqemu::vars = {};

    $dnsserver->listening_port(8989);
    $dnsserver->listening_address("12.12.12.12");
    $dnsserver->prepare();
    is $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT},    8989;
    is $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS}, "12.12.12.12";
    *bmwqemu::vars = {};

    $bmwqemu::vars{CONNECTIONS_HIJACK} = 1;
    $bmwqemu::vars{NICTYPE}            = "user";
    $dnsserver->prepare();
    is $bmwqemu::vars{CONNECTIONS_HIJACK_FAKEIP}, "10.0.2.254", "default fakeip was set";
    *bmwqemu::vars = {};

    $bmwqemu::vars{CONNECTIONS_HIJACK} = 0;
    $bmwqemu::vars{NICTYPE}            = "user";
    $dnsserver->prepare();
    ok !defined $bmwqemu::vars{CONNECTIONS_HIJACK_FAKEIP}, "default fakeip was not set";
    *bmwqemu::vars = {};

    $bmwqemu::vars{CONNECTIONS_HIJACK} = 1;
    $bmwqemu::vars{NICTYPE}            = "blah";
    $dnsserver->prepare();
    ok !defined $bmwqemu::vars{CONNECTIONS_HIJACK_FAKEIP}, "default fakeip was not set";
    *bmwqemu::vars = {};


    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_ENTRY} = "mytest.org:1.1.1.1,mybeautifultest.org:FORWARD,myawesometest.org:DROP,myfoo.org:mybar.org";
    $dnsserver->prepare();
    is_deeply $dnsserver->record_table,
      {
        'mytest.org'          => ["mytest.org.     A   1.1.1.1"],
        'mybeautifultest.org' => "FORWARD",
        'myawesometest.org'   => "DROP",
        'myfoo.org'           => ["myfoo.org.     CNAME   mybar.org"]};
    *bmwqemu::vars = {};

    $dnsserver->record_table({});

    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_ENTRY} = "download.opensuse.org:1.1.1.1";
    $dnsserver->prepare();
    is_deeply $dnsserver->record_table, {'download.opensuse.org' => ["download.opensuse.org.     A   1.1.1.1"]};
    *bmwqemu::vars = {};

    $bmwqemu::vars{VNC} = 50;
    $dnsserver->prepare();
    is $dnsserver->listening_port, 10045;
    *bmwqemu::vars = {};

    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_POLICY} = 'FORWARD';
    $dnsserver->prepare();
    is $dnsserver->policy, 'FORWARD';
    *bmwqemu::vars = {};

    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_POLICY} = 'SINK';
    $dnsserver->prepare();
    is $dnsserver->policy, 'SINK';
    *bmwqemu::vars = {};
};

subtest 'dns sink resolver' => sub {
    use backend::component::dnsserver::dnsresolver;

    my $resolver = backend::component::dnsserver::dnsresolver->new('*' => '10.0.0.0');    ## no critic (HashKeyQuotes)
    my $question = $resolver->query("foobarbaz.org", "A", "IN");
    ok defined $question;
    my @ans = $question->answer();
    is $ans[0]->address, "10.0.0.0";
    isa_ok $ans[0], "Net::DNS::RR::A";

    $resolver = backend::component::dnsserver::dnsresolver->new('d.o.o' => ["d.o.o. A 0.0.0.0"], '*' => '10.0.0.0');    ## no critic (HashKeyQuotes)
    $question = $resolver->query("d.o.o", "A", "IN");
    my $question_2 = $resolver->query("test", "A", "IN");

    ok defined $question;
    ok defined $question_2;
    @ans = $question->answer();
    my @ans_2 = $question_2->answer();
    is $ans[0]->address, "0.0.0.0";
    isa_ok $ans[0], "Net::DNS::RR::A";
    is $ans_2[0]->address, "10.0.0.0";
    isa_ok $ans_2[0], "Net::DNS::RR::A";

    $resolver = backend::component::dnsserver::dnsresolver->new("d.o.o" => ["d.o.o. A 0.0.0.0"]);
    $question = $resolver->query("d.o.o", "A", "IN");
    ok defined $question;
    @ans = $question->answer();
    is $ans[0]->address, "0.0.0.0";
    isa_ok $ans[0], "Net::DNS::RR::A";
    $question = $resolver->query("blah", "A", "IN");
    ok !defined $question;

    $resolver = backend::component::dnsserver::dnsresolver->new();
    $question = $resolver->query("d.o.o", "A", "IN");
    ok !defined $question;

    $resolver->{records} = {'d.o.o' => {}};
    $question = $resolver->query("d.o.o", "A", "IN");
    ok !defined $question;

    $resolver->{records} = {};
    $question = $resolver->query("d.o.o", "A", "IN");
    ok !defined $question;
};

done_testing;
