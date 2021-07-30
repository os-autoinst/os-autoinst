# Copyright © 2018-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package backend::amt;

use Mojo::Base -strict;
use autodie ':all';

use base 'backend::baseclass';

use Time::HiRes qw(sleep gettimeofday);
use Data::Dumper;
require Carp;
use bmwqemu ();
use testapi 'get_required_var';
use IPC::Run ();
require IPC::System::Simple;

# xml namespaces
my $IPS = "http://intel.com/wbem/wscim/1/ips-schema/1";
my $CIM = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2";
my $AMT = "http://intel.com/wbem/wscim/1/amt-schema/1";
my $XSD = "http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd";
my $ADR = "http://schemas.xmlsoap.org/ws/2004/08/addressing";

# AMT requirements: exactly 8 chars, at least on lowecase letter, uppercase
# letter, digit, and special
my $vnc_password = 'we4kP@ss';

sub new {
    my $class = shift;
    get_required_var('AMT_HOSTNAME');
    get_required_var('AMT_PASSWORD');

    # use env to avoid leaking password to logs
    $ENV{'WSMAN_USER'} = 'admin';
    $ENV{'WSMAN_PASS'} = $bmwqemu::vars{AMT_PASSWORD};

    return $class->SUPER::new;
}

sub wsman_cmdline {
    my ($self) = @_;

    return ('wsman', '-h', $bmwqemu::vars{AMT_HOSTNAME}, '-P', '16992');
}

sub wsman {
    my ($self, $cmd, $stdin) = @_;

    my @cmd = $self->wsman_cmdline();
    push(@cmd, split(/ /, $cmd));

    my ($stdout, $stderr, $ret);
    bmwqemu::diag("AMT cmd: @cmd");
    $ret = IPC::Run::run(\@cmd, \$stdin, \$stdout, \$stderr);
    chomp $stdout;
    chomp $stderr;

    die join(' ', @cmd) . ": $stderr" unless ($ret);
    bmwqemu::diag("AMT: $stdout");
    return $stdout;
}

# enable SOL + IDE-r
sub enable_solider {
    my ($self) = @_;

    $self->wsman("invoke -a RequestStateChange $AMT/AMT_RedirectionService -k RequestedState=32771");
}

sub configure_vnc {
    my ($self) = @_;

    # is turning it off first necessary?
    #$self->wsman("invoke -a RequestStateChange $CIM/CIM_KVMRedirectionSAP -k RequestedState=3");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k RFBPassword=$vnc_password");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k Is5900PortEnabled=true");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k OptInPolicy=false");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k SessionTimeout=0");
    $self->wsman("invoke -a RequestStateChange $CIM/CIM_KVMRedirectionSAP -k RequestedState=2");
}

sub get_power_state {
    my ($self) = @_;

    my $stdout = $self->wsman("get $CIM/CIM_AssociatedPowerManagementService");

    return ($stdout =~ m/:PowerState>(\d+)</)[0];
}

sub set_power_state {
    my ($self, $power_state) = @_;

    my $cmd_stdin = "
<p:RequestPowerStateChange_INPUT xmlns:p=\"$CIM/CIM_PowerManagementService\">
  <p:PowerState>$power_state</p:PowerState>
  <p:ManagedElement>
    <a:Address xmlns:a=\"$ADR\">$ADR/role/anonymous</a:Address>
    <r:ReferenceParameters xmlns:r=\"$ADR\">
      <u:ResourceURI xmlns:u=\"$XSD\">$CIM/CIM_ComputerSystem</u:ResourceURI>
      <s:SelectorSet xmlns:s=\"$XSD\">
        <s:Selector Name=\"Name\">ManagedSystem</s:Selector>
      </s:SelectorSet>
    </r:ReferenceParameters>
  </p:ManagedElement>
</p:RequestPowerStateChange_INPUT>
";
    my $stdout = $self->wsman("-J - invoke -a RequestPowerStateChange $CIM/CIM_PowerManagementService", $cmd_stdin);

    return ($stdout =~ m/:ReturnValue>(\d+)</);
}

