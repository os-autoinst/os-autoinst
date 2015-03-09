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
them, e.g. "tunctl -u _openqa-worker -p -t tap0"
