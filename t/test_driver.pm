# This provides a mean to test things without requiring a real backend
package t::test_driver;

use strict;
use Carp;

sub new {
    my $class = shift;

    my $hash;
    $hash->{cmds} = [];
    return bless $hash, $class;
}

sub type_string {
    my ($self, $args) = @_;
    push(@{ $self->{cmds} }, 'type_string', $args);
}

1;
