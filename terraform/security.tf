# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS
# ─────────────────────────────────────────────────────────────────────────────

# SG para el ALB - solo acepta HTTP desde internet
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "Permite trafico HTTP entrante al Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP desde internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS desde internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Trafico saliente hacia instancias EC2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg-alb"
    Environment = var.environment
  }
}

# SG para EC2 - solo acepta trafico desde el ALB
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-sg-ec2"
  description = "Permite trafico solo desde el ALB y SSH interno"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP solo desde el ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH solo desde la subred privada"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Trafico saliente - actualizaciones via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg-ec2"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# NETWORK ACLs — capa adicional de seguridad a nivel de subred
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private.id]

  # Permitir tráfico HTTP entrante desde subredes públicas
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 80
    to_port    = 80
  }

  # Permitir SSH desde dentro de la VPC
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }

  # Permitir respuestas de tráfico saliente (puertos efímeros)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Bloquear todo lo demás entrante
  ingress {
    rule_no    = 200
    protocol   = "-1"
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Permitir todo el tráfico saliente
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-nacl-private"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — Principio de menor privilegio para EC2
# ─────────────────────────────────────────────────────────────────────────────

# Rol para las instancias EC2
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# Política mínima — solo acceso a SSM (sin necesidad de SSH)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Política para escribir logs en CloudWatch
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS WAF — protección contra ataques web
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Regla 1 — protección contra amenazas comunes (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Regla 2 — bloqueo de bots conocidos
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Regla 3 — rate limiting (máx 1000 req por IP cada 5 minutos)
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-waf"
    Environment = var.environment
  }
}

# Asociar WAF al ALB
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# AWS SHIELD — protección contra DDoS (Standard es gratuito)
# ─────────────────────────────────────────────────────────────────────────────

# NOTA: Shield Advanced requiere suscripcion de pago ($3000/mes).
# Shield Standard esta activo automaticamente en toda cuenta AWS sin costo
# y protege contra ataques DDoS comunes sin necesidad de configuracion.
# No se requiere recurso Terraform para Shield Standard.

# resource "aws_shield_protection" "alb" {
#   name         = "${var.project_name}-shield-alb"
#   resource_arn = aws_lb.main.arn
# }
