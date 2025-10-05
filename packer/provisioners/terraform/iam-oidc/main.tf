#########################################
# Terraform: GitHub OIDC + S3 + DynamoDB
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

variable "region" {
  description = "AWS region for the OIDC setup"
  type        = string
}

variable "repo" {
  description = "GitHub repo for OIDC trust (e.g., org/repo)"
  type        = string
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
  bucket        = lower("ami-manifests-${replace(var.repo, "/", "-")}-${var.region}")
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
# IAM Policy for EC2, S3, DynamoDB
#########################################

data "aws_iam_policy_document" "gha_policy" {
  statement {
    sid = "EC2Permissions"
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
    sid = "S3Permissions"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.manifests.arn,
      "${aws_s3_bucket.manifests.arn}/*"
    ]
  }

  statement {
    sid       = "DynamoDBPermissions"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.ami_inventory.arn]
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

