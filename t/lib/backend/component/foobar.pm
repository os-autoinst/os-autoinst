package backend::component::foobar;
use Mojo::Base "backend::component";
has load => 0;    # This component can be just explictly loaded. Does not require autoload.
1;
