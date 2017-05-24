# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/xenial64"
  config.vm.box_check_update = false

  config.vm.provision :file, source: "vagrant-assets/docker-daemon.json", destination: "/tmp/docker-daemon.json"
  config.vm.provision :file, source: "vagrant-assets/dnsmasq-kubernetes", destination: "/tmp/dnsmasq-kubernetes"

  config.vm.provision :shell, privileged: true, inline:<<EOS
set -ex

echo === Installing packages ===
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  docker.io \
  dnsmasq \
  gettext-base \

echo === Setting up DNSMasq ===
mv /tmp/dnsmasq-kubernetes /etc/dnsmasq.d/
chown root:root /etc/dnsmasq.d/dnsmasq-kubernetes
chmod 444 /etc/dnsmasq.d/dnsmasq-kubernetes
systemctl restart dnsmasq

echo === Reconfiguring Docker ===
mv /tmp/docker-daemon.json /etc/docker/daemon.json
chown root:root /etc/docker/daemon.json
chmod 444 /etc/docker/daemon.json
systemctl restart docker

echo === Done ===
EOS

  config.hostmanager.enabled = true
  config.hostmanager.manage_guest = true

  config.vm.provider "virtualbox" do |vb|
    vb.cpus = 2
    vb.memory = "2048"
  end

  config.vm.define "n0" do |c|
      c.vm.hostname = "n0"
      c.vm.network "private_network", ip: "192.168.77.10"
  end

  config.vm.define "n1" do |c|
      c.vm.hostname = "n1"
      c.vm.network "private_network", ip: "192.168.77.11"
  end

  config.vm.define "n2" do |c|
      c.vm.hostname = "n2"
      c.vm.network "private_network", ip: "192.168.77.12"
  end

end
