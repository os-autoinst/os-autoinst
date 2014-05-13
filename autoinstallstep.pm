package autoinstallstep;
use base "installstep";

# using this as base class means only run when an install is needed
sub is_applicable() {
    my $self = shift;
    return $self->SUPER::is_applicable || $bmwqemu::vars{AUTOYAST};
}

1;
# vim: set sw=4 et:
