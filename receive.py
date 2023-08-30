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

class Inference(Packet):
    name = "Inference"
    fields_desc = [
        BitField('value', 0, 126),
        BitField('padding', 0, 2),
        BitField('enter_time', 0, 48),
        BitField('exit_time', 0, 48),
    ]

def handle_pkt(pkt):
    global cnt, true_positive, true_negative, false_positive, false_negative
    malicious_flag = 0
    if 'IP' in pkt:
        cnt += 1
        if 'TCP' in pkt:
            if pkt[TCP].flags == 2:
                malicious_flag = 1
        if pkt[IP].tos == 1:
            if malicious_flag == 1:
                true_positive += 1
                print("Accurate!")
            elif malicious_flag == 0:
                false_positive += 1
                print("Inaccurate!")
        else:
            if malicious_flag == 1:
                false_negative += 1
                print("Inaccurate!")
            elif malicious_flag == 0:
                true_negative += 1
                print("Accurate!")
        total1 = true_positive + false_negative
        total2 = true_positive + false_positive
        if (total1 != 0 and total2 != 0):
            recall = float(true_positive) / float(total1)
            precision = float(true_positive) / float(total2)
            f1score = 2.0 / float(1 / precision + 1 / recall)
            accuracy = (true_positive+true_negative)/(true_positive+true_negative+false_positive+false_negative)
            print("Recall rate : {}, Precision : {}, Accuracy : {}, F1score : {}".format(recall, precision, accuracy, f1score))

def main():

    bind_layers(Ether, Inference)
    bind_layers(Inference, IP)
    bind_layers(IP, UDP)

    ifaces = filter(lambda i: 'eth' in i, os.listdir('/sys/class/net/'))
    iface = 'eth0'
    print("sniffing on %s" % iface)
    sys.stdout.flush()
    sniff(iface = iface, prn = lambda x: handle_pkt(x))

if __name__ == '__main__':
    main()
