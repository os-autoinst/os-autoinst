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
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
    unshift @INC, '..';
}

subtest qv => sub {
    use osutils 'qv';

    my $apple = 1;
    my $tree  = 2;
    my $bar   = 3;
    my $vars;

    is_deeply [qv "$apple $tree $bar"], [qw(1 2 3)], "Can interpolate variables";
    is_deeply [
        qv "$apple
                    $tree
                    $bar"
      ],
      [qw(1 2 3)], "Can interpolate variables even if on new lines";
    is_deeply [qv "3 45 5"], [qw(3 45 5)], "Can interpolate words";

    $vars->{HDDMODEL} = "test";
    is_deeply [qv "$vars->{HDDMODEL} 45 5"], [qw(test 45 5)], "Can interpolate variables and hash values";

};

subtest gen_params => sub {
    use osutils qw(qv gen_params);

    my @params    = qw(-foo bar -baz foobar);
    my $condition = 0;

    gen_params @params, "test", "1";
    is_deeply(\@params, [qw(-foo bar -baz foobar -test 1)], "added parameter");

    my $nothing;
    @params = qw(-foo bar);
    gen_params @params, "test", $nothing;
    is_deeply(\@params, [qw(-foo bar)], "didn't added any parameter");

    @params = qw(-foo bar);
    gen_params @params, "test", [qw(1 2 3)];
    is_deeply(\@params, [qw(-foo bar -test 1,2,3)], "Added parameter if parameter is an arrayref");

    @params = qw(-foo bar);
    my $apple = 1;
    my $tree  = 2;
    my $bar   = 3;
    gen_params @params, "test", [qv "$apple $tree $bar"];
    is_deeply(\@params, [qw(-foo bar -test 1,2,3)], "Added parameter if parameter is an arrayref supplied with qv()");

    my $nothing_is_there;
    @params = qw(-foo bar);
    gen_params @params, "test", $nothing_is_there;
    is_deeply(\@params, [qw(-foo bar)], "don't add parameter if it's empty");


    @params = qw(!!foo bar);
    gen_params @params, "test", [qv "$apple $tree $bar"], "!!";
    is_deeply(\@params, [qw(!!foo bar !!test 1,2,3)], "Added parameter if parameter is an arrayref and with custom prefix");

};

subtest dd_gen_params => sub {
    use osutils qw(qv dd_gen_params);

    my @params    = qw(--foo bar --baz foobar);
    my $condition = 0;

    dd_gen_params @params, "test", "1";
    is_deeply(\@params, [qw(--foo bar --baz foobar --test 1)], "added parameter");

    my $nothing;
    @params = qw(--foo bar);
    dd_gen_params @params, "test", $nothing;
    is_deeply(\@params, [qw(--foo bar)], "didn't added any parameter");

    @params = qw(--foo bar);
    dd_gen_params @params, "test", [qw(1 2 3)];
    is_deeply(\@params, [qw(--foo bar --test 1,2,3)], "Added parameter if parameter is an arrayref");

    @params = qw(--foo bar);
    my $apple = 1;
    my $tree  = 2;
    my $bar   = 3;
    dd_gen_params @params, "test", [qv "$apple $tree $bar"];
    is_deeply(\@params, [qw(--foo bar --test 1,2,3)], "Added parameter if parameter is an arrayref supplied with qv()");

    my $nothing_is_there;
    @params = qw(--foo bar);
    dd_gen_params @params, "test", $nothing_is_there;
    is_deeply(\@params, [qw(--foo bar)], "don't add parameter if it's empty");

};

subtest find_bin => sub {
    use Mojo::File qw(path tempdir);
    use osutils 'find_bin';

    my $sandbox = tempdir;

    my $test_file = path($sandbox, "test")->spurt("testfile");
    chmod 0755, $test_file;
    is find_bin($sandbox, qw(test)), $test_file, "Executable file found";

    $test_file = path($sandbox, "test2")->spurt("testfile");
    is find_bin($sandbox, qw(test2)), undef, "Executable file found but not executable";
    is find_bin($sandbox, qw(test3)), undef, "Executable file not found";

};

subtest looks_like_ip => sub {
    use osutils 'looks_like_ip';

    ok looks_like_ip($_), "$_ is a valid ip"
      for (
        qw(
        127.0.0.1
        255.255.255.255
        1.1.1.1
        2.2.2.2
        192.168.0.0
        10.10.0.0
        0.0.0.0
        ));

    ok !looks_like_ip($_), "$_ is an invalid ip"
      for (
        qw(
        255.255.255.256
        255.255.256.256
        255.256.256.256
        256.256.256.256
        256.256.256.255
        256.256.255.255
        256.255.255.255
        my.foo.bar
        1a.22.33.44
        1.22a.33.44
        1.22.33.44a
        4.4.4.4.4
        1.1.23.21.3.12.2.23
        ));
};

subtest get_class_name => sub {
    use osutils 'get_class_name';
    use backend::component::foo;
    use backend::component::foobar;
    my $obj1 = backend::component::foo->new;
    my $obj2 = backend::component::foobar->new;


    is get_class_name("backend::component::foo=HASH(0x27a3640)"),       "backend::component::foo";
    is get_class_name("backend::component::dnsserver=HASH(0x1f8e1c8)"), "backend::component::dnsserver";
    is get_class_name("backend::component::proxy=HASH(0x3538eb0)"),     "backend::component::proxy";
    is get_class_name($obj1), "backend::component::foo";
    is get_class_name($obj2), "backend::component::foobar";
};

subtest load_module => sub {
    use osutils 'load_module';
    use backend::component::foo;

    my $obj = load_module('backend::component::foo', {prepare => 0});
    is $obj->prepared, 0;
    $obj = load_module('backend::component::foo', {prepare => 1});
    is $obj->prepared, 1;
    $obj = load_module('backend::component::foo');
    is $obj->prepared, 1;
    is $obj->started,  1;
};

subtest load_components => sub {
    use osutils 'load_components';

    my ($errors, $loaded) = load_components('backend::component', 'foo', {prepare => 0});
    is @{$errors}, 0;
    is @{$loaded}, 2;
    is $_->{prepare}, 0 for @{$loaded};

    ($errors, $loaded) = load_components('backend::component', '', {prepare => 0});
    is @{$errors}, 1;
    is @{$loaded}, 0;
    my $err = shift @{$errors};
    isa_ok $err, "Mojo::Exception";

    local $ENV{FOO_BAR_BAZ} = 1;
    ($errors, $loaded) = load_components('backend::component', '');
    is @{$errors}, 1;
    is @{$loaded}, 1;
    is shift(@{$loaded})->prepared, 1;
};

done_testing();
