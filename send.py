from scapy.utils import rdpcap
from scapy.all import sendp
from time import sleep
import sys

pkts = rdpcap("dataset.pcap")

cnt = 0
for idx, pkt in enumerate(pkts):
    print(cnt)
    sendp(pkt, iface='eth0', verbose=False)
    cnt += 1
    sleep(0.1)