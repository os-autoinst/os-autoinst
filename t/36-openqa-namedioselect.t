#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use OpenQA::NamedIOSelect;

subtest NamedIOSelect => sub {

    my $io = OpenQA::NamedIOSelect->new;

    $io->add(*STDIN);
    $io->add(*STDOUT, 'STDOUT');

    like($io->get_name(*STDIN), qr/called at/, 'No name give, fallback to caller');
    is($io->get_name(*STDOUT), 'STDOUT', 'Filedescriptor got name');
    is($io->get_name(666), 'Unknown fd(666)', 'Unknown fd return formatted string');

    is(ref($io->select), 'IO::Select', 'Get the IO::Select object');

    $io->remove(*STDOUT);
    is($io->names->{fileno *STDOUT}, undef, 'File descriptor was removed');
    $io->remove(*STDIN);
    is(scalar(keys %{$io->names}), 0, 'All file descriptors are removed');
};

done_testing;
