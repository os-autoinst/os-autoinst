# Hooks called by the worker engine

## prestart
If test contains **prestart.pm** file in its root directory, this file is executed *before* testing VM is started. Useful when test interacts with some external service needed for VM boot (PXE, DHCP, NFS,etc.).

## postrun
If test contains **postrun.pm** file in its root directory, this file is executed *after* testing VM is shutdown and before worker is cleaned. Useful for log and data extraction from VM disk HDD.

## post fail
Function post_fail_hook() is called when error condition is detected. By default it is a noop, test should override this function to implement desired functionality. Useful for log and data extraction through network.

## is applicable
Function is_applicable() is called before test case is loaded during test initialization. By default it always return 1, test should override this function for controlling what parts of test are going to be run.