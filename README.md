# Kubernetes control-plane HA on AWS

Terraform creates three control-plane EC2 instances in one subnet and three workers across three Availability Zones. Keepalived uses unicast VRRP to elect an active control-plane node. On election, an EC2 API call moves the secondary private API address to that node. The endpoint is a private IP; access it from inside the VPC or through a VPN/tunnel. This setup tolerates a control-plane instance failure, but **not** failure of the control-plane Availability Zone.

If you already deployed an earlier version, review the Terraform plan before applying: moving control-plane instances to one subnet replaces instances, and the API endpoint changes. Existing kubeadm clusters need a deliberate migration or rebuild; applying Terraform alone will not update their certificates or cluster configuration.

## Prerequisites

- Terraform >= 1.10, AWS credentials, and an existing EC2 key pair
- An S3 bucket for state (create it before initializing Terraform)
- An Ubuntu 24.04 AMI matching `ami_id` and the selected AWS region

Replace the placeholder bucket in `backend.tf`, or supply the bucket on the command line. The S3 backend uses native S3 state locking (`use_lockfile = true`); grant the Terraform role access to the state object and its `.tflock` object. Enable bucket versioning.

```sh
terraform init -backend-config='bucket=my-terraform-state-bucket'
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

The default `ssh_allowed_cidr_blocks` and `api_allowed_cidr_blocks` are open for a lab. Restrict them in `terraform.tfvars` before exposing these instances.

## Monthly cost estimate

The default `instance_type` in `variables.tf` is `t3.medium` for all three control-plane and three worker nodes. For the default Singapore region (`ap-southeast-1`), the estimate below assumes Linux On-Demand pricing, six instances running 730 hours per month, and one public IPv4 address per instance. Prices are in USD and were checked in October 2026.

| Item | Calculation | Estimated monthly cost |
| --- | ---: | ---: |
| Six `t3.medium` instances | 6 × 730 hours × $0.0528/hour | $231.26 |
| Six public IPv4 addresses | 6 × 730 hours × $0.005/hour | $21.90 |
| Example EBS storage | 6 × 20 GB gp3 × $0.096/GB-month | $11.52 |
| **Illustrative total** | | **$264.68/month** |

The EBS line assumes a **20 GB gp3 root volume per node** for illustration. Terraform does not set root volume size or type, so the actual EBS charge depends on the selected AMI and any attached volumes. The estimate excludes data transfer (including traffic between AZs), S3 state storage and requests, snapshots, taxes, and possible T3 Unlimited surplus CPU credits. Check current rates before deployment: [EC2 On-Demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/), [Singapore `t3.medium` rate](https://aws-pricing.com/t3.medium.html), [public IPv4 pricing](https://aws.amazon.com/vpc/pricing/), and [EBS pricing](https://aws.amazon.com/ebs/pricing/) ([Singapore gp3 rate](https://tools.getfinops.cloud/gp2-to-gp3-savings-calculator/)).

## Initialize the cluster

Wait for cloud-init to finish on the nodes (`cloud-init status --wait`). SSH to the first control-plane IP from `terraform output control_plane_public_ips`. Check `systemctl status keepalived` and that the active node owns the private API address shown by `terraform output api_server_endpoint`. Keepalived can elect a node before the Kubernetes API exists; there is no need to wait for API health before `kubeadm init`.

On the first control-plane node:

```sh
sudo kubeadm init \
  --control-plane-endpoint '<api_server_endpoint>' \
  --upload-certs \
  --pod-network-cidr=192.168.0.0/16
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

Install the Cilium CLI, verify its archive checksum, and use the same pod CIDR as `kubeadm`. Cilium's default `10.0.0.0/8` pod pool overlaps this VPC's `10.0.0.0/16` range.

```sh
CILIUM_CLI_VERSION=$(curl -fsSL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz"{,.sha256sum}
sha256sum --check "cilium-linux-${CLI_ARCH}.tar.gz.sha256sum"
sudo tar -C /usr/local/bin -xzf "cilium-linux-${CLI_ARCH}.tar.gz"
rm "cilium-linux-${CLI_ARCH}.tar.gz"{,.sha256sum}
cilium install --helm-set ipam.operator.clusterPoolIPv4PodCIDRList=192.168.0.0/16
cilium status --wait
```

Run the `kubeadm join ... --control-plane --certificate-key ...` command from `kubeadm init` on the two other control-plane nodes, then the worker join command on all three workers. Verify with `kubectl get nodes` and `cilium connectivity test`.

## Check failover

On each control-plane instance, inspect `systemctl status keepalived` and `journalctl -u keepalived`. On the current master, `ip -4 addr` should show the API VIP; the EC2 console should show the same address as a secondary private IP on that instance's primary network interface. Stop Keepalived on the master to test election:

```sh
sudo systemctl stop keepalived
```

Wait for another control-plane node to claim the secondary IP, then check `kubectl get nodes` through the VIP. Restart Keepalived on the first node after the test. Failover requires the control-plane instance profile permission to call `ec2:AssignPrivateIpAddresses` in the control-plane subnet.

## Cleanup

```sh
terraform destroy
```
