# This is the direct companion to backend::proxy_console_call()
#
# "console_proxy" is a proxy object for calls to specific terminal functions
# like s3270->... or vnc->... or ssh->... from the tests in the main
# thread.

package backend::console_proxy;
use Data::Dumper qw(Dumper);
use strict;

sub new {
    my ($class, $console) = @_;

    my $self = bless({class => $class, console => $console}, $class);

    return $self;
}

use feature qw/say/;

sub AUTOLOAD {

    my $function = our $AUTOLOAD;

    $function =~ s,.*::,,;

    #<<< perltidy, this _is_ tidy...
    # allow symbolic references
    no strict 'refs'; ## no critic
    *$AUTOLOAD = sub {
	my $self = shift;
	my $args = \@_;
	my $wrapped_call = {
			    console => $self->{console},
			    function => $function,
			    args => $args,
			   };

	bmwqemu::log_call($function, wrapped_call => $wrapped_call);
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
