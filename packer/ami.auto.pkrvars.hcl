region            = "us-east-1"
env               = "development"
version           = "v1.0.0"
subnet_id         = "subnet-0ac19a8ca72369eef"
security_group_id = "sg-0edaa040cab1999cd"
iam_instance_profile = "packer-admin-profile"

tags = {
  Owner = "Allen"
  Purpose = "Automated AMI Build"
}

