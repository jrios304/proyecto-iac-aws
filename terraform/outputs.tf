output "vpc_id" {
  description = "ID de la VPC creada"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "URL del Load Balancer para acceder a la aplicacion"
  value       = aws_lb.main.dns_name
}

output "ec2_instance_id" {
  description = "ID de la instancia EC2"
  value       = aws_instance.app.id
}

output "cloudtrail_bucket" {
  description = "Bucket S3 donde se almacenan los logs de CloudTrail"
  value       = aws_s3_bucket.cloudtrail.bucket
}

# output "guardduty_detector_id" {
#   description = "ID del detector de GuardDuty"
#   value       = aws_guardduty_detector.main.id
# }

output "kms_key_arn" {
  description = "ARN de la clave KMS para cifrado"
  value       = aws_kms_key.main.arn
}

output "sns_topic_arn" {
  description = "ARN del topic SNS para alertas"
  value       = aws_sns_topic.alerts.arn
}

output "waf_acl_arn" {
  description = "ARN del Web ACL de WAF"
  value       = aws_wafv2_web_acl.main.arn
}
