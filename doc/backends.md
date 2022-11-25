# Backends in openQA
OpenQA (or actually os-autoinst) supports multiple backends to run the SUT. This
document is meant to describe their particularities. It does not cover all
available backends, though. Note that instructions for QEMU are already given in
the main README file.

For backend specific variables, there is a
[separate documentation](backend_vars.asciidoc).

## General recommendations
Normally the execution environment for exotic backends (like svirt and s390x) is
setup in production. For development purposes it makes sense to take out an
openQA worker from production that is configured to use the backend you want to
develop for. In some cases it can also be possible to setup a suitable
environment on your local machine (see e.g. section about the svirt backend).

### Take out worker from production
1. Find a worker host of the type you need, e.g. by searching the workers table
   in web UI of the relevant openQA instance.
2. Configure an additional worker slot in your local workers.ini using worker
   settings from the corresponding production worker.
3. Take out the corresponding worker slot from production, e.g. by stopping the
   corresponding systemd unit.
4. Start the locally configured worker slot and clone/run some jobs.
5. When you're done, bring back the production worker slots.

Steps specific to SUSE's internal setup can be found in the
[openQA project Wiki](https://progress.opensuse.org/projects/openqav3/wiki/#Use-a-production-host-for-testing-backend-changes-locally-eg-svirt-powerVM-IPMI-bare-metal-s390x-etc).

## svirt
This backend establishes an SSH connection to another machine to start there
a virtual machine using libvirt/virsh which uses QEMU, Xen, Hyper-V or VMWare
under the hood.

The svirt backend is enabled via `BACKEND=svirt` and the VM used under the hood
is configured via `VIRSH_VMM_FAMILY`.

### Local setup
For running jobs using the svirt backend locally, follow the configuration steps
explained in the following sub sections.

#### openQA worker configuration
Example configuration for using the local libvirt setup with QEMU under the hood
(add to `$OPENQA_CONFIG/workers.ini`):
```
[2]
BACKEND=svirt
WORKER_CLASS=svirt,svirt-kvm
VIRSH_HOSTNAME=127.0.0.1
VIRSH_GUEST=127.0.0.1
VIRSH_USERNAME=root
VIRSH_PASSWORD=$THE_ROOT_PASSWORD
VIRSH_CMDLINE=ifcfg=dhcp
VIRSH_MAC=52:54:00:12:34:56
VIRSH_OPENQA_BASEDIR=/var/lib
VIRSH_INSTANCE=1
VIRSH_VMM_FAMILY=kvm
VIRSH_VMM_TYPE=hvm
```

If you add multiple instances, be sure to assign a different `VIRSH_INSTANCE`
and `VIRSH_MAC`. For more details about the variables, checkout
[backend_vars.asciidoc](backend_vars.asciidoc).

`VIRSH_OPENQA_BASEDIR` must be set in accordance with `OPENQA_BASEDIR` if you
changed that environment variable.

Then start the worker slot as usual. If you invoke `isotovideo` directly
(without openQA worker), these variables go to `vars.json`.

#### SSH configuration
To allow an SSH connection to your local machine, put your root password in the
worker configuration as shown in the previous section. If your root password is
entered from the configuration, that `type_string` command is logged. So be
aware that your root password will end up in `autoinst-log.txt`.

In any case, also be sure to allow root login in `/etc/ssh/sshd_config` and that
`sshd` is actually started (e.g. using `zypper in openssh-server` and
`systemctl start sshd` under openSUSE).

#### libvirt configuration
Packages to install and services to start (example for openSUSE):
```
zypper in libvirt-client libvirt-daemon libvirt-daemon-driver-interface libvirt-daemon-driver-qemu libvirt-daemon-qemu
zypper in virt-manager # a GUI for libvirt, not really required for openQA but sometimes still useful
systemctl start libvirtd
```

Otherwise there is no configuration required. The test will configure libvirt on
its own. By default, the openSUSE test distribution uses the domain name
`openQA-SUT-1`. So you can for instance use `virsh dumpxml openQA-SUT-1` to
investigate the configuration of the running virtual machine. One can also use
`virt-manager` for viewing the created VM.

#### Clone a job from production
Simply pick a normal `qemu` job matching your local architecture. You can change
the backend and worker class by simply overriding the variables via
`openqa-clone-job`. To avoid running into "VNC password is 9 characters long,
only 8 permitted" you might also want to override `PASSWORD` - although this can
lead to needle mismatches (as some needles might be specific to a certain
password length). Example for a job from the openSUSE test distribution:
```
openqa-clone-job https://openqa.opensuse.org/tests/2320084 \
    WORKER_CLASS=svirt-kvm BACKEND=svirt PASSWORD=123
```

Note that `svirt` backend normally requires additional handling on the test
distribution-side. Checkout the `bootloader_svirt` test module of the openSUSE
test distribution for details. When cloning an openSUSE test, the
`bootloader_svirt` test module is automatically added to the schedule when
setting `BACKEND=svirt`. When overriding `SCHEDULE` you have to take it into
account manually.

### Testing with remote VMWare ESXi hypervisor using local `virsh`-client
It is possible to use your local `virsh`-client to connect to a a remote VMWare
ESXi hypervisor and run tests on it.

#### libvirt configuration
Since your local libvirt tooling is used by this setup, you still need to
install at least `virsh` locally (the `libvirt-client` package under openSUSE).

In this setup, `virsh` will be invoked with the `-c` parameter to specify the remote
hypervisor host. If you want to use `virsh` manually, you also need to specify that
parameter accordingly (e.g. grab the hypervisor URL from the autoinst log while the
test is running).

Like with "Local setup" one *could* also use `virt-manager`. The `esx://`-URL
can be added as custom URL and then one is prompted for the password. I only ran
into the problem that the self-signed certificate of our hypervisor instance was
not accepted.

#### openQA worker configuration
The configuration is like the one from the "Local setup" section. The main
difference is that we now set the VMWare host and password:

```
[3]
BACKEND = svirt
WORKER_CLASS = svirt-vmware
VIRSH_HOSTNAME=127.0.0.1
VIRSH_USERNAME=root
VIRSH_PASSWORD=$THE_ROOT_PASSWORD
VIRSH_CMDLINE=ifcfg=dhcp
VIRSH_INSTANCE=10
VMWARE_HOST=$THE_HYPERVISOR_HOSTNAME
VMWARE_PASSWORD=$THE_HYPERVISOR_PASSWORD
```

You can use any number for `VIRSH_INSTANCE`. If the VMWare hypervisor host is
also used in production, it makes sense to specify a `VIRSH_INSTANCE` that is
not already used in production (which means you don't have to take out worker
slots from production).

Note that `VIRSH_INSTANCE` is not used as the VM's ID. It is used to set the
libvirt-domain, e.g. in this example the libvirt-domain would be
`openQA-SUT-10`. The actual VM-ID is assigned by VMWare and can be queried via
`virsh`, e.g. `virsh -c esx://… dumpxml openQA-SUT-10`.

#### SSH configuration
Since we're still just connecting to our own host (for the SSH part) everything
from "Local setup" applies here as well.

#### Clone a job from production
It makes most sense to clone a VMWare test scenario so simply search the
production instance for existing VMWare jobs. The variables from the worker
config should apply automatically so jobs can be cloned as-is.

#### Further notes
* Within the ESXi web interface you can monitor events and tasks which is useful
  to keep track of what's going on from VMWare's side.
* The default timeout of the ESXi web interface is very low but you can change
  the timeout in the user menu (if you are annoyed by having to re-login all the
  time).

## Vagrant

The vagrant backend leverages [vagrant](https://www.vagrantup.com/) to launch
VMs and use them as the SUT, providing a ssh connection to the SUT via `vagrant
ssh`.

The vagrant backend picks the box from the variable `VAGRANT_BOX` and the
provider from `VAGRANT_PROVIDER`. The backend also respects the `QEMUCPUS` and
`QEMURAM` variables from the `virt` backend and forwards these to vagrant.

The provider also supports setting a custom URL to the json file that vagrant
expects to receive from the a non-vagrant cloud repository. This value can be
set via the backend variable `VAGRANT_BOX_URL` and will be translated to
`config.vm.box_url` in the `Vagrantfile`. This is only required when downloading
boxes from the Open Build Service.

Alternatively to downloading boxes directly from the internet, the vagrant
backend can use vagrant boxes that are available in the directories defined by
the variable `VAGRANT_ASSETDIR`. The backend will look for a file with the name
provided in `VAGRANT_BOX` if it starts with a `/`. If the box is not found, then
the backend will report an error.


### Worker configuration

The machine invoking `os-autoinst` (commonly referred to as the worker) must
have `vagrant` installed and it needs the correct permissions to be allowed to
launch virtual machines with the desired providers: For the virtualbox provider
the worker user must be in the `vboxusers` group and for libvirt in the
`libvirt` group. The respective backends must be installed and
functional. Additionally, when using the `libvirt` provider, the worker user
must have the correct permissions to interact with the libvirt daemon and the
`virsh` command line program must be installed.

If you want to test local vagrant boxes, then you must create a directory on the
worker where the vagrant boxes will be stored and set the path to this directory
in the variable `VAGRANT_ASSETDIR`. It is recommended to configure this variable
directly on the worker and not in testsuites or anywhere else.

### Limitations

Currently the backend only supports running scripts/commands and rudimentary
checks (e.g. whether the SUT is running or shut off). Needle matching and
listening to serial lines is not supported at the moment.

## s390x
There are two approaches to run tests on s390x. One uses the `s390x` backend
(zVM) and one uses the `svirt` backend (zKVM).

The diagram on the
[openQA project Wiki](https://progress.opensuse.org/projects/openqav3/wiki/#s390x-Test-Organisation)
shows the `s390x` backend's setup at the top and the `svirt` backend's setup
at the bottom.

As mentioned in the svirt section it is generally possible to run the backend
locally. However, you would generally resort to taking out a worker from
production as explained under general recommendations.

## generalhw

The generalhw backend is used to test on real hardware. There is a variety of
configurations that are supported by this backend. Eg. it is possible to connect
to a SUT using a serial UART connection or an SSH connection via xterm console.
It is also possible to use an HDMI grabber and control a keyboard emulation device.
The backend can run scripts to powercycle the SUT and to flash an SD card using
specal hardware.

A detailed description how to use this backend can be found
[here](https://github.com/os-autoinst/os-autoinst-distri-opensuse/blob/master/data/generalhw_scripts/raspberry_pi_hardware_testing_setup.md).
