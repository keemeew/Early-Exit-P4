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
import time

global cnt, true_positive, true_negative, false_positive, false_negative
cnt = 0
true_positive = 0
true_negative = 0
false_positive = 0
false_negative = 0

class Soren(Packet):
    name = "Soren"
    fields_desc = [
        BitField('value', 0, 126),
        BitField('padding', 0, 2),
        BitField('enter_time', 0, 48),
        BitField('exit_time', 0, 48),
    ]

def handle_pkt(pkt):
    # pkt.show()
    global cnt, true_positive, true_negative, false_positive, false_negative
    malicious_flag = 0
    if 'IP' in pkt:
        cnt += 1
        print(pkt[IP].tos)
        if 'TCP' in pkt:
            if pkt[TCP].flags == 2:
                print('malicious')
                malicious_flag = 1
        if pkt[IP].tos == 1:
            if malicious_flag == 1:
                true_positive += 1
            elif malicious_flag == 0:
                false_positive += 1
        else:
            if malicious_flag == 1:
                false_negative += 1
            elif malicious_flag == 0:
                true_negative += 1
        print("true_positive: {}, true_negative : {},  false_positive : {}, false_negative : {}".format(true_positive, true_negative, false_positive, false_negative))
        # print(pkt[Soren].exit_time-pkt[Soren].enter_time)

def main():

    bind_layers(Ether, Soren)
    bind_layers(Soren, IP)
    bind_layers(IP, UDP)
    # bind_layers(IP, TCP)

    ifaces = filter(lambda i: 'eth' in i, os.listdir('/sys/class/net/'))
    iface = 'eth0'
    print("sniffing on %s" % iface)
    sys.stdout.flush()
    sniff(iface = iface, prn = lambda x: handle_pkt(x))

if __name__ == '__main__':
    main()
