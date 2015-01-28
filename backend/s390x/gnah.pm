# This is the direct companion to backend::s390x::do_console_hack()
#
# "gnah" is a proxy object for calls to specific terminal functions
# like s3270->... or vnc->... or ssh->... from the tests in the main
# thread.

package gnah;
use Data::Dumper qw(Dumper);

sub new() {
    my ($class, $console) = @_;

    my $self = bless( { class => $class, console => $console }, $class );

    return $self;
}

sub AUTOLOAD {
    my $self = shift;
    my $args = \@_;

    my $function = our $AUTOLOAD;

    $function =~ s,.*::,,;
    my $wrapped_call = {
	console => $self->{console},
	function => $function,
	args => $args,
    };

    my $retval = $bmwqemu::backend->do_console_hack($wrapped_call);

    return $retval;

}

1;
