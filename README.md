# Implementation of In-Network Adaptive Inference 

This is the implementation of "In-Network Adaptive Inference using Early-Exits" based on P4 BMv2 software switch. 

## Dependencies

To run the code, basic dependencies such as p4c, Bmv2 and Mininet should be installed. We strongly recommend you to place those dependencies identically on the home directory. I post links for detailed information below.

p4c: https://github.com/p4lang/p4c

Bmv2: https://github.com/p4lang/behavioral-model

Mininet: https://github.com/mininet/mininet

## Instructions

This repository is to show the feasibility of our idea which is to conduct early-exiting on the middle of in-network inference. There are two modes - static exiting and adaptive exiting. Static exiting mode is to exit every packets on the designated exit point. On the other hand, adaptive exiting obtains the confidence score of current packet and decides whether to exit by comparing with the threshold.

Network topology:

![image](https://github.com/keemeew/Early-Exit-P4/assets/69777212/047e8c60-6513-4a85-bd37-06affa07a38e)

These are instructions you can follow to run.

### Preliminaries

1. Clone the repository to the local 
```
git clone <project link>
```

2. Compile .p4 files
```
p4c --target bmv2 --arch v1model --std p4-16 ~/Early-Exit-P4/p4src/ee_adaptive.p4 -o ~/Early-Exit-P4/p4src
p4c --target bmv2 --arch v1model --std p4-16 ~/Early-Exit-P4/p4src/ee_static.p4 -o ~/Early-Exit-P4/p4src
```

3. Set up virtual network interfaces
```
sudo bash veth.sh
```

### Static
