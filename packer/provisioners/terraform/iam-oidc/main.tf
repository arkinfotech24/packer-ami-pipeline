#########################################
# Terraform: GitHub OIDC + S3 + DynamoDB + Packer Build Permissions
#########################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

#########################################
# Provider and Variables
#########################################

provider "aws" {
  region = var.region
}

#########################################
# GitHub OIDC Identity Provider
#########################################

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

#########################################
# S3 bucket for Packer manifests
#########################################

resource "aws_s3_bucket" "manifests" {
  bucket        = lower("ami-manifests-${replace(coalesce(var.repo, "arkinfotech24/packer-ami-pipeline"), "/", "-")}-${var.region}")
  force_destroy = true

  tags = {
    Project     = "packer-ami-pipeline"
    Environment = "infra"
  }
}

#########################################
# DynamoDB for AMI inventory tracking
#########################################

resource "aws_dynamodb_table" "ami_inventory" {
  name         = "ami-inventory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "AmiId"

  attribute {
    name = "AmiId"
    type = "S"
  }

  tags = {
    Project = "packer-ami-pipeline"
  }
}

#########################################
# IAM Role for GitHub Actions (OIDC)
#########################################

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repo}:*"]
    }
  }
}

resource "aws_iam_role" "gha_packer_role" {
  name               = "gha-packer-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

#########################################
# IAM Policy for Packer Build Permissions (EC2 + IAM + S3 + DynamoDB)
#########################################

data "aws_iam_policy_document" "gha_policy" {
  statement {
    sid = "PackerEC2Permissions"
    actions = [
      "ec2:Describe*",
      "ec2:GetPasswordData",
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:CreateTags",
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:TerminateInstances",
      "ec2:CreateImage",
      "ec2:RegisterImage",
      "ec2:DeregisterImage",
      "ec2:ModifyImageAttribute",
      "ec2:CopyImage",
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:DeleteVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:DescribeSnapshots",
      "ec2:DescribeImages",
      "iam:PassRole"
    ]
    resources = ["*"]
  }

  statement {
    sid = "S3Permissions"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObjectAcl"
    ]
    resources = [
      aws_s3_bucket.manifests.arn,
      "${aws_s3_bucket.manifests.arn}/*"
    ]
  }

  statement {
    sid = "DynamoDBPermissions"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DescribeTable"
    ]
    resources = [aws_dynamodb_table.ami_inventory.arn]
  }

  statement {
    sid = "CloudWatchLogsPermissions"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gha_packer_policy" {
  name   = "gha-packer-policy"
  policy = data.aws_iam_policy_document.gha_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.gha_packer_role.name
  policy_arn = aws_iam_policy.gha_packer_policy.arn
}

#########################################
# Outputs
#########################################

#output "role_arn" {
#  value       = aws_iam_role.gha_packer_role.arn
#  description = "IAM Role ARN for GitHub Actions"
#}

#output "s3_bucket" {
#  value       = aws_s3_bucket.manifests.bucket
#  description = "S3 bucket for storing Packer manifests"
#}

#output "dynamodb_table" {
#  value       = aws_dynamodb_table.ami_inventory.name
#  description = "DynamoDB table for AMI inventory tracking"
#}

