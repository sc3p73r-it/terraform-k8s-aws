#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ansible
install -d -m 0755 /opt/k8s-ansible/roles/kubernetes_node/tasks
cat >/opt/k8s-ansible/site.yml <<'YAML'
---
- hosts: localhost
  connection: local
  become: true
  roles: [kubernetes_node]
YAML
cat >/opt/k8s-ansible/roles/kubernetes_node/tasks/main.yml <<'YAML'
---
- name: Install prerequisites
  ansible.builtin.apt:
    name: [apt-transport-https, ca-certificates, curl, gpg, containerd]
    state: present
    update_cache: true
- name: Disable swap
  ansible.builtin.command: swapoff -a
  changed_when: false
- name: Disable swap in fstab
  ansible.builtin.replace:
    path: /etc/fstab
    regexp: '^([^#].*\sswap\s.*)$'
    replace: '# \1'
- name: Enable forwarding
  ansible.builtin.copy:
    dest: /etc/sysctl.d/99-kubernetes.conf
    mode: '0644'
    content: "net.ipv4.ip_forward = 1\n"
- name: Apply sysctl
  ansible.builtin.command: sysctl --system
  changed_when: false
- name: Configure containerd
  ansible.builtin.shell: |
    mkdir -p /etc/containerd
    containerd config default >/etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  args: {executable: /bin/bash}
- name: Restart containerd
  ansible.builtin.service: {name: containerd, state: restarted, enabled: true}
- name: Install Kubernetes repository key
  ansible.builtin.shell: |
    mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  args: {executable: /bin/bash, creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg}
- name: Add Kubernetes repository
  ansible.builtin.apt_repository:
    repo: 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /'
    filename: kubernetes
- name: Install Kubernetes packages
  ansible.builtin.apt:
    name: [kubelet, kubeadm, kubectl]
    state: present
    update_cache: true
- name: Hold Kubernetes packages
  ansible.builtin.dpkg_selections:
    name: '{{ item }}'
    selection: hold
  loop: [kubelet, kubeadm, kubectl]
YAML
ansible-playbook -i localhost, /opt/k8s-ansible/site.yml
touch /var/lib/k8s-bootstrap-complete
