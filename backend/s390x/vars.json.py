#!/usr/bin/python3

# generate vars.json

import collections

# unify two dictionaries, *updating old_dict*
def unify(old_dict, new_dict):
    for k, v in new_dict.items():
        if k in old_dict:
            d = old_dict[k]
            if d is None:
                old_dict[k] = v
            elif isinstance(d, collections.Mapping):
                if isinstance(v, collections.Mapping):
                    unify(d, v)
                else:
                    raise TypeError
            elif v is None:
                pass
            elif v != d:
                raise ValueError("conflicting values in unification: %s != %s"%(v,d))
            else:
                assert(v == d)
        else:
            old_dict[k] = v

from collections import namedtuple

hostname =  lambda _if: (
    lambda _ip: "s390{_if}{_ip}.suse.de".format(_if=_if, _ip=_ip)
)

hostip_10_161_if_ip_nm = lambda _if, _nm: (
    lambda _ip: '10.161.{_if}.{_ip}{_nm}'.format(_if=_if, _ip=_ip, _nm=_nm)
)

gateway = lambda _if: "10.161.{_if}.254".format(_if=_if)

Devinfo = namedtuple("Devinfo", ["ip",
                                 "hostname",
                                 "gateway",
                                 "parmfile"])

devinfo = {
    "ctc": Devinfo(
        hostip_10_161_if_ip_nm("189",""),
        hostname("ctc"),
        gateway("189"),
        {
            "InstNetDev"   : "ctc",
            "CTCProtocol"  : "0",
            "Pointopoint"  : gateway("189"),
            "ReadChannel"  : "0.0.0600",
            "WriteChannel" : "0.0.0601",
        }),
    "iucv": Devinfo(
        hostip_10_161_if_ip_nm("187", ""),
        hostname("icv"),
        gateway("187"),
        {
            "InstNetDev": "iucv",
            "Pointopoint"  : gateway("187"),
            "IUCVPeer": "ROUTER01",
        }),
    "hsi-l2": Devinfo(
        hostip_10_161_if_ip_nm("183","/24"),
        hostname("hsl"),
        gateway("183"),
        {
            "PortNo": "0",
            "Layer2": "1",
            "InstNetDev":"osa",
            "OSAInterface":"qdio",
            "OSAMedium":"eth",
            #"Portname": "VSWNL2",
            #"ReadChannel": "0.0.8000",
            #"WriteChannel": "0.0.8001",
            #"DataChannel": "0.0.8002",
        }),
    "hsi-l3": Devinfo(
        hostip_10_161_if_ip_nm("185","/24"),
        hostname("hsi"),
        gateway("185"),
        {
            "PortNo": "0",
            "Layer2": "0",
            "InstNetDev":"osa",
            "OSAInterface":"qdio",
            "OSAMedium":"eth",
            "Portname": "trash",
            "ReadChannel": "0.0.7000",
            "WriteChannel": "0.0.7001",
            "DataChannel": "0.0.7002",
        }),
    "vswitch-l2": Devinfo(
        hostip_10_161_if_ip_nm("155","/20"),
        hostname("vsl"),
        gateway("159"),
        {
            "PortNo": "0",
            "Layer2": "1",
            "Portname": "VSWNL2",
            "ReadChannel": "0.0.0800",
            "WriteChannel": "0.0.0801",
            "DataChannel": "0.0.0802",
            "InstNetDev":"osa",
            "OSAInterface":"qdio",
            "OSAMedium":"eth",
            # "02:00:00:00:42:{guest:2x}".format(guest=157)
            # use the default
            "OSAHWAddr":"",
        }),
    "vswitch-l3": Devinfo(
        hostip_10_161_if_ip_nm("157","/20"),
        hostname("vsw"),
        gateway("159"),
        {
            "PortNo": "0",
            "Layer2": "0",
            "Portname": "VSWN1",
            "ReadChannel": "0.0.0700",
            "WriteChannel": "0.0.0701",
            "DataChannel": "0.0.0702",
            "OSAInterface":"qdio",
            "OSAMedium":"eth",
            "InstNetDev":"osa",
        }),
}


# these are used interchangeably
devinfo['osa-l2'] = devinfo['vswitch-l2']
devinfo['osa-l3'] = devinfo['vswitch-l3']


def get_network_parms(guest, network_device):

    _devinfo = devinfo[network_device]

    network_parms = {
        "PARMFILE"              : {
            "HostIP"    : _devinfo.ip(guest),
            "Hostname"  : _devinfo.hostname(guest),
            "Gateway"   : _devinfo.gateway,
        }
    }

    unify(network_parms, { "PARMFILE": _devinfo.parmfile })

    return network_parms


zVM_HOST = "zvm54.suse.de"

import socket
# unreadable one-liner variant of a simple function that isn't needed after this, from stackoverflow...
my_ip = [(s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1),
          s.connect((zVM_HOST, 0)),
          s.getsockname()[0],
          s.close()) for s in [socket.socket(socket.AF_INET, socket.SOCK_DGRAM)]][0][2]

insthost_vars = {
    "dist": {
        "INSTSRC": {
            # dist.suse.de
            "HOST":     "10.160.0.100",
        },
        "FTPBOOT" : {
            "COMMAND"  : "ftpboot",
            "HOST"     : "DIST.SUSE.DE",
        }
    },
    # to use this, restrict on FTP, run a local tftpd with anonymous access.
    # use frohboot instead of ftpboot.
    "localhost": {
        "INSTSRC": {
            "PROTOCOL":"FTP",
            "HOST":     my_ip,
        },
        "FTPBOOT" : {
            "COMMAND"  : "frohboot",
            "HOST"     : my_ip,
        },
        # We use localhost for debugging purposes.  It will always be
        # unsigned, thus insecure.
        "PARMFILE": {
            "insecure": "1",
        },
    },
}

