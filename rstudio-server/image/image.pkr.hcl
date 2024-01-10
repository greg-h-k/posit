packer {
  required_plugins {
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }


source "amazon-ebs" "rstudio-server-ami-build" {
  ami_name      = "rstudio-server-${local.timestamp}"
  instance_type = var.build_instance_type
  region        = var.region
  source_ami_filter {
    filters = {
      name                = var.source_ami_filter_name
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
  ssh_interface = "session_manager"
  communicator = "ssh"

  iam_instance_profile = var.ami_build_instance_profile_name

}

# a build block invokes sources and runs provisioning steps on them.
build {
  sources = ["source.amazon-ebs.rstudio-server-ami-build"]
  
  provisioner "ansible" {
    playbook_file = "./automation/playbook.yaml"
    // added scp-extra-args due to issue copying files as mentioned here
    // https://github.com/hashicorp/packer-plugin-ansible/issues/110
    extra_arguments = [ 
        "--scp-extra-args", "'-O'",
        // "-vvvv",
        "--extra-vars", "rstudio_server_deb_url=${var.rstudio_server_deb_url} shiny_server_deb_url=${var.shiny_server_deb_url}"
    ] 
  }
}