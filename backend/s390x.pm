package backend::s390x;

use strict;
use warnings;
use English;
require IPC::System::Simple;
use autodie qw(:all);

use base ('backend::baseclass');

use Carp qw(confess cluck carp croak);

use feature qw/say/;

use testapi qw(get_var check_var set_var);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    die "configure WORKER_HOSTNAME e.g. in workers.ini" unless get_var('WORKER_HOSTNAME');
    return $self;
}

###################################################################
sub do_start_vm {
    my ($self) = @_;

    $self->unlink_crash_file();
    my $console = $testapi::distri->add_console('worker', 'local-Xvnc');
    $console->backend($self);
    $self->select_console({testapi_console => 'worker'});
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
    $self->deactivate_console({testapi_console => 'sut'});
    $self->deactivate_console({testapi_console => 'worker'});
    return;
}

sub status {
    my ($self) = @_;
    # FIXME: do something useful here.
    carp "status not implemented";
}

sub wait_serial {
    my ($self, $args) = @_;

    my $regexp  = $args->{regexp};
    my $timeout = $args->{timeout};
    my $matched = 0;
    my $str;

    die 'Unsupported ARRAYREF for s390' if (ref $regexp eq 'ARRAY');
    my $console = testapi::console('bootloader');
    my $r = eval { $console->expect_3270(output_delim => $regexp, timeout => $timeout); };
    unless ($@) {
        $matched = 1;
        $str = join('\n', @$r);
    }
    return {matched => $matched, string => $str};
}

1;
