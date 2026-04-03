host_arch = ENV.fetch("VM_HOST_ARCH", `uname -m`.strip)

arch_defaults = case host_arch
when "arm64", "aarch64"
  {
    box: ENV.fetch("VAGRANT_BOX", "bytesguy/ubuntu-server-22.04-arm64"),
    provider: ENV.fetch("VAGRANT_DEFAULT_PROVIDER", "vmware_desktop")
  }
else
  {
    box: ENV.fetch("VAGRANT_BOX", "ubuntu/jammy64"),
    provider: ENV.fetch("VAGRANT_DEFAULT_PROVIDER", "virtualbox")
  }
end

vm_name = ENV.fetch("VAGRANT_VM_NAME", "petclinic-prod")
vm_hostname = ENV.fetch("VAGRANT_VM_HOSTNAME", "petclinic-prod")
vm_memory = Integer(ENV.fetch("VAGRANT_VM_MEMORY", "2048"))
vm_cpus = Integer(ENV.fetch("VAGRANT_VM_CPUS", "2"))
vm_private_ip = ENV.fetch("VAGRANT_VM_IP", "192.168.56.20")
host_ssh_port = Integer(ENV.fetch("VAGRANT_HOST_SSH_PORT", "2222"))
host_app_port = Integer(ENV.fetch("VAGRANT_HOST_APP_PORT", "8080"))

Vagrant.configure("2") do |config|
  config.vm.box = arch_defaults[:box]
  config.vm.hostname = vm_hostname
  config.vm.boot_timeout = 600

  config.vm.provider arch_defaults[:provider] do |provider|
    provider.vmx["memsize"] = vm_memory.to_s if provider.respond_to?(:vmx)
    provider.vmx["numvcpus"] = vm_cpus.to_s if provider.respond_to?(:vmx)
    provider.memory = vm_memory if provider.respond_to?(:memory=)
    provider.cpus = vm_cpus if provider.respond_to?(:cpus=)
  end

  config.vm.provider "virtualbox" do |vb|
    vb.name = vm_name
    vb.memory = vm_memory
    vb.cpus = vm_cpus
  end

  config.vm.provider "vmware_desktop" do |vmware|
    vmware.vmx["displayname"] = vm_name
    vmware.vmx["memsize"] = vm_memory.to_s
    vmware.vmx["numvcpus"] = vm_cpus.to_s
  end

  config.vm.network "private_network", ip: vm_private_ip
  config.vm.network "forwarded_port", guest: 22, host: host_ssh_port, id: "ssh", auto_correct: true
  config.vm.network "forwarded_port", guest: 8080, host: host_app_port, auto_correct: true

  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provision "shell",
    path: "vagrant/bootstrap.sh",
    privileged: true
end
