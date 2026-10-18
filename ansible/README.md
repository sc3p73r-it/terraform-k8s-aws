# Ansible package installation

`install_k8s.sh` embeds and runs this same idempotent node-preparation playbook during EC2 first boot. For an existing host, copy the playbook from the script into `ansible/site.yml` and run:

```sh
ansible-playbook -i '<host>,' -u ubuntu --private-key ./key.pem ansible/site.yml
```

The playbook installs containerd, disables swap, enables forwarding, and installs/holds `kubeadm`, `kubelet`, and `kubectl`.
