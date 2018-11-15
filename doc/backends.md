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
