# ocp-vmware-ipi-odf

OpenShift VMWare install IPI to VMC with ODF Storage Infra Nodes.

This required your NSX-T segment to be configured with a public OpenShift API VIP and Ingress VIP. See here for how its done via ansible in agnosticd.

- https://github.com/redhat-cop/agnosticd/blob/development/ansible/roles-infra/infra-vmc-resources/tasks/create_segment.yaml
- https://github.com/redhat-cop/agnosticd/blob/development/ansible/roles-infra/infra-vmc-resources/tasks/create_additional_public_ips.yaml
- https://github.com/redhat-cop/agnosticd/blob/development/ansible/roles-infra/infra-vmc-resources/tasks/create_public_ip_and_nat.yaml


## (1) Install OpenShift Cluster

From bastion

```bash
./vmware-ocp-ipi.sh
```

You will need to provide:

- OCP pull screet
- vCenter host
- vCenter username
- vCenter password
- OCP API VIP
- OCP Ingress VIP

Wait for install to complete.

Join cluster to ACM. Label with cluster with `odf=true`.

## (2) Create Infrastructure Nodes

From bastion

```bash
./create-infra.sh
```

Wait for infra nodes to become ready.

## (3) Deploy ODF to Cluster using ACM Policy

Deploy ODF Policy to ACM with ArgoCD deployed.

```bash
git clone https://github.com/eformat/odf-policy.git
```

Adjust to suit.

Create Local Storage, ODF and Storage Cluster.

```bash
oc apply -f applicationset/odf-appset.yaml
```

Once storage system deployed, make cepfs the default StorageClass

```bash
oc annotate sc/ocs-storagecluster-cephfs storageclass.kubernetes.io/is-default-class=true
oc annotate sc/thin-csi storageclass.kubernetes.io/is-default-class-
```