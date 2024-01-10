terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.2.0"
}

variable "region" {
  type = string
  description = "The AWS region to deploy resources into. Pre-requisites must exist in same region"
}

variable "vpc_cidr" {
  type = string
  description = "A CIDR address range to use for the VPC, must not conflict with existing VPC ranges"
}

variable "ec2_key_name" {
  type = string
  description = "The name of the key pair to associate with the EC2 instance"
}

variable "rstudio_workbench_ami" {
  type = string
  description = "The AMI id for the custom image built by Packer"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=e4768508a17f79337f9f1e48ebf47ee885b98c1f"

  name = "rstudio-workbench-multi"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(cidrsubnets(var.vpc_cidr, 6, 6, 6, 6, 6, 6),0,3)
  public_subnets  = slice(cidrsubnets(var.vpc_cidr, 6, 6, 6, 6, 6, 6),3,6)

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group" "intra_sg" {
  name        = "intra-sg"
  description = "Self referencing security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Allow access on any protocol form sources associated with same security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress"
  }
}

# SHARED STORAGE 
resource "aws_efs_file_system" "rstudio-workbench-efs" {
  creation_token = "rstudio-workbench-efs"
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "rstudio-workbench-efs"
  }
}

resource "aws_efs_mount_target" "rstudio-workbench-efs-mount-1" {
  file_system_id = aws_efs_file_system.rstudio-workbench-efs.id
  subnet_id      = element(module.vpc.private_subnets, 0)
  security_groups = [aws_security_group.intra_sg.id]
}

resource "aws_efs_mount_target" "rstudio-workbench-efs-mount-2" {
  file_system_id = aws_efs_file_system.rstudio-workbench-efs.id
  subnet_id      = element(module.vpc.private_subnets, 1)
  security_groups = [aws_security_group.intra_sg.id]
}

resource "aws_efs_mount_target" "rstudio-workbench-efs-mount-3" {
  file_system_id = aws_efs_file_system.rstudio-workbench-efs.id
  subnet_id      = element(module.vpc.private_subnets, 2)
  security_groups = [aws_security_group.intra_sg.id]
}

resource "aws_iam_role" "rstudio_server_role" {
  name = "rstudio-workbench-server-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  ]
  inline_policy {
    name = "allow-rds-iam-auth"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["rds-db:connect"]
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_iam_instance_profile" "rstudio_server_profile" {
  name = "rstudio-workbench-server-profile"
  role = aws_iam_role.rstudio_server_role.name
}

resource "aws_instance" "rstudio_workbench_server" {
  count = 2
  ami                  = var.rstudio_workbench_ami
  instance_type        = "t3.medium"
  vpc_security_group_ids = [aws_security_group.intra_sg.id]
  subnet_id            = element(module.vpc.private_subnets, count.index)
  iam_instance_profile = aws_iam_instance_profile.rstudio_server_profile.name
  key_name             = var.ec2_key_name
  metadata_options {
    http_tokens = "required"
  }
  ebs_optimized = true

  root_block_device {
    encrypted = true
  }

  // mount the EFS shared storage and add to /etc/fstab
  user_data = <<EOF
#!/bin/bash
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.rstudio-workbench-efs.dns_name}:/ /efs/workbench/home
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.rstudio-workbench-efs.dns_name}:/ /efs/workbench/shared-storage
echo ${aws_efs_file_system.rstudio-workbench-efs.dns_name}:/ /efs/workbench/home nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0 | tee -a /etc/fstab
echo ${aws_efs_file_system.rstudio-workbench-efs.dns_name}:/ /efs/workbench/shared-storage nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0 | tee -a /etc/fstab
EOF

  tags = {
    Name = "rstudio-workbench-server-${count.index + 1}"
    Role = "rstudio-workbench-server"
  }
}


# POSTGRES DATABASE 
## postgres db required for multi server deployment 
resource "aws_db_subnet_group" "rstudio-workbench-db-subnet-group" {
  name = "rstudio-workbench-db-subnet-group"
  subnet_ids = [for subnet in module.vpc.private_subnets: subnet]

  tags = {
    Name = "rstudio-workbench-db-subnet-group"
  }
}

resource "aws_rds_cluster" "rstudio-workbench-db-cluster" {
  apply_immediately = true

  cluster_identifier = "rstudio-workbench-db-cluster"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "15.4"
  master_username    = "postgres"
  manage_master_user_password = true
  vpc_security_group_ids = [aws_security_group.intra_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rstudio-workbench-db-subnet-group.id
  skip_final_snapshot = true
  
  iam_database_authentication_enabled = true

  serverlessv2_scaling_configuration {
    max_capacity = 1.0
    min_capacity = 0.5
  }
}

resource "aws_rds_cluster_instance" "rstudio-workbench-db-instance" {
  cluster_identifier = aws_rds_cluster.rstudio-workbench-db-cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.rstudio-workbench-db-cluster.engine
  engine_version     = aws_rds_cluster.rstudio-workbench-db-cluster.engine_version
  auto_minor_version_upgrade = true

  db_subnet_group_name = aws_db_subnet_group.rstudio-workbench-db-subnet-group.id
}




