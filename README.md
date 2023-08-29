# Implementation of In-Network Adaptive Inference using Early-Exits

This is the implementation of "In-Network Adaptive Inference using Early-Exits" based on P4 BMv2 software switch. 

## Dependencies

To run the code, basic dependencies such as p4c, Bmv2 and Mininet should be installed. We strongly recommend you to place those dependencies identically on the home directory. I post links for detailed information below.

p4c: https://github.com/p4lang/p4c

Bmv2: https://github.com/p4lang/behavioral-model

Mininet: https://github.com/mininet/mininet

## Instructions

This repository is to show the feasibility of our idea which is to conduct early-exiting on the middle of in-network inference. There are two modes - static exiting and adaptive exiting. Static exiting mode is to exit every packets on the designated exit point. On the other hand, adaptive exiting obtains the confidence score of current packet and decides whether to exit by comparing with the threshold.

These are instructions you can follow to run.

1. Clone the repository to local 
```
git clone https://github.com/keemeew/Approximated-Fair-Queuing
```

2. Compile approx_fair_queuing.p4 (Optional)
```
p4c --target bmv2 --arch v1model approx_fair_queuing.p4
```

3. Set up virtual nic interfaces
```
sudo bash veth_setup.sh
```

4. Run Bmv2 switch 
```
sudo simple_switch -i 0@veth0 -i 1@veth2 -i 2@veth4 --log-console --thrift-port 9090 approx_fair_queuing.json
```
* 'veth0-2' is used for input port, and 'veth4' is output port.

5. Insert switch rule
```
sudo simple_switch_CLI --thrift-port 9090 < rule.txt
```

6. Send long flow and burst flow simultaneously
``` 
sudo python3 send.py --dst "10.10.0.1"
sudo python3 send.py --dst "10.10.0.2"
```
I recommend you to use terminal applications (e.g., terminator) which supports command broadcasting to run two different send.py commands simultaneously. Timing to send long flow and burst flow is carefully adjusted in python script. By the way, please sniff 'veth4 using packet sniffing applications such as wireshark by yourself.
