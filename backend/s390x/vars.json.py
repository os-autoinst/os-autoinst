#!/usr/bin/python3

# generate vars.json

import collections
import os

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
            "Portname": "VSWNL2",
            "ReadChannel": "0.0.7100",
            "WriteChannel": "0.0.7101",
            "DataChannel": "0.0.7102",
            "OSAHWAddr":"",
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

sshpassword = "nots3cr3t"
Xvnc_DISPLAY = 91

console_vars = lambda Xvnc_DISPLAY: {
    "ssh": {
        "PARMFILE": {
            "ssh": "1",
            "sshpassword" : sshpassword,
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
            # run a local X server with it's screen  open to the world, like this:
            # Xvnc -ac -SecurityTypes=none :77
            "HOST"   : my_ip,
            "SCREEN" : Xvnc_DISPLAY,
        },
        "PARMFILE": {
            "Display_IP" : "{}:{}".format(my_ip, Xvnc_DISPLAY),
            # http://bugzilla.suse.com/show_bug.cgi?id=920635
            "Y2FULLSCREEN": "1",
        }
    },
    # FIXME:  get ssh -X working
    "ssh-X": {
       "PARMFILE": {
           "ssh": "1",
           "sshpassword" : sshpassword,
       },
       "DISPLAY" : {
           "TYPE" : "SSH-X",
       },
    },
}

def update_vars_json(vars_json):
    guest          = vars_json["S390_HOST"]
    network_device = vars_json["S390_NETWORK"]
    instsource     = vars_json["S390_INSTSRC"]
    console        = vars_json["S390_CONSOLE"]
    distro         = os.path.basename(vars_json["ISO"][:-len('.iso')])

    vars_json_basics = {
        "BACKEND"	: "s390x",
        "ZVM_HOST"	: zVM_HOST,
        "ZVM_GUEST"     : "linux{guest}".format(guest=guest),
        "ZVM_PASSWORD"	: "lin390",

        "NETWORK"       : network_device,

        "DEBUG"         : {
            #"wait after linuxrc": None,
            #    pauses os-autoinst just before it connects to YaST, right after linuxrc.
            #    also see PARMFILE: startshell
            #"keep zVM guest": None,
            #    do #cp disconnect at the end instead of #cp logoff
            # "try vncviewer": None,
            #    don't connect and initialize.  Just do the vnc connect and
            #    go from there.
            # "vncviewer" : None,
            #    start local vncviewer
        },

        "PARMFILE" : {
            # nameserver
            "Nameserver" : "10.160.0.1",
            "Domain"	 : "suse.de",
            # *ALLWAYS* enable sshd 'backdoor' in our tests
            "sshd"        : "1",
            "sshpassword": sshpassword,
            # inject a DUD.  only works in manual=0 unattended mode!
            #"dud": "http://w3.suse.de/~snwint/bnc_913888.dud",
            # "startshell":"1".
            "manual": "0",
        }
    }

    unify(vars_json, vars_json_basics)

    network_vars = get_network_parms(guest, network_device)

    unify(vars_json, network_vars)

    Xvnc_DISPLAY = vars_json['VNC']
    unify(vars_json, console_vars(Xvnc_DISPLAY)[console])

    vars_json["INSTSRC"] = {
            "HOST":     "openqa",
            "PROTOCOL": "FTP",
            "DIR_ON_SERVER": "/" + vars_json['REPO_8'] + "/",
            "FTP_USER": "anonymous"
    }
    vars_json["FTPBOOT"] =  {
        "COMMAND"  : "qaboot",
        "FTP_SERVER"     : "openqa",
        "PATH_TO_SUSE_INS": vars_json['REPO_8']
    }

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
    #_script, insthost, host, network, instsrc, console, distro = sys.argv

    import os.path
    with open("vars.json") as f:
        vars_json = json.load(f);

    print(json.dumps( update_vars_json( vars_json ), indent=True ))
