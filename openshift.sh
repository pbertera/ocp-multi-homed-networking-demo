#!/bin/bash

# path to the demo.sh file (https://github.com/pbertera/demo.sh)
. ../demo.sh/demo.sh

clear
SPEED=5
VM_MASTER_DEVICE=eth1
OCP_MASTER_DEVICE=enp7s0
PROJECT=multi-network

ps1_user=pietro
ps1_bg_color=${c['bg_CYAN']}
ps1_color=${c['ORANGE']}

ps1() {
    echo -ne "${ps1_bg_color}${ps1_color}${ps1_user}@${ps1_hostname}${c['reset']}${c['CYAN']} ${c['BLUE']}$(basename $(pwd)) \$${c['reset']} "
}   

function sshCommand {
	local host="$1"
	shift
	p $@
	ssh -x $host $@
}

function makeVlan {
  master=$OCP_MASTER_DEVICE
  id=$1
  state=$2 # 'up' or 'absent'
  p "# Set the VLAN $id with NodeNetworkConfigurationPolicy"
  p 'cat << EOF | oc apply -f -'
  cat << END
apiVersion: nmstate.io/v1beta1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: vlan-$id
spec:
  desiredState:
    interfaces:
    - name: ${master}.${id}
      description: VLAN $id using $master
      type: vlan
      state: $state
      vlan:
        base-iface: $master
        id: $id
  nodeSelector:
    vlan${id}: "yes"
EOF
END

  cat << EOF | oc apply -f -
apiVersion: nmstate.io/v1beta1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: vlan-${id}
spec:
  desiredState:
    interfaces:
    - name: ${master}.${id}
      description: VLAN $id using $master
      type: vlan
      state: $state
      vlan:
        base-iface: $master
        id: $id
  nodeSelector:
    vlan${id}: "yes"
EOF
}

function makeAdditionalNet {
  p '# Create the spec.additionalNetorks list on networks.operator.openshift.io/cluster'
  p 'cat << EOF | oc patch -p "$(cat)" --type json networks.operator.openshift.io cluster'
  cat << END
[                                                                                         
  {'op': 'add', 'path': '/spec/additionalNetworks', value: []}                            
]
EOF
END

  cat << EOF | oc patch -p "$(cat)" --type json networks.operator.openshift.io cluster
[               
  {'op': 'add', 'path': '/spec/additionalNetworks', value: []}
]
EOF
}

function makeMultusVlan {
  id=$1
  master=${OCP_MASTER_DEVICE}.${id}
  
  p "# Create the spec.additionalNetorks object vor vlan $id on networks.operator.openshift.io/cluster"
  p 'cat << EOF | oc patch -p "$(cat)" --type json networks.operator.openshift.io cluster'
  cat << END
[
  {
    'op': 'add',
    'path': '/spec/additionalNetworks/-',
    'value': {
      'name': 'vlan-$id',
      'namespace': 'default',
      'type': 'Raw',
      'rawCNIConfig': '{ "cniVersion": "0.3.1", "name": "vlan-${id}", "type": "macvlan", "mode": "bridge", "master": "$master", "ipam": { "type": "whereabouts", "range": "192.168.${id}.0/24", "exclude": [ "192.168.${id}.1/32" ]}}'
    }
  }
]
EOF
END

  cat << EOF | oc patch -p "$(cat)" --type json networks.operator.openshift.io cluster
[
  {
    'op': 'add',
    'path': '/spec/additionalNetworks/-',
    'value': {
      'name': 'vlan-$id',
      'namespace': 'default',
      'type': 'Raw',
      'rawCNIConfig': '{ "cniVersion": "0.3.1", "name": "vlan-${id}", "type": "macvlan", "mode": "bridge", "master": "$master", "ipam": { "type": "whereabouts", "range": "192.168.${id}.0/24", "exclude": [ "192.168.${id}.1/32" ]}}'
    }
  }
]
EOF
}

function createPod {
  id=$1
  p "# Create a dummy pod attached to the network vlan-${id}"
  p 'cat << EOF | oc create -f -'
  cat << END
apiVersion: v1                   
kind: Pod   
metadata:   
  namespace: $PROJECT
  annotations:                   
    k8s.v1.cni.cncf.io/networks: default/vlan-${id}          
  name: pod-vlan${id}            
spec:       
  nodeSelector:                  
    vlan${id}: "yes"             
  containers:                    
  - name: main                   
    image: quay.io/pbertera/net-tools                        
    command:
    - /bin/bash                  
    - -c    
    - sleep infinity
EOF
END

  cat << EOF | oc create -f -
apiVersion: v1
kind: Pod
metadata:
  namespace: $PROJECT
  annotations:
    k8s.v1.cni.cncf.io/networks: default/vlan-${id}
  name: pod-vlan${id}
spec:
  nodeSelector:
    vlan${id}: "yes"
  containers:
  - name: main
    image: quay.io/pbertera/net-tools
    command:
    - /bin/bash
    - -c
    - sleep infinity
EOF
}

