# Copyright © 2021 SUSE LLC
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

package backend::vagrant;

use base 'backend::virt';
use bmwqemu;
use testapi ();

use Mojo::Base -strict, -signatures;
use Mojo::File;
use Cwd qw(abs_path);
use File::Temp;
use File::chdir;
use IPC::Run;
use Time::Seconds;

sub new ($class) {
    my $self = $class->SUPER::new;
    my $vars = \%bmwqemu::vars;

    $self->{vagrant_cwd} = File::Temp->newdir();
    $self->{up_timeout}  = $vars->{VAGRANT_UP_TIMEOUT} // 300;
    $self->{provider}    = $vars->{VAGRANT_PROVIDER}   // die 'Need variable \'VAGRANT_PROVIDER\'';
    $self->{box_name}    = $vars->{VAGRANT_BOX}        // die 'Need variable \'VAGRANT_BOX\'';
    $self->{box_url}     = $vars->{VAGRANT_BOX_URL};

    if (substr($self->{box_name}, 0, 1) eq '/') {
        my $asset_dir    = $vars->{VAGRANT_ASSETDIR} // die 'Need variable \'VAGRANT_ASSETDIR\' when using local vagrant boxes';
        my $box_abs_path = undef;

        opendir(my $dh, $asset_dir) or die "Could not opendir $asset_dir: $!";

        my $box_path = abs_path("$asset_dir$self->{box_name}");
        die "File $box_path does not exist" unless (-e $box_path);
        $self->{box_name} = $box_path;
    }

    $self->{libvirt_pool_name} = undef;

    my $path = Mojo::File::path($self->{vagrant_cwd})->make_path();
    $self->{vagrantfile} = $path->child("Vagrantfile");
    bmwqemu::diag("Writing Vagrantfile to $self->{vagrantfile}");

    my $vagrant_file_contents = <<END;
Vagrant.configure("2") do |config|
  config.vm.box = "$self->{box_name}"
END
    if (defined($self->{box_url})) {
        $vagrant_file_contents .= <<END;
  config.vm.box_url = "$self->{box_url}"
END
    }
    $vagrant_file_contents .= <<END;
  config.vm.synced_folder ".", "/vagrant", disabled: true
END


    if ($self->{provider} eq 'virtualbox') {
        $vagrant_file_contents .= <<END;
  config.vm.provider "virtualbox" do |v|
    v.memory = $vars->{QEMURAM}
    v.cpus = $vars->{QEMUCPUS}
  end
END
    } elsif ($self->{provider} eq 'libvirt') {
        $self->{libvirt_storage_pool_path} = "$self->{vagrant_cwd}/pool";
        mkdir $self->{libvirt_storage_pool_path};
        $self->{libvirt_pool_name} = "vagrant" . int(rand(100000));

        $vagrant_file_contents .= <<END;
  config.vm.provider :libvirt do |libvirt|
    libvirt.cpus = $vars->{QEMUCPUS}
    libvirt.memory = $vars->{QEMURAM}
    libvirt.storage_pool_name = "$self->{libvirt_pool_name}"
  end
END
    } else {
        die "got an unknown vagrant provider $self->{provider}";
    }

    $vagrant_file_contents .= <<END;
end
END

    $self->{vagrantfile}->spurt($vagrant_file_contents);

    return $self;
}

sub run_vagrant_command ($self, $args) {
    my ($retval, $stdin, $stdout, $stderr);

    my @vagrant_cmd = ("vagrant", $args->{cmd});
    push(@vagrant_cmd, ("--machine-readable")) unless $args->{not_machine_readable};
    push @vagrant_cmd, @{$args->{extra_args}} if defined $args->{extra_args};
    my $timeout = $args->{timeout} // ONE_MINUTE;

    bmwqemu::diag("Invoking vagrant command: @vagrant_cmd");
    {
        local $CWD = $self->{vagrant_cwd};
        my $handle = IPC::Run::start(\@vagrant_cmd, \$stdin, \$stdout, \$stderr, IPC::Run::timeout($timeout));
        IPC::Run::finish($handle);
        $retval = $handle->full_result(0);
    }

    return {retval => $retval, stdout => $stdout, stderr => $stderr};
}

