#!/usr/bin/perl -w
package backend::s390x;

use strict;
use warnings;
use English;

use base ('backend::vnc_backend');

use Carp qw(confess cluck carp croak);

use feature qw/say/;

use backend::s390x::s3270;

use backend::VNC;

use testapi qw(get_var check_var set_var);

sub new {
    my $class = shift;
    my $self = bless({class => $class}, $class);
    return $self;
}


sub _delete_console {
    my ($self, $console_info) = @_;
    my $args = $console_info->{args};
    my ($testapi_console, $backend_console) = @$args{qw(testapi_console backend_console)};
    CORE::say __FILE__ . ':' . __LINE__ . ':' . (caller 0)[3] . ':' . bmwqemu::pp($args);
    #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
    if ($testapi_console eq "bootloader") {
        if (exists get_var("DEBUG")->{"keep zVM guest"}) {
            $console_info->{console}->cp_disconnect();
        }
        else {
            $console_info->{console}->cp_logoff_disconnect();
        }
        # REFACTOR: DRY (same as in the next two...)
        my $window_id = $console_info->{window_id};
        my $display   = $self->{consoles}->{worker}->{DISPLAY};
        system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
        $console_info->{console} = undef;
    }

    else {
        confess "unknown backend console $backend_console";
    }
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
    $self->inflate_vars_json();
    $self->activate_console({testapi_console => "worker", backend_console => "local-Xvnc"});
    return 1;
}

# input from the worker in vars.json:
#     "S390_CONSOLE" : "vnc",
#     "S390_HOST" : "153",
#     "S390_NETWORK" : "hsi-l3",
#     "REPO_0" : "SLES-11-SP4-DVD-s390x-Build1050-Media1",
# when not invoked from the worker (no WORKER_CLASS set), these need
# to be set, too:
#     "S390_INSTHOST": "dist",
#     "S390_INSTSRC": "http",
# output: a full-featured vars.json suitable for s390 testing
sub inflate_vars_json {
    my ($self) = @_;

    # these vars have to be set in vars.json:
    die unless defined get_var('S390_HOST');
    die unless defined get_var('S390_NETWORK');
    die unless defined get_var('S390_CONSOLE');
    die unless defined get_var('REPO_0');
    # when called from the openqa worker, these two vars are not set
    # yet:
    if (defined get_var('WORKER_CLASS')) {
        die if defined get_var('S390_INSTHOST');
        die if defined get_var('S390_INSTSRC');
        set_var("S390_INSTHOST", "openqa");
        # FIXME: this should become a parameter in the future, too.
        # only ftp is implemented so far on openqa.suse.de
        set_var("S390_INSTSRC", "ftp");
        bmwqemu::save_vars();
    }
    else {
        die unless defined get_var('S390_INSTHOST');
        die unless defined get_var('S390_INSTSRC');
    }

    # use external script to inflate vars.json
    my $vars_json_cmd = $bmwqemu::scriptdir . "/backend/s390x/vars.json.py";

    open(my $VARS, '-|', $vars_json_cmd) // die "can't call $vars_json_cmd";
    my @vars = <$VARS>;
    close($VARS);
    open($VARS, ">", "vars.json") || die "can't open vars.json";
    print $VARS join('', @vars);
    close($VARS);

    bmwqemu::load_vars();
    bmwqemu::expand_DEBUG_vars();
    bmwqemu::save_vars();
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

sub do_savevm {
    notimplemented();
}

sub do_loadvm {
    notimplemented();
}

sub status {
    my ($self) = @_;
    # FIXME: do something useful here.
    carp "status not implemented";
}

1;
