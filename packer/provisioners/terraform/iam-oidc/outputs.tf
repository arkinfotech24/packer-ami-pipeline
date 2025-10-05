#########################################
# Outputs for chained Terraform modules
#########################################

output "role_arn" {
  description = "IAM role ARN assumed by GitHub Actions"
  value       = aws_iam_role.gha_packer_role.arn
}

output "s3_bucket" {
  description = "S3 bucket used to store Packer manifests"
  value       = aws_s3_bucket.manifests.bucket
}

output "dynamodb_table" {
  description = "DynamoDB table for AMI inventory tracking"
  value       = aws_dynamodb_table.ami_inventory.name
}

