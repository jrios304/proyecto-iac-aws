# ─────────────────────────────────────────────────────────────────────────────
# S3 BUCKET PARA CLOUDTRAIL — almacena los logs de auditoría
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-cloudtrail-logs"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Política del bucket — permite a CloudTrail escribir logs
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# AWS CLOUDTRAIL — auditoría de todas las acciones en la cuenta
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true    # registra IAM, STS, etc.
  is_multi_region_trail         = true    # cubre todas las regiones
  enable_log_file_validation    = true    # detecta si los logs fueron alterados
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = {
    Name        = "${var.project_name}-cloudtrail"
    Environment = var.environment
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}"
  retention_in_days = 90
}

resource "aws_iam_role" "cloudtrail" {
  name = "${var.project_name}-cloudtrail-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail" {
  name = "${var.project_name}-cloudtrail-policy"
  role = aws_iam_role.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# SNS — notificaciones por email cuando se disparan alarmas
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH ALARMS — detecta anomalías y notifica
# ─────────────────────────────────────────────────────────────────────────────

# Alarma 1 — CPU alta en EC2
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-alta"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU supera el 80% - posible ataque o sobrecarga"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# Alarma 2 — muchas respuestas 4xx del ALB (posible escaneo)
resource "aws_cloudwatch_metric_alarm" "alb_4xx" {
  alarm_name          = "${var.project_name}-alb-4xx-alto"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "Mas de 50 errores 4xx en 1 minuto - posible ataque"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# Alarma 3 — intentos de login fallidos (simulación incidente)
resource "aws_cloudwatch_metric_alarm" "failed_logins" {
  alarm_name          = "${var.project_name}-logins-fallidos"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedLoginAttempts"
  namespace           = "${var.project_name}/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Mas de 5 intentos de login fallidos - posible fuerza bruta"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# Alarma 4 — cambios en Security Groups (actividad sospechosa)
resource "aws_cloudwatch_metric_alarm" "sg_changes" {
  alarm_name          = "${var.project_name}-cambios-sg"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SecurityGroupChanges"
  namespace           = "CloudTrailMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Se detectaron cambios en Security Groups"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH LOG METRIC FILTERS — detecta eventos de seguridad en CloudTrail
# ─────────────────────────────────────────────────────────────────────────────

# Filtro para cambios en Security Groups
resource "aws_cloudwatch_log_metric_filter" "sg_changes" {
  name           = "${var.project_name}-sg-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupIngress) }"

  metric_transformation {
    name      = "SecurityGroupChanges"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

# Filtro para accesos no autorizados
resource "aws_cloudwatch_log_metric_filter" "unauthorized_access" {
  name           = "${var.project_name}-unauthorized"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedAccess*\") || ($.errorCode = \"AccessDenied\") }"

  metric_transformation {
    name      = "UnauthorizedAccessAttempts"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS GUARDDUTY — detección inteligente de amenazas
# ─────────────────────────────────────────────────────────────────────────────

# NOTA: GuardDuty requiere activacion manual en cuentas nuevas.
# Activar desde consola: Security -> GuardDuty -> Enable GuardDuty
# Luego descomentar y ejecutar terraform apply.

# resource "aws_guardduty_detector" "main" {
#   enable = true
#   datasources {
#     s3_logs { enable = true }
#   }
#   tags = {
#     Name        = "${var.project_name}-guardduty"
#     Environment = var.environment
#   }
# }
