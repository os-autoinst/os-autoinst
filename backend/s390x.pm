package backend::s390x;

use strict;
use warnings;
use English;

use base ('backend::baseclass');

use Carp qw(confess cluck carp croak);

use feature qw/say/;

use testapi qw(get_var check_var set_var);

sub new {
    my $class = shift;
    my $self = bless({class => $class}, $class);
    die "configure WORKER_HOSTNAME e.g. in workers.ini" unless get_var('WORKER_HOSTNAME');
    return $self;
}

# cature send_key events to switch consoles on ctr-alt-fX
sub send_key {
    my ($self, $args) = @_;
    my $_map = {
        "ctrl-alt-f1" => "installation",
        "ctrl-alt-f2" => "ctrl-alt-f2",
        "ctrl-alt-f3" => "ctrl-alt-f2",
        "ctrl-alt-f4" => "ctrl-alt-f2",
        "ctrl-alt-f7" => "installation",
        "ctrl-alt-f9" => "ctrl-alt-f2",
    };
    print "SEND_KEY $args->{key}\n";
    if ($args->{key} =~ qr/^ctrl-alt-f(\d+)/i) {
        die "unkown ctrl-alt-fX combination $args->{key}" unless exists $_map->{$args->{key}};
        $self->select_console({testapi_console => $_map->{$args->{key}}});
        return;
    }
    return $self->SUPER::send_key($args);
}
###################################################################
sub do_start_vm {
    my ($self) = @_;

    $self->unlink_crash_file();
    $self->activate_console({testapi_console => "worker", backend_console => "local-Xvnc"});
    return 1;
}

sub do_stop_vm {
    my ($self) = @_;

    # first kill all _remote_ consoles except for the remote zVM
    # console (which would stop the vm guest)
    my @consoles = keys %{$self->{consoles}};
    for my $console (@consoles) {
        $self->deactivate_console({testapi_console => $console})
          unless $console =~ qr/bootloader|worker/;
    }

    # now cleanly disconnect from the guest and then kill the local
    # Xvnc
    $self->deactivate_console({testapi_console => 'bootloader'});
    $self->deactivate_console({testapi_console => 'worker'});
    return;
}

sub status {
    my ($self) = @_;
    # FIXME: do something useful here.
    carp "status not implemented";
}

1;
