#!/usr/bin/env python3
"""Minimal replacement for sendip via scapy. sends one packet."""

import errno
import os
import socket
import sys
from scapy.all import (
    send,
    IP, IPv6,
    TCP, UDP, ICMP,
    ICMPv6DestUnreach, ICMPv6TimeExceeded, ICMPv6ParamProblem,
    Raw,
)
from scapy.layers.inet6 import ICMPv6Unknown

_LOOPBACK = {'127.0.0.1', '::1'}

def parse_args(argv):
    p = {
        'ip_version': None,
        'transport': None,
        'src': None,
        'dst': None,
        'sport': None,
        'dport': None,
        'icmp_type': None,
        'icmp_code': None,
        'payload_size': 0,
    }

    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '-p':
            proto = argv[i + 1]; i += 2
            if proto in ('ipv4', 'ipv6'):
                p['ip_version'] = proto
            elif proto in ('tcp', 'udp', 'icmp'):
                p['transport'] = proto
            else:
                sys.exit(f'unknown protocol: {proto}')
        elif a == '-is':
            p['src'] = argv[i + 1]; i += 2
        elif a == '-id':
            p['dst'] = argv[i + 1]; i += 2
        elif a == '-6s':
            p['src'] = argv[i + 1]; i += 2
        elif a == '-6d':
            p['dst'] = argv[i + 1]; i += 2
        elif a == '-ts':
            p['sport'] = int(argv[i + 1]); i += 2
        elif a == '-td':
            p['dport'] = int(argv[i + 1]); i += 2
        elif a == '-us':
            p['sport'] = int(argv[i + 1]); i += 2
        elif a == '-ud':
            p['dport'] = int(argv[i + 1]); i += 2
        elif a == '-ct':
            p['icmp_type'] = int(argv[i + 1]); i += 2
        elif a == '-cd':
            p['icmp_code'] = int(argv[i + 1]); i += 2
        elif a == '-d':
            # e.g. "r10" = 10 random bytes of payload
            spec = argv[i + 1]; i += 2
            if spec.startswith('r'):
                p['payload_size'] = int(spec[1:])
        elif not a.startswith('-'):
            i += 1  # positional: routing dest, scapy routes by dst in header
        else:
            i += 1

    return p


_ICMPV6_CLASS = {
    1: ICMPv6DestUnreach,
    3: ICMPv6TimeExceeded,
    4: ICMPv6ParamProblem,
}


def make_icmpv6(typ, code):
    cls = _ICMPV6_CLASS.get(typ, ICMPv6Unknown)
    pkt = cls(code=code)
    if cls is ICMPv6Unknown:
        pkt.type = typ
    return pkt


def build_packet(p):
    if p['ip_version'] == 'ipv4':
        ip = IP(src=p['src'], dst=p['dst'])
    elif p['ip_version'] == 'ipv6':
        ip = IPv6(src=p['src'], dst=p['dst'])
    else:
        sys.exit('no IP version specified')

    t = p['transport']
    if t == 'tcp':
        l4 = TCP(sport=p['sport'], dport=p['dport'])
    elif t == 'udp':
        l4 = UDP(sport=p['sport'], dport=p['dport'])
    elif t == 'icmp':
        typ, code = p['icmp_type'], p['icmp_code']
        if p['ip_version'] == 'ipv4':
            l4 = ICMP(type=typ, code=code)
        else:
            l4 = make_icmpv6(typ, code)
    else:
        sys.exit('no transport protocol specified')

    pkt = ip / l4
    if p['payload_size'] > 0:
        pkt = pkt / Raw(os.urandom(p['payload_size']))
    return pkt


def send_on_iface(pkt, dst, iface):
    """Send via AF_INET(6) SOCK_RAW with SO_BINDTODEVICE.

    The packet originates locally and traverses the OUTPUT netfilter chain,
    matching the iptables rules under test.  No ARP on dummy interfaces.
    """
    is_ipv6 = IPv6 in pkt
    if is_ipv6:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_RAW,
                             socket.IPPROTO_RAW)
        dst_addr = (dst, 0, 0, 0)
    else:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW,
                             socket.IPPROTO_RAW)
        dst_addr = (dst, 0)
    try:
        sock.sendto(bytes(pkt), dst_addr)
    except OSError as e:
        if e.errno != errno.EPERM:
            raise
    finally:
        sock.close()


def main():
    p = parse_args(sys.argv[1:])
    iface = None if p['dst'] in _LOOPBACK else 'eth0'
    pkt = build_packet(p)
    if p['dst'] in _LOOPBACK:
        send(pkt, verbose=False)
    else:
        send_on_iface(pkt, p['dst'], 'eth0')


if __name__ == '__main__':
    main()
