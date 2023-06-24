#!/bin/sh -xe

cd ~/ocpinstall/cluster/

export KUBECONFIG=~/ocpinstall/cluster/auth/kubeconfig

curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | sudo tar -C /usr/local/bin -xvzf - govc

echo ">> Creating Infra MachineConfig Pool"

cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: infra
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,infra]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/infra: ""
EOF

read -p "Cluster API Name e.g. mx76p-lph2w: "  CLUSTER_API_NAME
read -p "netowrk Segment Name e.g. segment-sandbox-mx76p: "  NETWORK_NAME
read -p "vCenter host: "  VCENTER_SERVER
read -p "vCenter username: "  VCENTERUSER
read -p "vCenter password: "  VCENTERPASSWORD

ROLE=infra
MACHINE_SET_NAME=${CLUSTER_API_NAME}-${ROLE}-0
REPLICAS=3
BOOT_DISK_SIZE=120
RAM=24576
CPU=8
CORES=2
VM_TEMPLATE=${CLUSTER_API_NAME}-rhcos-generated-region-generated-zone
CLUSTER_NAME=Cluster-1
DATACENTER_NAME=SDDC-Datacenter
DATASTORE_NAME=/SDDC-Datacenter/datastore/WorkloadDatastore
VM_FOLDER=/SDDC-Datacenter/vm/Workloads/${NETWORK_NAME##segment-}
RESOURCE_POOL=/SDDC-Datacenter/host/${CLUSTER_NAME}/Resources

echo ">> Creating MachineSet"

oc apply -n openshift-machine-api -f- <<EOF
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
    creationTimestamp: null
    labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_API_NAME}
        machine.openshift.io/cluster-api-machine-role: ${ROLE}
        machine.openshift.io/cluster-api-machine-type: ${ROLE}        
    name: ${MACHINE_SET_NAME}
    namespace: openshift-machine-api
spec:
    replicas: ${REPLICAS}
    selector:
        matchLabels:
            machine.openshift.io/cluster-api-cluster: ${CLUSTER_API_NAME}
            machine.openshift.io/cluster-api-machineset: ${MACHINE_SET_NAME}
    template:
        metadata:
            creationTimestamp: null
            labels:
                machine.openshift.io/cluster-api-cluster: ${CLUSTER_API_NAME}
                machine.openshift.io/cluster-api-machine-role: ${ROLE}
                machine.openshift.io/cluster-api-machine-type: ${ROLE}
                machine.openshift.io/cluster-api-machineset: ${MACHINE_SET_NAME}
        spec:
            metadata:
                labels:
                    node-role.kubernetes.io/${ROLE}: ""
                    cluster.ocs.openshift.io/openshift-storage: ""
            providerSpec:
                value:
                    apiVersion: vsphereprovider.openshift.io/v1beta1
                    credentialsSecret:
                        name: vsphere-cloud-credentials
                    diskGiB: ${BOOT_DISK_SIZE}
                    kind: VSphereMachineProviderSpec
                    memoryMiB: ${RAM}
                    metadata:
                        creationTimestamp: null
                    network:
                        devices:
                        - networkName: "${NETWORK_NAME}"
                    numCPUs: ${CPU}
                    numCoresPerSocket: ${CORES}
                    snapshot: ""
                    template: ${VM_TEMPLATE}
                    userDataSecret:
                        name: worker-user-data
                    workspace:
                        datacenter: ${DATACENTER_NAME}
                        datastore: ${DATASTORE_NAME}
                        folder: ${VM_FOLDER}
                        resourcePool: ${RESOURCE_POOL}
                        server: ${VCENTER_SERVER}
EOF

echo ">> Waiting for infra nodes to be ready, this could take some time .."

oc wait --for=condition=Ready node -l node-role.kubernetes.io/infra='' --timeout=1200s

echo ">> Remove worker role label from infra nodes"

for node in $(oc get node -l node-role.kubernetes.io/infra='' -o name); do
  oc label $node node-role.kubernetes.io/worker-
done

## FIXME Govc to create separate disks
# https://access.redhat.com/solutions/6990931
# https://issues.redhat.com/browse/RFE-1426

echo ">> Adding extra disk to Storage nodes"

export DISK_SIZE=300GB
export GOVC_URL=${VCENTER_SERVER}
export GOVC_USERNAME=${VCENTERUSER}
export GOVC_PASSWORD=${VCENTERPASSWORD}
export GOVC_INSECURE=1

for node in $(oc get node -l node-role.kubernetes.io/infra='' -o name); do
  OBJECT_ID=$(govc device.info -vm ${node##node/} -json | jq '.Devices[] | select(.Backing.BackingObjectId != null) | .Backing.BackingObjectId')
  OBJECT_ID=$(echo $OBJECT_ID | tr -d '"')
  govc vm.disk.create -vm ${node##node/} -name ${OBJECT_ID}/data.vmdk -size ${DISK_SIZE}
done
