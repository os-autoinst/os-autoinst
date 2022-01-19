use Mojo::Base 'basetest', -signatures;

sub run ($self, $rargs) {

    unless (defined $rargs) {
        die 'run_args not passed through';
    }
}
1;
