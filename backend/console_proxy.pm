# This is the direct companion to backend::s390x::do_console_hack()
#
# "gnah" is a proxy object for calls to specific terminal functions
# like s3270->... or vnc->... or ssh->... from the tests in the main
# thread.

package console_proxy;
use Data::Dumper qw(Dumper);

sub new() {
    my ($class, $console) = @_;

    my $self = bless( { class => $class, console => $console }, $class );

    return $self;
}

use feature qw/say/;

sub AUTOLOAD {

    my $function = our $AUTOLOAD;

    $function =~ s,.*::,,;

    #<<< perltidy, this _is_ tidy...
    no strict 'refs';  # allow symbolic references
    *$AUTOLOAD = sub {
	my $self = shift;
	my $args = \@_;
	my $wrapped_call = {
			    console => $self->{console},
			    function => $function,
			    args => $args,
			   };

	my $wrapped_retval = $bmwqemu::backend->proxy_console_call($wrapped_call);

	if (exists $wrapped_retval->{exception}) {
	    die $wrapped_retval->{exception};
	}

	return $wrapped_retval->{result};
    };
    #<<< turn perltidy back on

    goto &$AUTOLOAD;
}

1;
