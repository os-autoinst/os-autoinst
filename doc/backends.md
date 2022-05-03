# Backends in openQA
OpenQA (or actually os-autoinst) supports multiple backends to run the SUT. This
document is meant to describe their particularities. So far only svirt and
Vagrant are covered, though.

For backend specific variables, there is a
[separate documentation](backend_vars.asciidoc).

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