sub select_next_boot {
    my ($self, $bootdev) = @_;

    my $amt_bootdev;
    if ($bootdev eq 'cddvd') {
        $amt_bootdev = 'Intel(r) AMT: Force CD/DVD Boot';
    }
    elsif ($bootdev eq 'hdd') {
        $amt_bootdev = 'Intel(r) AMT: Force Hard-drive Boot';
    }
    elsif ($bootdev eq 'pxe') {
        $amt_bootdev = 'Intel(r) AMT: Force PXE Boot';
    }
    else {
        die "Unsupported boot device $bootdev";
    }

    # reset boot configuration to known state
    my $keys = "-k BIOSPause=false -k BootMediaIndex=0";
    $keys = "$keys -k ConfigurationDataReset=false -k FirmwareVerbosity=0 ";
    $keys = "$keys -k ForcedProgressEvents=false -k LockKeyboard=false ";
    $keys = "$keys -k LockPowerButton=false -k LockResetButton=false ";
    $keys = "$keys -k LockSleepButton=false -k ReflashBIOS=false";
    $keys = "$keys -k UseSafeMode=false -k UserPasswordBypass=false";
    $keys = "$keys -k IDERBootDevice=0 -k UseIDER=false -k UseSOL=false";
    $keys = "$keys -k BIOSSetup=false";
    $self->wsman("put $AMT/AMT_BootSettingData $keys");

    # set requested boot device
    my $cmd_stdin = "
<p:ChangeBootOrder_INPUT xmlns:p=\"$CIM/CIM_BootConfigSetting\">
  <p:Source>
    <a:Address xmlns:a=\"$ADR\">$ADR/role/anonymous</a:Address>
    <r:ReferenceParameters xmlns:r=\"$ADR\">
      <u:ResourceURI xmlns:u=\"$XSD\">$CIM/CIM_BootSourceSetting</u:ResourceURI>
      <s:SelectorSet xmlns:s=\"$XSD\">
        <s:Selector Name=\"InstanceID\">$amt_bootdev</s:Selector>
      </s:SelectorSet>
    </r:ReferenceParameters>
  </p:Source>
</p:ChangeBootOrder_INPUT>";

    my $stdout = $self->wsman("-J - invoke -a ChangeBootOrder $CIM/CIM_BootConfigSetting", $cmd_stdin);

    # TODO: setting idercd/iderfd/sol/bios/idersolcd/idersolfd/biossol require
    # one more call to AMT_BootSettingData here

    if (!($stdout =~ m/:ReturnValue>0</)) {
        die "ChangeBootOrder failed";
    }

    $cmd_stdin = "
<p:SetBootConfigRole_INPUT xmlns:p=\"$CIM/CIM_BootService\">
  <p:BootConfigSetting>
    <a:Address xmlns:a=\"$ADR\">$ADR/role/anonymous</a:Address>
    <r:ReferenceParameters xmlns:r=\"$ADR\">
      <u:ResourceURI xmlns:u=\"$XSD\">$CIM/CIM_BootConfigSetting</u:ResourceURI>
      <s:SelectorSet xmlns:s=\"$XSD\">
        <s:Selector Name=\"InstanceID\">Intel(r) AMT: Boot Configuration 0</s:Selector>
      </s:SelectorSet>
    </r:ReferenceParameters>
  </p:BootConfigSetting>
  <p:Role>1</p:Role>
</p:SetBootConfigRole_INPUT>";

    $stdout = $self->wsman("-J - invoke -a SetBootConfigRole $CIM/CIM_BootService", $cmd_stdin);

    if (!($stdout =~ m/:ReturnValue>0</)) {
        die "SetBootConfigRole failed";
    }

}

sub restart_host {
    my ($self) = @_;
    $self->set_power_state($self->is_shutdown() ? 2 : 5);
}

sub do_start_vm {
    my ($self) = @_;


    #if (!$self->{configured}) {
    #   $self->enable_solider();
    #   $self->configure_vnc();
    #   $self->{configured} = 1;
    #}
    $self->select_next_boot('pxe');

    # remove backend.crashed
    $self->unlink_crash_file;
    $self->restart_host;
    sleep(5);
    $self->truncate_serial_file;
    my $sol = $testapi::distri->add_console('sol', 'amt-sol');
    $sol->backend($self);

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname        => $bmwqemu::vars{AMT_HOSTNAME},
            password        => $vnc_password,
            connect_timeout => 3,
            port            => 5900
        });

    $vnc->backend($self);
    try {
        local $SIG{__DIE__} = undef;
        $self->select_console({testapi_console => 'sut'});
    }
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    # need to terminate both VNC and console first, otherwise AMT will refuse
    # to shutdown
    $self->deactivate_console({testapi_console => 'sol'});
    $self->deactivate_console({testapi_console => 'sut'});
    $self->set_power_state(8);
    return {};
}

sub is_shutdown {
    my ($self) = @_;
    my $ret = $self->get_power_state();
    return $ret == 8;
}

1;
