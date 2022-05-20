# Copyright 2018-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::amt;

use Mojo::Base 'backend::baseclass', -signatures;
use autodie ':all';
use Time::HiRes qw(sleep gettimeofday);
use Data::Dumper;
require Carp;
use bmwqemu ();
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

sub new ($class) {
    defined $bmwqemu::vars{AMT_HOSTNAME} or die 'Need variable AMT_HOSTNAME';
    defined $bmwqemu::vars{AMT_PASSWORD} or die 'Need variable AMT_PASSWORD';

    # use env to avoid leaking password to logs
    $ENV{'WSMAN_USER'} = 'admin';
    $ENV{'WSMAN_PASS'} = $bmwqemu::vars{AMT_PASSWORD};

    backend::baseclass::handle_deprecate_backend('AMT');
    return $class->SUPER::new;
}

sub wsman_cmdline ($self) {
    return ('wsman', '-h', $bmwqemu::vars{AMT_HOSTNAME}, '-P', '16992');
}

sub wsman ($self, $cmd, $stdin = undef) {
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
sub enable_solider ($self) {
    $self->wsman("invoke -a RequestStateChange $AMT/AMT_RedirectionService -k RequestedState=32771");
}

sub configure_vnc ($self) {
    # is turning it off first necessary?
    #$self->wsman("invoke -a RequestStateChange $CIM/CIM_KVMRedirectionSAP -k RequestedState=3");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k RFBPassword=$vnc_password");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k Is5900PortEnabled=true");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k OptInPolicy=false");
    $self->wsman("put $IPS/IPS_KVMRedirectionSettingData -k SessionTimeout=0");
    $self->wsman("invoke -a RequestStateChange $CIM/CIM_KVMRedirectionSAP -k RequestedState=2");
}

sub get_power_state ($self) {
    my $stdout = $self->wsman("get $CIM/CIM_AssociatedPowerManagementService");

    return ($stdout =~ m/:PowerState>(\d+)</)[0];
}

sub set_power_state ($self, $power_state) {
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

sub select_next_boot ($self, $bootdev) {
    my $amt_bootdev = 'Intel(r) AMT: Force ' . ({
            cddvd => 'CD/DVD Boot',
            hdd => 'Hard-drive Boot',
            pxe => 'PXE Boot',
    }->{$bootdev} or die "Unsupported boot device $bootdev");

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
    die 'SetBootConfigRole failed' unless $stdout =~ m/:ReturnValue>0</;
}

sub restart_host ($self) {
    $self->set_power_state($self->is_shutdown() ? 2 : 5);
}

sub do_start_vm ($self, @) {
    $self->select_next_boot('pxe');
    $self->restart_host;
    sleep(5);
    $self->truncate_serial_file;
    my $sol = $testapi::distri->add_console('sol', 'amt-sol');
    $sol->backend($self);

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname => $bmwqemu::vars{AMT_HOSTNAME},
            password => $vnc_password,
            connect_timeout => 3,
            port => 5900
        });

    $vnc->backend($self);
    try {
        local $SIG{__DIE__} = undef;
        $self->select_console({testapi_console => 'sut'});
    }
    return {};
}

sub do_stop_vm ($self, @) {
    # need to terminate both VNC and console first, otherwise AMT will refuse
    # to shutdown
    $self->deactivate_console({testapi_console => 'sol'});
    $self->deactivate_console({testapi_console => 'sut'});
    $self->set_power_state(8);
    return {};
}

sub is_shutdown ($self, @) {
    my $ret = $self->get_power_state();
    return $ret == 8;
}

1;