instsrc_vars = {
    "ftp": {
        "INSTSRC": {
            "PROTOCOL":"FTP",
        },
    },
    "http": {
        "INSTSRC": {
            "PROTOCOL": "HTTP",
        },
    },
    "https": None,
    "nfs": {
        "INSTSRC": {
            "PROTOCOL": "NFS",
        },
    },
    "smb": {
        "INSTSRC": {
            "PROTOCOL": "SMB",
        },
    },
    "tftp": None,
}

console_vars = {
    "ssh": {
        "PARMFILE": {
            "ssh": "1",
            "sshpassword" : "SSH!554!",
        },
        "DISPLAY" : {
            "TYPE" : "SSH",
        },
    },
    "vnc": {
        "DISPLAY": {
            "TYPE" : "VNC",
            "PASSWORD": "FOOBARBAZ",
        },
        "PARMFILE": {
            "VNC":  "1",
            "VNCPassword": "FOOBARBAZ",
            "VNCSize": "1024x768",
        }
    },
    "x11": {
        "DISPLAY": {
            "TYPE" : "X11",
            # run a local X server with screen 1 open to the world, like this:
            # Xvnc -ac -SecurityTypes=none :1
            "HOST"   : my_ip,
            "SCREEN" : "1",
        },
        "PARMFILE": {
            "Display_IP" : "{}:1".format(my_ip)
        }
    },
    # FIXME:  get ssh -X working
    #"ssh-X": {
    #    "PARMFILE": {
    #        "ssh": "1",
    #        "sshpassword" : "SSH!554!",
    #    },
    #    "DISPLAY" : {
    #        "TYPE" : "SSH",
    #    },
    #},
}

def make_vars_json(insthost, guest, network_device, instsource, console, distro):

    vars_json = {

        "DISTRI"	: "sle",
        "CASEDIR"	: "/space/SVN/os-autoinst-distri-opensuse/",

        "BACKEND"	: "s390x",
        "ZVM_HOST"	: zVM_HOST,

        "DEBUG"         : [
            "wait after linuxrc",
            #    pauses os-autoinst just before it connects to YaST, rigth after linuxrc.
            #    also see PARMFILE: startshell
            "keep zVM guest",
            #    do #cp disconnect at the end instead of #cp logoff
            # "try vncviewer",
            #    don't connect and initialize.  Just do the vnc connect and
            #    go from there.
        ],

        "BETA": "1",

        "ZVM_GUEST"     : "linux{guest}".format(guest=guest),
        "ZVM_PASSWORD"	: "lin390",

        "NETWORK"       : network_device,

        "PARMFILE" : {
            # nameserver
            "Nameserver" : "10.160.0.1",
            "Domain"	 : "suse.de",
            # *ALLWAYS* enable sshd in our tests
            "sshd"        : "1",
            "sshpassword": "SSH!554!",
            # inject a DUD.  only works in manual=0 unattended mode!
            #"dud": "http://w3.suse.de/~snwint/bnc_913888.dud",
            # "startshell":"1".
            "manual": "0",
            #"dud": "nfs://10.160.0.111:/real-home/snwint/Export/bnc_913888.dud",
            #"dud": "ftp://{host}/bnc_913888/bnc_913888.dud".format(host=my_ip),
            #"linuxrc.log":"/dev/console",
            ##startshell=1 linuxrc.log=/dev/console
            ##install=http://10.160.0.100/install/SLP/SLES-11-SP4-Alpha3/s390x/DVD1
            ##InstNetDev=osa OSAInterface=qdio OSAMedium=eth

        }
    }

    network_vars = get_network_parms(guest, network_device)

    unify(vars_json, network_vars)

    unify(vars_json, {
        "FTPBOOT" : {
            # host comes from insthost_vars...
            # "HOST"     : "DIST\\.SUSE\\.DE",
            "DISTRO"   : distro
        },
    })

    unify(vars_json, {
        "INSTSRC": {
            "PROTOCOL": instsource.upper(),
            "DIR_ON_SERVER": "{prefix}/install/SLP/{distro}/s390x/DVD1".format(
                distro=distro,
                prefix= "/dist" if instsource == "nfs" else ""
            ),
            "FTP_USER": "anonymous"
        },
    } )

    unify(vars_json, console_vars[console])

    unify(vars_json, instsrc_vars[instsource])

    unify(vars_json, insthost_vars[insthost])

    vars_json["PARMFILE"]["install"] = "{protocol}://{host}{dir_on_server}".format(
        protocol=instsource.lower(),
        host=vars_json["INSTSRC"]["HOST"],
        dir_on_server=vars_json["INSTSRC"]["DIR_ON_SERVER"]
        )


    return vars_json


import json
from pprint import pprint as pp
import sys
if __name__ == "__main__":
    _script, insthost, host, network, instsrc, console, distro = sys.argv

    print(json.dumps( make_vars_json( insthost, host, network, instsrc, console, distro), indent=True ))

    #pp( make_vars_json("155", "hsi-l3", "http", "vnc", "SLES-11-SP4-Alpha2"))
    #pp( make_vars_json("156", "ctc", "ftp", "X11"))
    #pp( make_vars_json("157", "vswitch-l3", "http", "vnc"))
