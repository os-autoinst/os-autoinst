use Mojo::Base 'basetest', -signatures;

sub run ($) {
    something();
}

sub something () {
    OpenQA::Exception::TestapiError->throw(error => 'ON PURPOSE') if $ENV{THROW_EXCEPTION};
    my $x = 23;
    if ($ENV{PERL_DIE}) {
        my $y = $x / 0;
    }
}

1;

