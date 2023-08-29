#!/usr/bin/env python

# NOTE: THIS SCRIPT IS STILL IN PYTHON 2

import sys
import struct
import os

from scapy.all import sniff, sendp, hexdump, get_if_list, get_if_hwaddr, bind_layers
from scapy.all import Packet, IPOption, Ether
from scapy.all import ShortField, IntField, LongField, BitField, FieldListField, FieldLenField
from scapy.all import Packet
from scapy.all import IP, UDP, Raw, TCP
from scapy.layers.inet import _IPOption_HDR
from scapy.fields import *

global cnt, acc
cnt = 0
acc = 0

class Soren(Packet):
    name = "Soren"
    fields_desc = [
        BitField('value', 0, 126),
        BitField('padding', 0, 2),
    ]

def handle_pkt(pkt):
    pkt.show()
    # global cnt, acc
    # malicious_flag = 0
    # if 'IP' in pkt:
    #     cnt += 1
    #     print(pkt[IP].tos)
    #     if 'TCP' in pkt:
    #         if pkt[TCP].flags == 2:
    #             print('malicious')
    #             malicious_flag = 1
    #     if pkt[IP].tos == malicious_flag:
    #         acc += 1
    #     print("Current Accuracy:",acc/cnt)


        
    # print(pkt[Soren].value)
    # global count
    # if 'IP' in pkt:
    #     if pkt['IP'].src == "10.0.1.1":
    #         count += 1
    #         return ("#{} {} ==> {}: ".format(count, pkt['IP'].src, pkt['IP'].dst))

    # sys.stdout.flush()

def main():

    bind_layers(Ether, Soren)
    bind_layers(Soren, IP)
    bind_layers(IP, UDP)
    # bind_layers(IP, TCP)

    ifaces = filter(lambda i: 'eth' in i, os.listdir('/sys/class/net/'))
    iface = 'switch3-eth3'
    print("sniffing on %s" % iface)
    sys.stdout.flush()
    sniff(iface = iface, prn = lambda x: handle_pkt(x))

if __name__ == '__main__':
    main()
