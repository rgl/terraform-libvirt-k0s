# About

[![Lint](https://github.com/rgl/terraform-libvirt-debian-example/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/terraform-libvirt-debian-example/actions/workflows/lint.yml)

An example [k0s Kubernetes](https://github.com/k0sproject/k0s) cluster in libvirt QEMU/KVM Debian Virtual Machines using terraform.

# Usage (Ubuntu 22.04 host)

Create and install the [base Debian 12 vagrant box](https://github.com/rgl/debian-vagrant).

Install Terraform:

```bash
wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
unzip terraform_1.5.7_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Create the infrastructure:

```bash
rm -f ~/.ssh/known_hosts*
terraform init
TF_LOG=TRACE TF_LOG_PATH=terraform-plan.log terraform plan -out=tfplan
TF_LOG=TRACE TF_LOG_PATH=terraform-apply.log time terraform apply tfplan
```

**NB** if you have errors alike `Could not open '/var/lib/libvirt/images/k0s_c0_root.img': Permission denied'` you need to reconfigure libvirt by setting `security_driver = "none"` in `/etc/libvirt/qemu.conf` and restart libvirt with `sudo systemctl restart libvirtd`.

Show information about the libvirt/qemu guest:

```bash
virsh dumpxml k0s_c0
virsh qemu-agent-command k0s_c0 '{"execute":"guest-info"}' --pretty
virsh qemu-agent-command k0s_c0 '{"execute":"guest-network-get-interfaces"}' --pretty
./qemu-agent-guest-exec k0s_c0 id
./qemu-agent-guest-exec k0s_c0 uname -a
ssh-keygen -f ~/.ssh/known_hosts -R "$(terraform output --raw ip)"
ssh "vagrant@$(terraform output --raw ip)"
```

Show information about kubernetes:

```bash
terraform output --raw kubeconfig >kubeconfig.yml
export KUBECONFIG="$PWD/kubeconfig.yml"
kubectl version --output yaml
kubectl cluster-info
kubectl get nodes -o wide
kubectl api-versions
kubectl api-resources -o wide
kubectl get namespaces
kubectl get all --all-namespaces -o wide
kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp
kubectl get charts --all-namespaces # aka charts.helm.k0sproject.io
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```
