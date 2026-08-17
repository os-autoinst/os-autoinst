# os-autoinst architecture
This document gives an overview about the multi-process architecture of os-autoinst.

## Process tree
Once everything is running, the process tree looks like this:

* **isotovideo**: spawns further processes, IO-loop for passing commands (main occupation), cleanup  
  relevant files: `isotovideo`, `driver.pm`, `OpenQA/Isotovideo/Runner.pm`,
                  `OpenQA/Isotovideo/CommandHandler.pm`, `needle.pm` (initial needle scan)

    * **backend**: spawns and handles backend (eg. qemu), receives commands from isotovideo IO-loop,
                   handles the VNC connections, makes regular screenshots  
      relevant files: `baseclass.pm` and derived, `console.pm` and derived, `needle.pm` (reloading,
                      matching), `cv.pm`, `ppmclibs/*`

        * **qemu** (for instance)

        * **videoencoder**: encodes the Ogg Theora file  
          relevant files: `videoencoder.cpp`

    * **autotest**: determines test order, runs test code and thus testapi functions, sends
                    commands to isotovideo IO-loop (via `query_isotovideo`)  
      relevant files: `autotest.pm`, `testapi.pm`, `console_proxy.pm`, `basetest.pm` and derived,
                      `needle.pm` (needles are instantiated here as well)

    * **command server**: provides GET/POST HTTP routes and WS server, passes commands received via
                          WS to isotovideo IO-loop  
      relevant files: `commands.pm`, `OpenQA/Commands.pm`

### Further notes
* The lists of relevant files has been reduced to the most important ones.
* **isotovideo** starts everything and passes commands between the other processes.
* All processes have an IO loop except **autotest**. The latter mainly executes the test code and
  everything else reacts to it.
* The command server is accessed by the openQA worker and livehandler and the SUT via
  `autoinst_url`.

### Details about IPC between main processes
* **isotovideo**
    * in `OpenQA::Isotovideo::Runner`: tokenless `read_json` from **autotest**, **backend**,
      **command server**
    * in `driver`: `send_json` and `read_json` pair *with* tokens to send/receive to/from
      **backend**
    * in `OpenQA::Isotovideo::CommandHandler`: `send_json` to send messages to **command server**
    * in `OpenQA::Isotovideo::CommandHandler`: `send_json` to send messages to **backend**
* **autotest**
    * in `autotest`: `send_json` and `read_json` pair *with* tokens to send/receive to/from
      **isotovideo**
* **backend**
    * in `baseclass:::check_socket`: tokenless `read_json` and optional `send_json` pair to handle
      commands from **isotovideo** and send back result
        * uses the multi-flag of `read_json` to handle multiple commands at once
    * in `baseclass`: `send_json` in various places to send messages unrequested to **isotovideo**
* **command server**
    * in `commands`: tokenless `read_json` to handle commands from **isotovideo**
        * uses the multi-flag of `read_json` to handle multiple commands at once
    * in `commands::isotovideo_command`: `send_json` and `read_json` pair *without* tokens to
      send messages to **isotovideo** and wait for a response
    * in `OpenQA::Commands`: `send_json` to send messages from ws clients to **isotovideo** (which
      might handle them directly or forward them to the backend)
