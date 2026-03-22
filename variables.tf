variable "region" {
  description = "Region de AWS donde se desplegara la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto - prefijo en todos los recursos"
  type        = string
  default     = "devops-seguridad"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "produccion"
}

# ── Red ──────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR de la subred publica"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR de la subred privada"
  type        = string
  default     = "10.0.2.0/24"
}

variable "public_subnet_cidr_2" {
  description = "Segunda subred publica (requerida por ELB)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "availability_zone_1" {
  description = "Primera zona de disponibilidad"
  type        = string
  default     = "us-east-1a"
}

variable "availability_zone_2" {
  description = "Segunda zona de disponibilidad"
  type        = string
  default     = "us-east-1b"
}

# ── EC2 ──────────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "Tipo de instancia EC2 (t2.micro esta en Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI de Amazon Linux 2 en us-east-1"
  type        = string
  default     = "ami-0c421724a94bba6d6"   # Amazon Linux 2023 standard - us-east-1
}

variable "key_pair_name" {
  description = "Nombre del key pair para acceso SSH a EC2"
  type        = string
  default     = "devops-key"
}

# ── Auto Scaling ──────────────────────────────────────────────────────────────

variable "asg_min_size" {
  description = "Minimo de instancias en el Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximo de instancias en el Auto Scaling Group"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Capacidad deseada inicial"
  type        = number
  default     = 1
}

# ── Alertas ──────────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Email para recibir alertas de CloudWatch y SNS"
  type        = string
  default     = "jriosawsfree@gmail.com"   # cambia esto
}
