# ─────────────────────────────────────────────────────────────────────────────
# KMS — cifrado de datos en reposo
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_kms_key" "main" {
  description             = "Clave KMS para cifrado de datos del proyecto"
  deletion_window_in_days = 7
  enable_key_rotation     = true   # rotacion anual automatica

  tags = {
    Name        = "${var.project_name}-kms"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.main.key_id
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 — almacenamiento seguro con políticas de acceso restringido
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "app" {
  bucket        = "${var.project_name}-app-data-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-app-data"
    Environment = var.environment
  }
}

# Bloquear todo acceso público
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cifrado con KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# Versionamiento habilitado
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Object Lock — protege contra eliminación accidental o maliciosa
resource "aws_s3_bucket_object_lock_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.app]
}

# ─────────────────────────────────────────────────────────────────────────────
# SECRETS MANAGER — almacena credenciales de forma segura
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}/db-password"
  description             = "Contrasena de base de datos del proyecto"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.project_name}-db-secret"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "admin"
    password = "CambiarEstoEnProduccion123!"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS CONFIG — verifica cumplimiento de políticas de seguridad
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-config-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-config"
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
      }
    ]
  })
}

resource "aws_iam_role" "config" {
  name = "${var.project_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-config-channel"
  s3_bucket_name = aws_s3_bucket.config.bucket

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# Regla Config — instancias EC2 deben tener cifrado en disco
resource "aws_config_config_rule" "ec2_encrypted" {
  name = "${var.project_name}-ec2-encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Regla Config — S3 no debe ser público
resource "aws_config_config_rule" "s3_no_public" {
  name = "${var.project_name}-s3-no-public-access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}
