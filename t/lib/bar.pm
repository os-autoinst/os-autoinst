package bar;
use Mojo::Base -base;
has load => sub { $ENV{FOO_BAR_BAR} };

1;
