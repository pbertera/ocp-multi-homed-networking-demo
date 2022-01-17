#!/bin/bash

# path to the demo.sh file (https://github.com/pbertera/demo.sh)
. ../demo.sh/demo.sh

GOBIN=~/go/bin/
NS=testns
# cleanup
rm -rf conf.d
sudo ip netns list | grep $NS >/dev/null && sudo ip netns delete $NS
rm -rf plugins

SPEED=100

pi '# install cnitool'
pe 'go get github.com/containernetworking/cni'
pe 'go install github.com/containernetworking/cni/cnitool@latest'

pi '# install CNI plugins'
pe 'git clone https://github.com/containernetworking/plugins.git'
pe 'cd plugins'
pe './build_linux.sh'
pe 'cd ..'
pe 'ls -l plugins/bin/'

pe mkdir conf.d
pe echo "'"'{"cniVersion":"0.4.0","name":"point-to-point","type":"ptp","ipMasq":true,"ipam":{"type":"host-local","subnet":"172.16.29.0/24","routes":[{"dst":"0.0.0.0/0"}]}}'"'" \> conf.d/10-ptp.conf

pi "# create the $NS network namespace"
pe "sudo ip netns add $NS"
pe "sudo NETCONFPATH=${PWD}/conf.d CNI_PATH=./plugins/bin ${GOBIN}/cnitool add point-to-point /var/run/netns/$NS"

pi "# test the netns connectivity"
pe "sudo ip netns exec $NS ip addr"
pe "ip -4 addr| grep -A2 'link-netns $NS'"

pe "sudo ip netns exec $NS ping -c 3 172.16.29.1"
pe "sudo ip netns exec $NS ping -c 3 8.8.8.8"

pi "# remove the connection"
pe "sudo NETCONFPATH=${PWD}/conf.d CNI_PATH=./plugins/bin ${GOBIN}/cnitool del point-to-point /var/run/netns/$NS"
pe "sudo ip netns exec $NS ip addr"
pe "sudo ip netns del $NS"
