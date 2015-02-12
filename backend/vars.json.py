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
                raise ValueError
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
            "ReadChannel" : "0.0.0600",
            "WriteChannel" : "0.0.0601"
        }),
    "hsi-l2": Devinfo(
        hostip_10_161_if_ip_nm("183","/24"),
        hostname("hsl"),
        gateway("183"),
        {}),
    "hsi-l3": Devinfo(
        hostip_10_161_if_ip_nm("185","/24"),
        hostname("hsi"),
        gateway("185"),
        {}),
    "iucv": Devinfo(
        hostip_10_161_if_ip_nm("187", ""),
        hostname("icv"),
        gateway("187"),
        {}),
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
        }),
    "iucv": Devinfo(
        hostip_10_161_if_ip_nm("187",""),
        hostname("icv"),
        gateway("187"),
        {}),
}

def get_network_parms(guest, network_device):

    _devinfo = devinfo[network_device]

    network_parms = {
        "PARMFILE"		: {
            "HostIP"	: _devinfo.ip(guest),
            "Hostname"	: _devinfo.hostname(guest),
            "Gateway"	: _devinfo.gateway,
        }
    }

    unify(network_parms, { "PARMFILE": _devinfo.parmfile })

    return network_parms


console_vars = {
    "ssh": {
        "PARMFILE": {
            "ssh": "1"
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
    },
    "x11": {
        # FIXME:  ssh -X vs X11
        # "PARMFILE": {
        #     "ssh": "1"
        # },
        "DISPLAY": {
            "TYPE" : "X11",
        },
    },
}

instsrc_vars = {
    "ftp": {
        "INSTSRC": {
            "PROTOCOL":"FTP",
            # dist.suse.de
            "HOST":     "10.160.0.100",
        },
    },
    "http": {
        "INSTSRC": {
            "PROTOCOL": "HTTP",
            # dist.suse.de
            "HOST":     "10.160.0.100",
            
        },
    },
    "https": None,
    "nfs": {
        "INSTSRC": {
            "PROTOCOL": "NFS",
            # dist.suse.de
            "HOST":     "10.160.0.100",
            
        },
    },
    "smb": None,
    "tftp": None,
}

def make_vars_json(guest, network_device, instsource, console, distro):

    vars_json = {

        "DISTRI"	: "sle",
        "CASEDIR"	: "/space/SVN/os-autoinst-distri-opensuse/",

        "BACKEND"	: "s390x",
        "ZVM_HOST"	: "zvm54",

        # debug_vnc:
        #   "no": nope
        #   "setup vnc": initialize vnc. #cp disconnect at the end
        #   "try vncviewer": don't connect and initialize.  Just do the
        #      vnc connect and go from there.
        "DEBUG_VNC"     : "no",

        "ZVM_GUEST"     : "linux{guest}".format(guest=guest),
        "ZVM_PASSWORD"	: "lin390",

        "NETWORK"       : network_device,

        "PARMFILE" : {
            "Nameserver" : "10.160.0.1",
            "Domain"	 : "suse.de",
            # *ALLWAYS* enable ssh in our tests
            "ssh"        : "1",
        }
    }

    network_vars = get_network_parms(guest, network_device)

    unify(vars_json, network_vars)

    unify(vars_json, {
        "FTPBOOT" : {
            "HOST"     : "DIST\\.SUSE\\.DE",
            "DISTRO"   : distro
        },
    })

    unify(vars_json, {
        "INSTSRC": {
            "PROTOCOL": instsource.upper(),
            # dist.suse.de
            "HOST":     "10.160.0.100",
            "DIR_ON_SERVER": "{prefix}/install/SLP/{distro}/s390x/DVD1".format(
                distro=distro,
                prefix= "/dist" if instsource == "nfs" else ""
            ),
            "FTP_USER": "anonymous"
        },
    } )
    unify(vars_json, console_vars[console])

    unify(vars_json, instsrc_vars[instsource])

    return vars_json


import json
from pprint import pprint as pp
import sys
if __name__ == "__main__":
    _script, host, network, instsrc, console, distro = sys.argv

    print(json.dumps( make_vars_json( host, network, instsrc, console, distro), indent=True ))

    #pp( make_vars_json("155", "hsi-l3", "http", "vnc", "SLES-11-SP4-Alpha2"))
    #pp( make_vars_json("156", "ctc", "ftp", "X11"))
    #pp( make_vars_json("157", "vswitch-l3", "http", "vnc"))
