package foo;
use Mojo::Base -base;
has load => sub { $ENV{FOO_BAR_BAZ} };
has prepared => 0;
has started  => 0;

sub prepare {
    shift->prepared(1);
}

sub start {
    shift->started(1);
}
1;
