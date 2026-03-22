# Valores concretos del proyecto
# Cambia alert_email por tu correo real para recibir las alertas

project_name  = "devops-seguridad"
environment   = "produccion"
region        = "us-east-1"

# EC2
instance_type = "t3.micro"        # Free Tier
key_pair_name = "devops-key"      # lo crearemos en el siguiente paso

# Auto Scaling
asg_min_size         = 1
asg_max_size         = 3
asg_desired_capacity = 1

# Alertas — CAMBIA ESTO por tu email real
alert_email = "jriosawsfree@gmail.com"
