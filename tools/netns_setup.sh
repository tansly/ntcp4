#!/bin/bash

# Client device
# The other end of veth1 (that is, veth0) is the P4 middlebox.
NS=ns0
IPADDR=192.168.6.10/24
VETH=veth1
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
ip link set veth0 netns $NS
ip link set veth2 netns $NS
ip link set veth4 netns $NS
ip netns exec $NS ip link set lo up
ip netns exec $NS ip link set veth0 up
ip netns exec $NS ip link set veth2 up
ip netns exec $NS ip link set veth4 up

# Monitor device
# The other end of veth5 (that is, veth4) is the middlebox.
NS=ns2
IPADDR=192.168.6.66/24
VETH=veth5
ip netns add $NS
ip link set $VETH netns $NS
ip netns exec $NS ip link set lo up
ip netns exec $NS ip addr add $IPADDR dev $VETH
ip netns exec $NS ip link set $VETH up
ip netns exec $NS ethtool --offload $VETH rx off tx off gso off

# Router
ip addr add 192.168.6.1/24 dev veth3
ip l set veth3 up
echo 1 > /proc/sys/net/ipv4/conf/veth3/forwarding
echo 1 > /proc/sys/net/ipv4/conf/enp0s3/forwarding
# Instead of proxy ARP, may consider masquerading
echo 1 > /proc/sys/net/ipv4/conf/enp0s3/proxy_arp
