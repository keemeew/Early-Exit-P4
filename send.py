from scapy.utils import rdpcap
from scapy.all import sendp
from time import sleep
import sys

pkts = rdpcap("dataset.pcap")

print("Sending packets...")
for idx, pkt in enumerate(pkts):
    sendp(pkt, iface='eth0', verbose=False)
    if (idx+1) % 20 == 0:
        print("{}%".format((idx+1)/20))
    sleep(0.1)
print("Done.")