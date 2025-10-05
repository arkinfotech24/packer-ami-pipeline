terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" { type = string }
variable "repo" { type = string } # e.g., "arkinfotech24/packer-ami-pipeline"

# GitHub OIDC provider
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# S3 for manifests
resource "aws_s3_bucket" "manifests" {
  bucket        = "ami-manifests-${replace(var.repo, "/", "-")}-${var.region}"
  force_destroy = true
}

# DynamoDB table for AMI inventory
resource "aws_dynamodb_table" "ami_inventory" {
  name         = "ami-inventory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "AmiId"

  attribute {
    name = "AmiId"
    type = "S"
  }
}

# IAM role assumed by GitHub Actions via OIDC
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

# Policy permissions
data "aws_iam_policy_document" "policy" {
  statement {
    sid = "EC2"
    actions = [
      "ec2:DescribeImages",
      "ec2:CreateImage",
      "ec2:RegisterImage",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:Describe*",
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:DeleteVolume",
      "iam:PassRole"
    ]
    resources = ["*"]
  }

  statement {
    sid = "S3"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:ListBucket",
      "s3:GetObject"
    ]
    resources = [
      aws_s3_bucket.manifests.arn,
      "${aws_s3_bucket.manifests.arn}/*"
    ]
  }

  statement {
    sid       = "DDB"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.ami_inventory.arn]
  }
}

resource "aws_iam_policy" "gha_packer_policy" {
  name   = "gha-packer-policy"
  policy = data.aws_iam_policy_document.policy.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.gha_packer_role.name
  policy_arn = aws_iam_policy.gha_packer_policy.arn
}

output "role_arn" {
  value = aws_iam_role.gha_packer_role.arn
}

output "s3_bucket" {
  value = aws_s3_bucket.manifests.bucket
}

output "dynamodb_table" {
  value = aws_dynamodb_table.ami_inventory.name
}

