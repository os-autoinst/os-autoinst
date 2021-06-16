# Backends in openQA
OpenQA (or actually os-autoinst) supports multiple backends to run the SUT.
This document is meant to describe their particularities. So far only svirt
is covered, though.

For backend specific variables, there is a [separate documentation](backend_vars.asciidoc).

## svirt
This backend establishes an SSH connection to another machine to start there
a virtual machine using libvirt/virsh which uses QEMU, Xen, Hyper-V or VMWare
under the hood.

### Local setup
Simply configure it to connect to the local machine and install libvirt/virsh.

#### Worker configuration
Example configuration for using QEMU under the hood (add to `$OPENQA_CONFIG/workers.ini`):
```
[2]
BACKEND=svirt
VIRSH_HOSTNAME=127.0.0.1 # use our own machine as svirt host
VIRSH_USERNAME=root # see notes
VIRSH_CMDLINE=ifcfg=dhcp
VIRSH_MAC=52:54:00:12:34:56
VIRSH_OPENQA_BASEDIR=/var/lib # set in accordance with OPENQA_BASEDIR (by default /var/lib)
WORKER_CLASS=svirt,svirt-kvm
VIRSH_INSTANCE=1
#VIRSH_PASSWORD=# see notes
VIRSH_GUEST=127.0.0.1
VIRSH_VMM_FAMILY=kvm
VIRSH_VMM_TYPE=hvm
```

##### Notes
To allow an SSH connection to your local machine, either put your (root) password
in the worker configuration or add your key to `$HOME/.ssh/authorized_keys`.

#### libvirt configuration
Packages to install and services to start (example for openSUSE):
```
zypper in libvirt-client libvirt-daemon libvirt-daemon-driver-interface libvirt-daemon-driver-qemu libvirt-daemon-qemu
zypper in virt-manager # a GUI for libvirt, not really required for openQA but sometimes still useful
systemctl start libvirtd sshd
```

Otherwise there is no configuration required. The test will configure libvirt on its
own. By default, the openSUSE test distribution uses the domain name `openQA-SUT-1`.
So you can for instance use `virsh dumpxml openQA-SUT-1` to investigate the configuration
of the running virtual machine.


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
