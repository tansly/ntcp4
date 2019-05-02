#!/bin/bash

# The topology:
#                                      +------------------------+
#                                      |                        |
#                                      |      Namespace ns2     |
#                                      |                        |
#                                      |      +-----------+     |
#                                      | veth7|           |     |
#                                      |    +-+  Monitor  |     |
#                                      |    | |           |     |
#                                      |    | +-----^-----+     |
#                                      |    |       +veth5      |
#                                      |    |       |           |
#                                      +------------------------+
#                                           |       |
#                                 Management|       |Monitor
#                                 interface |       |interface
#   +-------------------------+        +--------------------------+       +-------------------------------+
#   |                         |        |    |       |             |       |                               |
#   |                         |        |    +veth6  +veth4        |       |                               |
#   |                         |        |   +------------------+   |       |         +-----------+         |
#   |       +--------+        |        |   |                  |   |       |         |           |         |
#   |       |        +veth1   |        |   |                  |   |       |         |  "Router" |         |    Internet
#   |       |  Host  +---------------------+    Middlebox     +---------------------+           +-------------------+
#   |       |        |        |        |   veth0          veth2   |       |   veth3 |           |         |
#   |       +--------+        |        |   |                  +   |       |         +-----------+         |
#   |                         |        |   +------------------+   |       |                               |
#   |                         |        |                          |       |                               |
#   |     Namesepace ns0      |        |      Namespace ns1       |       |         Init namespace        |
#   |                         |        |                          |       |                               |
#   +-------------------------+        +--------------------------+       +-------------------------------+
#
# The middlebox is a device that is deployed in front of a router.
# In this particular topology, there is only one host, but one can generalize
# this by adding more interfaces to it and implementing L2 switching in the P4 program.

# XXX: Don't ask me why I disable segmentation offloading (ethtool commands).
# When I do not, I got a lot of TCP/UDP packets with bogus checksums that are dropped
# by the network stack, thus not reaching the application running at the host.
# I think that the kernel does not compute checksums for packets going through
# veth interfaces (which makes sense as it is a waste of time) when offloading
# is enabled. When offloading is disabled, the checksums are computed, though.
#
# The thing is, when there is no P4 middlebox, packets without proper checksums
# do not cause any problems, but when I place the middlebox in the middle, those packets
# get dropped somewhere in the kernel. I don't exactly understand what happens
# but I think when the middlebox forwards the packets artificially (by using raw
# sockets, probably) they interact with the kernel in a way I don't expect and get dropped.
#
# I'll try checking the kernel source to see what is put in place of the checksums
# and how they are checked (when offloading is enabled) to understand where/why
# they are dropped exactly.

# Client device
NS=ns0
IPADDR=192.168.6.10/24
VETH=veth1 # The other end of veth1 (that is, veth0) is the P4 middlebox.
ip netns add $NS
ip link set $VETH netns $NS
ip netns exec $NS ip link set lo up
ip netns exec $NS ip addr add $IPADDR dev $VETH
ip netns exec $NS ip link set $VETH up
ip netns exec $NS ip r add default via 192.168.6.1
ip netns exec $NS ethtool --offload $VETH rx off tx off gso off

# P4 "middlebox"
# It takes packets from veth0 (or veth2) and forwards it to veth2 (or veth0),
# while also cloning the packet to veth4 (which is connected to the monitor device).
# Note that cloning in P4 is managed by "clone sessions".
# One must use the `mirroring_add` command appropriately to make the device actually clone
# the packets to the correct interface. See the P4 program for details.
NS=ns1
ip netns add $NS
# Forwarding/cloning interfaces
ip link set veth0 netns $NS
ip link set veth2 netns $NS
ip link set veth4 netns $NS
ip netns exec $NS ip link set lo up
ip netns exec $NS ip link set veth0 up
ip netns exec $NS ip link set veth2 up
ip netns exec $NS ip link set veth4 up
# Management interface, for remote management from the monitor device
ip link set veth6 netns $NS
ip netns exec $NS ip addr add 192.168.6.99/24 dev veth6
ip netns exec $NS ip link set veth6 up

# Monitor device
# The other end of veth5 (that is, veth4) is the middlebox.
NS=ns2
VETH=veth5
ip netns add $NS
ip link set $VETH netns $NS
ip netns exec $NS ip link set lo up
ip netns exec $NS ip link set $VETH up
ip netns exec $NS ethtool --offload $VETH rx off tx off gso off
# Set up the management interface
IPADDR_MGMT=192.168.6.66/24
VETH_MGMT=veth7
ip link set $VETH_MGMT netns $NS
ip netns exec $NS ip addr add $IPADDR_MGMT dev $VETH_MGMT
ip netns exec $NS ip link set $VETH_MGMT up

# Router
ip addr add 192.168.6.1/24 dev veth3
ip l set veth3 up
ethtool --offload veth3 rx off tx off gso off
echo 1 > /proc/sys/net/ipv4/conf/veth3/forwarding
echo 1 > /proc/sys/net/ipv4/conf/enp0s3/forwarding
# Instead of proxy ARP, may consider masquerading
echo 1 > /proc/sys/net/ipv4/conf/enp0s3/proxy_arp

# XXX: There are some connectivity problems probably related to the path MTU/fragmentation.
