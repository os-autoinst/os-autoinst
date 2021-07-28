#!/usr/bin/perl

# Copyright (C) 2017-2021 SUSE LLC
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

use Test::Most;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::Warnings qw(:all :report_warnings);
use Test::Output qw(stderr_like);

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
    is_deeply(\@params, [qw(-foo bar -test), '1,2,3'], "Added parameter if parameter is an arrayref");

    @params = qw(-foo bar);
    my $apple = 1;
    my $tree  = 2;
    my $bar   = 3;
    gen_params @params, "test", [qv "$apple $tree $bar"];
    is_deeply(\@params, [qw(-foo bar -test), '1,2,3'], "Added parameter if parameter is an arrayref supplied with qv()");

    my $nothing_is_there;
    @params = qw(-foo bar);
    gen_params @params, "test", $nothing_is_there;
    is_deeply(\@params, [qw(-foo bar)], "don't add parameter if it's empty");


    @params = qw(!!foo bar);
    gen_params @params, "test", [qv "$apple $tree $bar"], prefix => "!!";
    is_deeply(\@params, [qw(!!foo bar !!test), '1,2,3'], "Added parameter if parameter is an arrayref and with custom prefix");

    @params = qw(-kernel vmlinuz -initrd initrd);
    gen_params @params, "append", "ro root=/dev/sda1";
    is_deeply(\@params, [('-kernel', 'vmlinuz', '-initrd', 'initrd', '-append', "\'ro root=/dev/sda1\'")], "Quote itself if parameter contains whitespace");

    @params = qw(-kernel vmlinuz -initrd initrd);
    gen_params @params, "append", "ro root=/dev/sda1", no_quotes => 1;
    is_deeply(\@params, [('-kernel', 'vmlinuz', '-initrd', 'initrd', '-append', "ro root=/dev/sda1")], "Do not quote itself if pass no_quotes argument");

    @params = qw(-kernel vmlinuz);
    gen_params @params, "append", "ro root=/dev/sda1", no_quotes => 1, prefix => '--';
    is_deeply(\@params, [('-kernel', 'vmlinuz', '--append', "ro root=/dev/sda1")], "Do not quote itself if pass no_quotes argument with custom prefix");
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
    is_deeply(\@params, [qw(--foo bar --test), '1,2,3'], "Added parameter if parameter is an arrayref");

    @params = qw(--foo bar);
    my $apple = 1;
    my $tree  = 2;
    my $bar   = 3;
    dd_gen_params @params, "test", [qv "$apple $tree $bar"];
    is_deeply(\@params, [qw(--foo bar --test), '1,2,3'], "Added parameter if parameter is an arrayref supplied with qv()");

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

subtest quote => sub {
    use osutils 'quote';

    my $foo = "foo";
    my $bar = "bar bar";
    my $vars;

    is quote($foo), "\'foo\'",     "Quote variables";
    is quote($bar), "\'bar bar\'", "Quote words";
    is quote('foo' . $bar), "\'foobar bar\'", "Quote words and variables";

    $vars->{ADDONS} = "ha,geo,sdk";
    is quote($vars->{ADDONS}), "\'ha,geo,sdk\'", "Quote variables and hash values";
};

subtest runcmd => sub {
    use osutils 'runcmd';

    my @cmd = ('qemu-img', 'create', '-f', 'qcow2', 'image.qcow2', '1G');
    my $ret;
    stderr_like { $ret = runcmd(@cmd) } qr/running qemu-img/, 'debug runcmd progress output';
    is $ret, 0, "qemu-image creation and get its return code";
    stderr_like { $ret = runcmd('rm', 'image.qcow2') } qr/running rm/, 'debug runcmd output with rm';
    is $ret, 0, "delete image and get its return code";
    local $@;
    stderr_like { eval { runcmd('ls', 'image.qcow2') } } qr/No such file or directory/, 'no image found as expected';
    like $@, qr/runcmd 'ls image.qcow2' failed with exit code \d+/, "command failed and calls die";
};

subtest attempt => sub {
    use osutils 'attempt';
    my $module = Test::MockModule->new('osutils');
    # just save ourselves some time during testing
    $module->redefine(wait_attempt => sub { sleep 0; });

    my $var = 0;
    stderr_like { attempt(5, sub { $var == 5 }, sub { $var++ }) } qr/Waiting for.*attempts/, 'attempts conducted';
    is $var, 5, 'all attempts exhausted';
    $var = 0;
    stderr_like { attempt {
            attempts  => 6,
            condition => sub { $var == 6 },
            cb        => sub { $var++ }
    } } qr/Waiting for.*attempts/, 'attempts conducted with named parameters';
    is $var, 6, 'correct attempts with named parameters';

    $var = 0;
    stderr_like { attempt {
            attempts  => 6,
            condition => sub { $var == 7 },
            cb        => sub { $var++ },
            or        => sub { $var = 42 }
    } } qr/Waiting for.*attempts/, 'attempts with alternative return';
    is $var, 42, 'alternative return set';
};

done_testing();