sub get_ssh_credentials ($self) {
    my $vagrant_ssh_conf_res = $self->run_vagrant_command({cmd => "ssh-config", not_machine_readable => 1});
    die "obtaining the ssh config failed!" unless $vagrant_ssh_conf_res->{retval} == 0;
    my $stdout    = $vagrant_ssh_conf_res->{stdout};
    my %con_creds = (
        hostname => "localhost",
        username => "vagrant",
        password => "vagrant",
        port     => 22
    );

    if ($stdout =~ m/\w*HostName (.*)/) {
        $con_creds{hostname} = $1;
    }
    if ($stdout =~ m/\w*User (.*)/) {
        $con_creds{username} = $1;
    }
    if ($stdout =~ m/\w*Port (\d+)/) {
        $con_creds{port} = $1;
    }
    return %con_creds;
}

sub do_start_vm ($self) {
    if (defined($self->{libvirt_pool_name})) {
        my ($stdout, $stderr, $virsh_res);

        my @virsh_cmd = ("virsh", "pool-create-as", "--target", $self->{libvirt_storage_pool_path}, "--name", $self->{libvirt_pool_name}, "--type", "dir");
        my $handle    = IPC::Run::start(\@virsh_cmd, \undef, \$stdout, \$stderr);
        IPC::Run::finish($handle);
        $virsh_res = $handle->full_result(0);

        # don't die in case that the storage pool already exists, but die if
        # there's a different error
        my $re = qr/pool '$self->{libvirt_pool_name}' already exists with uuid/;
        die "Create libvirt storage pool failed with exit code: $virsh_res\n, $stdout\n, $stderr\n"
          if (($virsh_res != 0) && !($stderr =~ m/$re/));
    }

    my @prov = ("--provider", $self->{provider});
    my $args = {cmd => "up", extra_args => \@prov, timeout => $self->{up_timeout}};

    my $res = $self->run_vagrant_command($args);
    die "Failed to execute vagrant up, got:\n$res->{stdout}\n\n$res->{stderr}\n"
      unless $res->{retval} == 0;

    my %ssh_creds = $self->get_ssh_credentials();
    my $ssh       = $testapi::distri->add_console('vagrant-ssh', 'ssh-serial', \%ssh_creds);
    $ssh->backend($self);

    return {};
}

sub do_stop_vm ($self) {
    my $res = $self->run_vagrant_command({cmd => "halt"});
    if ($res->{retval} != 0) {
        bmwqemu::fctwarn("vagrant: failed to execute vagrant halt, got $res->{retval},\n$res->{stdout}\n$res->{stderr}");
    }

    my @extra_args  = ("-f");
    my $destroy_res = $self->run_vagrant_command({cmd => "destroy", extra_args => \@extra_args});
    if ($destroy_res->{retval} != 0) {
        bmwqemu::fctwarn("vagrant: failed to destroy the vagrant VM, got:\n$destroy_res->{stdout}\n$destroy_res->{stderr}");
    }

    # ensure that the box is gone:
    my $extra_remove_args = ["remove", "-af", "--provider", $self->{provider}, $self->{box_name}];
    my $box_remove_res    = $self->run_vagrant_command({cmd => "box", extra_args => $extra_remove_args});
    if ($box_remove_res->{retval} != 0) {
        bmwqemu::fctwarn("vagrant: failed to destroy the vagrant box $self->{box_name}, got:\n$box_remove_res->{stdout}\n$box_remove_res->{stderr}");
    }

    if (defined($self->{libvirt_pool_name})) {
        my ($stdout, $stderr, $virsh_res);
        my @virsh_cmd = ("virsh", "pool-destroy", $self->{libvirt_pool_name});
        my $handle    = IPC::Run::start(\@virsh_cmd, \undef, \$stdout, \$stderr);
        IPC::Run::finish($handle);
        $virsh_res = $handle->full_result(0);

        if ($virsh_res != 0) {
            bmwqemu::fctwarn("vagrant: failed to destroy the libvirt storage pool $self->{libvirt_pool_name}, got $virsh_res\n$stdout\n$stderr");
        }
    }
}

sub run_cmd ($self, $cmd) {
    my @args = ('--', split(/ /, $cmd));
    my $res  = $self->run_vagrant_command({cmd => "ssh", not_machine_readable => 1, extra_args => \@args});

    chomp $res->{stdout};
    return $res->{stdout};
}

sub can_handle { }

# don't use signatures here, as is_shutdown also receives some additional args
# that are not really used anywhere
sub is_shutdown {
    my ($self) = @_;
    my $res = $self->run_vagrant_command({cmd => "status", timeout => 5});
    chomp($res->{stdout});
    return $res->{stdout} =~ /default,state,(shutoff|not_created|poweroff)/;
}

sub check_socket ($self, $fh, $write) {
    return $self->SUPER::check_socket($fh, $write);
}

sub stop_serial_grab { }

1;
