#!/bin/bash

# Client device
NS=ns0
IPADDR=192.168.6.10/24
VETH=veth1
ip netns add $NS
ip link set $VETH netns $NS
ip netns exec $NS ip link set lo up
ip netns exec $NS ip addr add $IPADDR dev $VETH
ip netns exec $NS ip link set $VETH up
ip netns exec $NS ip r add default via 192.168.6.1

# Monitor device
NS=ns2
IPADDR=192.168.6.66/24
VETH=veth5
ip netns add $NS
ip link set $VETH netns $NS
ip netns exec $NS ip link set lo up
ip netns exec $NS ip addr add $IPADDR dev $VETH
ip netns exec $NS ip link set $VETH up

# Router
ip addr add 192.168.6.1/24 dev veth3
ip l set veth3 up
echo 1 > /proc/sys/net/ipv4/conf/veth3/forwarding
echo 1 > /proc/sys/net/ipv4/conf/enp0s3/forwarding
echo 1 > /proc/sys/net/ipv4/conf/enp0s3/proxy_arp
