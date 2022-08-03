terraform {
    required_providers {
        proxmox = {
            source = "telmate/proxmox"
            version = "2.7.1"
        }
    }
}

variable "ram"{}
variable "storage_size"{}
variable "ip"{
	type=string
	default = "dhcp"
}
variable "gateway_ip"{
	type=string
	default = ""
}
variable "ip_mask"{
	type=string
	default = ""
}
variable "cores"{}
variable "vm_count"{}
variable "vm_name"{}
variable "os_template"{}
variable "os_type"{}
variable "password"{}
variable "filesystem_for_disk"{
	type=string
	default = "local-lvm"
}
#variable "ANSIBLE"{ type=map}#environment variable
#variable "TERRAFORM_USER"{ type=map}#environment variable
variable "proxmox_host"{ type=map}
variable "unprivileged"{}

variable "vm_connection_details"{
    type = map
}

variable "create_user"{ 
    type = map
}

provider "proxmox" {
    pm_password = var.proxmox_host["pm_password"]
    pm_api_url = var.proxmox_host["pm_api_url"]
    pm_user = var.proxmox_host["pm_user"]
    pm_tls_insecure = "true"
}

resource "proxmox_lxc" "server"  {
    count             = 1 #var.vm_count
    cores             = var.cores
    memory            = var.ram
    target_node       = var.proxmox_host.target_node
    hostname     = var.vm_name
    ostemplate   = var.os_template
    ostype       = var.os_type
    password     = var.password
    unprivileged = var.unprivileged
    start        = true
    onboot = true
    startup = "order=1,up=5" # order is priority, up is how long to wait before startingthe next container
    #TODO add startup order variable: startup = ....
    ssh_public_keys = <<-EOT
        ${var.vm_connection_details.pub}
    EOT


    // Terraform will crash without rootfs defined
    rootfs {
        storage = var.filesystem_for_disk
        size    = var.storage_size
    }

    #TODO change to take an input variable
    features {
        fuse    = false
        nesting = true
        mount   = "nfs;cifs"
    }

    network {
        name   = "eth0"
        bridge = "vmbr0"
        ip     = "${var.ip}${var.ip_mask}"
        gw     = "${var.gateway_ip}"
    }

    connection {
        host = var.ip        
        user = "${ var.vm_connection_details.user }"
        private_key = "${var.vm_connection_details.priv}"
        agent = false
        timeout = "5m"
    } 
}

module "create_ansible_user"{
    depends_on = [ proxmox_lxc.server]
    #count      = length( proxmox_lxc.server)
    source= "github.com/nickgreensgithub/tf_module_create_remote_user"

    connection = {
            ip = var.ip
            user= var.vm_connection_details.user
            private_key = var.vm_connection_details.priv
    }
    user = {
            name = "${ var.create_user.user }"
            is_sudo = true
            public_ssh="${ var.create_user.pub }"
    }
}



# resource "null_resource" "further_configuration" {
#     triggers = {
#         vm_ids = join(",", proxmox_lxc.server.*.id)
#     }

#     //remote exec required to delay running of local-exec provisioner below
#     provisioner "remote-exec" {
#         connection {
#             host = var.ip
#             user = "root"
#             private_key = file(var.TERRAFORM_USER.priv)
#         } 
#         inline = ["echo 'connected!'"]
#     }
#     #TODO use module created for this
#     //making an ansible user and setting its ssh key
#     provisioner "local-exec" {
#         command = "ansible-playbook -i ${var.ip}, /mnt/files/automation/ansible/playbooks/create_ansible_user/main.yml --private-key ${var.TERRAFORM_USER.priv} --user root"
#         //TODO can this be a relative path?
#     }    
# }

