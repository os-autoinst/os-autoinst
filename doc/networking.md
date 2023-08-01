# Networking in openQA
There are three possible network configurations for openQA virtual machines when using the
qemu backend.

The configuration is controlled by NICTYPE, NICMAC and NICVLAN variables passed from openQA.

## Default situation
By default NICTYPE is set to "user". In this case, each VM is created
with one network device, QEMU provided DHCP configuration. "User" network mode does have a
limitation - only TCP and UDP are supported. However no additional configuration is needed.

## Options for "user" mode
If options for "user" mode are required, they can be set in NICTYPE_USER_OPTIONS variable.

## TAP device support

When advanced configurations, routing or better performance is required,
NICTYPE can be set to "tap". In this case, preconfigured TAP device on host
system is used as VM network device.  Which TAP device is used depends on
TAPDEV variable which is automatically set to "tap" + worker id - 1, i.e.
worker1 uses tap0, worker 6 uses tap5. This mode requires the system
administrator to create a TAP device for each running worker and to manually
prepare any routing or bridging before "tap" networking can be used. TAP
devices need to be created with proper permissions so VMs can access them,
e.g. "tunctl -u _openqa-worker -p -t tap0".

Some configuration can also be configured by environment variables as defined
in the script `os-autoinst-openvswitch`.

The script `script/os-autoinst-setup-multi-machine` can be used to setup
common dependencies for that setup to work including firewalld configuration
and TAP and bridge device setup.

## Multiple network devices
To create multiple network devices, one can set multiple, comma-separated MAC addresses
via NICMAC. The TAPDEV variable supports multiple, comma-separated values, too.

---

Also have a look at [Multi Machine Tests Setup](http://open.qa/docs/#_multi_machine_tests_setup)
documentation.
