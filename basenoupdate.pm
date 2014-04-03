package basenoupdate;
use base "installstep";

# using this as base class means only run when an install is needed, but no upgrade of an old system
sub is_applicable() {
    my $self = shift;
    return $self->SUPER::is_applicable && !$ENV{UPGRADE};
}

1;
