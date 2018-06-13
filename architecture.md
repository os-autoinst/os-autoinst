# os-autoinst architecture
This document gives an overview about the multi-process architecture of os-autoinst.

## Process tree
Once everything is running, the process tree looks like this:

* **isotovideo**: spawns further processes, IO-loop for passing commands (main occupation), cleanup  
  relevant files: `isotovideo`

    * **backend**: spawns and handles backend (eg. qemu), receives commands from isotovideo IO-loop,
                   handles the VNC connections, makes regular screenshots  
      files: `baseclass.pm` and derived, `console.pm` and derived

        * **qemu** (for instance)

        * **videoencoder**: encodes the Ogg Theora file  
          relevant files: `videoencoder.cpp`

    * **autotest**: determines test order, runs test code and thus testapi functions, sends
                    commands to isotovideo IO-loop (via `query_isotovideo`)  
      relevant files: `autotest.pm`, `testapi.pm`, `console_proxy.pm`, `basetest.pm` and derived

    * **command server**: provides GET/POST HTTP routes and WS server, passes commands received via
                          WS to isotovideo IO-loop  
      relevant files: `commands.pm`, `OpenQA/Commands.pm`

### Further notes
* The lists of relevant files has been reduced to the most important ones.
* **isotovideo** starts everything and passes commands between the other processes.
* All processes have an IO loop except **autotest**. The latter mainly executes the test code and
  everything else reacts to it.
* The command server is accessed by the openQA worker and livehandler.