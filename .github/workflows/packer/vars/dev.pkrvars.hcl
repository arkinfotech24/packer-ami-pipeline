region              = "us-east-1"
env                 = "dev"
distro              = "al2023" # default; workflow can override
subnet_id           = "subnet-0ac19a8ca72369eef"
security_group_id   = "sg-0edaa040cab1999cd"
iam_instance_profile = ""   # optional: e.g., "PackerBuilderInstanceProfile"
root_volume_size    = 16
cwagent             = true

tags = {
  "Owner" = "Allen"
  "CostCenter" = "DevOps"
}

