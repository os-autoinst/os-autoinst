# Networking in OpenQA
There are three possible network configurations for OpenQA virtual machines (VM).
The configuration is controlled by NICTYPE and MULTINET variables passed from OpenQA.

## default situation
By default NICTYPE is set to "user" and MULTINET is not set. In this case, each VM is created
with one network device, QEMU provided DHCP configuration. "User" network mode does have a
limitation - only TCP and UDP are supported. However no additional configuration is needed.

## multiple network devices
When MULTINET variable is set, only NICTYPE set to "user" is supported. In this case, each VM
is created with two network devices using "user" network mode.

## TAP device support
When advanced configurations, routing or better performance is required, NICTYPE can be set to
"tap". In this case, preconfigured TAP device on host system is used as VM network device.
Which TAP device is used depends on TAPDEV variable which is automatically set to "tap" + worker id - 1,
i.e. worker1 uses tap0, worker 6 uses tap5. This mode requires system administrator to create
TAP device for each running worker and to manually prepare any routing or bridging before "tap"
networking can be used. TAP devices need to be created with proper permissions so VMs can access
them, e.g. "tunctl -u _openqa-worker -p -t tap0". Up to three TAP devices supported (NICTYPE, NICTYPE_1, NICTYPE_2).
To change network settings after the VM creation configuration scripts can be used 
(path to the scripts specified in TAPSCRIPT, TAPSCRIPT_1, TAPSCRIPT_2 variables).
Sample script to attach TAP device to bridge br0:
```
#!/bin/sh
brctl addif br0 $1
ip link set $1 up
```
