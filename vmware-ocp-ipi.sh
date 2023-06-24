#!/bin/sh -xe

export IP=$(hostname -I|cut -d. -f3)

export OCP_VERSION=4.13.3
curl -L -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux-${OCP_VERSION}.tar.gz | sudo tar zxvf - -C /usr/local/bin/ oc
curl -L -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz | sudo tar zxvf - -C /usr/local/bin/ openshift-install

mkdir -p ~/ocpinstall/cluster/
cd ~/ocpinstall/cluster/

echo -e 'y\n' | ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
read -p "pull screet: "  PULLSECRET
read -p "vCenter host: "  VCENTERHOST
read -p "vCenter username: "  VCENTERUSER
read -p "vCenter password: "  VCENTERPASSWORD
read -p "API VIP: "  APIVIP
read -p "Ingress VIP: "  INGRESSVIP

cat >install-config.yaml <<EOF
apiVersion: v1
baseDomain: dynamic.opentlc.com
compute:
- hyperthreading: Enabled
  architecture: amd64
  name: 'worker'
  replicas: 3
  platform:
    vsphere:
      cpus: 4
      coresPerSocket: 2
      memoryMB:  16384
      osDisk:
        diskSizeGB: 120
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 3
  platform:
    vsphere:
      cpus:  4
      coresPerSocket: 2
      memoryMB:  16384
      osDisk:
        diskSizeGB: 120
metadata:
  name: ${GUID}
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 192.168.${IP}.0/24
  serviceNetwork:
  - 172.30.0.0/16
platform:
  vsphere:
    datacenter: SDDC-Datacenter
    defaultDatastore: /SDDC-Datacenter/datastore/WorkloadDatastore
    cluster: /SDDC-Datacenter/host/Cluster-1
    apiVIPs:
    - ${APIVIP}
    ingressVIPs:
    - ${INGRESSVIP}
    diskType: thin
    folder: /SDDC-Datacenter/vm/Workloads/sandbox-${GUID}
    network: segment-sandbox-${GUID}
    password: ${VCENTERPASSWORD}
    username: ${VCENTERUSER}
    vCenter: ${VCENTERHOST}
publish: External
pullSecret: '${PULLSECRET}'
sshKey: '$(cat ~/.ssh/id_rsa.pub)'
EOF

cp install-config.yaml ../

openshift-install create cluster --dir ~/ocpinstall/cluster/

export KUBECONFIG=~/ocpinstall/cluster/auth/kubeconfig
openshift-install wait-for install-complete --dir ~/ocpinstall/cluster/ --log-level debug