function run_demo {
  ps1_hostname=localhost

  p ssh vm

  ps1_hostname=vm

  sshCommand vm sudo ip link add link $VM_MASTER_DEVICE name ${VM_MASTER_DEVICE}.10 type vlan id 10
  sshCommand vm sudo ip link add link $VM_MASTER_DEVICE name ${VM_MASTER_DEVICE}.20 type vlan id 20
  sshCommand vm sudo ip link add link $VM_MASTER_DEVICE name ${VM_MASTER_DEVICE}.30 type vlan id 30
  sshCommand vm sudo ip link set up dev ${VM_MASTER_DEVICE}.10
  sshCommand vm sudo ip link set up dev ${VM_MASTER_DEVICE}.20
  sshCommand vm sudo ip link set up dev ${VM_MASTER_DEVICE}.30
  sshCommand vm sudo ip addr add 192.168.10.1/24 dev ${VM_MASTER_DEVICE}.10
  sshCommand vm sudo ip addr add 192.168.20.1/24 dev ${VM_MASTER_DEVICE}.20
  sshCommand vm sudo ip addr add 192.168.30.1/24 dev ${VM_MASTER_DEVICE}.30
  sshCommand vm sudo ip addr

  p ssh bastion

  ps1_hostname=bastion
  ps1_bg_color=${c['bg_BLUE']}
  ps1_color=${c['RED']}

  pe oc login -u pbertera https://wallace:6443

  makeVlan 10 up
  makeVlan 20 up
  makeVlan 30 up

  loop "pe oc get nncp; oc get nnce"

  #while [ "$key" != 'c' ]; do
  #  pe oc get nncp
  #  pe oc get nnce
  #  read -n 1 -rep $'Press 'c' to continue with the demo: \n' key
  #done

  makeAdditionalNet

  makeMultusVlan 10
  makeMultusVlan 20
  makeMultusVlan 30

  pe oc get network-attachment-definition -n default -o yaml

  pe oc new-project ${PROJECT}

  createPod 10
  createPod 20
  createPod 30

  loop pe oc get pods
  #while [ "$key" != 'c' ]; do
  #  pe oc get pods
  #  read -n 1 -rep $'Press "c" to continue with the demo: \n' key
  #done

  pe oc exec pod-vlan10 -- ip addr
  pe oc exec pod-vlan20 -- ip addr
  pe oc exec pod-vlan30 -- ip addr

  pe oc exec pod-vlan10 -- ping -c 3 192.168.10.1
  pe oc exec pod-vlan20 -- ping -c 3 192.168.20.1
  pe oc exec pod-vlan30 -- ping -c 3 192.168.30.1
}

function reset_demo {
  ps1_hostname=localhost

  p ssh vm
  ps1_hostname=vm

  sshCommand vm sudo ip link delete ${VM_MASTER_DEVICE}.10
  sshCommand vm sudo ip link delete ${VM_MASTER_DEVICE}.20
  sshCommand vm sudo ip link delete ${VM_MASTER_DEVICE}.30

  p ssh bastion

  ps1_hostname=bastion
  ps1_bg_color=${c['bg_BLUE']}
  ps1_color=${c['RED']}

  pe oc login -u pbertera https://wallace:6443

  p '# Delete the spec.additionalNetorks list on networks.operator.openshift.io/cluster'
  p 'cat << EOF | oc patch -p "$(cat)" --type json networks.operator.openshift.io cluster'
  cat << END
[
  {'op': 'remove', 'path': '/spec/additionalNetworks'}
]
EOF
END

  cat << EOF | oc patch -p "$(cat)" --type json networks.operator.openshift.io cluster
[
  {'op': 'remove', 'path': '/spec/additionalNetworks'}
]
EOF
  
  makeVlan 10 absent
  makeVlan 20 absent
  makeVlan 30 absent

  loop "pe oc get nncp; oc get nnce"

  pe oc delete nncp vlan-10
  pe oc delete nncp vlan-20
  pe oc delete nncp vlan-30
  pe oc delete project ${PROJECT}
}

if [ "$1" == "reset" ]; then
  reset_demo
else
  run_demo
fi
