# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "promenade/ubuntu1604"
  config.vm.box_check_update = false

  config.vm.provision :shell, privileged: true, inline:<<EOS
set -ex

echo === Setting up NTP so simulate MaaS environment ===
apt-get update -qq
apt-get install -y -qq --no-install-recommends chrony
EOS

  config.vm.synced_folder ".", "/vagrant", :nfs => true

  config.vm.provider "libvirt" do |lv|
    lv.cpus = 2
    lv.memory = "2048"
    lv.nested = true
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

  config.vm.define "n3" do |c|
      c.vm.hostname = "n3"
      c.vm.network "private_network", ip: "192.168.77.13"
  end

end
