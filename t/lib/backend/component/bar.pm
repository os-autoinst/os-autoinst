package backend::component::bar;
use Mojo::Base "backend::component";
has load => sub { $ENV{FOO_BAR_BAR} };

1;
