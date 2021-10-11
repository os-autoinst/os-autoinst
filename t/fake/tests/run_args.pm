use Mojo::Base 'basetest', -signatures;

sub run ($self, $rargs) {
    die 'run_args not passed through' unless defined $rargs;
}
1;
