
locals {
  grafana_port = 3000
  domain_name  = "grafana.${var.dns_domain}"
  log_group    = "grafana-group"
}

resource "aws_ecs_cluster" "grafana" {
  name = "grafana"
}

resource "aws_ecs_service" "grafana" {
  name            = "grafana"
  cluster         = aws_ecs_cluster.grafana.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  
  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana" # Must match the JSON file
    container_port   = local.grafana_port
  }
  
  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [ aws_security_group.grafana.id ]
    assign_public_ip = true
  }

  # ECS won't use a target group unless it is associated with an ALB.
  # The listener rule makes this association.
  depends_on = [ aws_lb_listener_rule.grafana ]
}

resource "aws_ecs_task_definition" "grafana" {
  family                   = "grafana"
  container_definitions    = templatefile("grafana-task.json",
    {
      grafana_port         = local.grafana_port,
      oauth2_client_id     = aws_cognito_user_pool_client.grafana.id,
      oauth2_client_secret = aws_cognito_user_pool_client.grafana.client_secret,
      auth_endpoint        = "https://grafana-demo.auth.ap-southeast-2.amazoncognito.com/login",      
      token_endpoint       = "https://grafana-demo.auth.ap-southeast-2.amazoncognito.com/oauth2/token",
      userinfo_endpoint    = "https://grafana-demo.auth.ap-southeast-2.amazoncognito.com/oauth2/userInfo",
      log_group            = aws_cloudwatch_log_group.grafana.name,
      root_url             = "https://${local.domain_name}",
    })
  network_mode 		   = "awsvpc"
  requires_compatibilities = [ "FARGATE" ]
  memory		   = 512
  cpu 			   = 256
  # Execution means to boot your container
  execution_role_arn       = aws_iam_role.ecs_task.arn
  # What the task itself runs with
  task_role_arn            = aws_iam_role.grafana.arn

  depends_on = [ aws_iam_role_policy_attachment.task_run ]
}

resource "aws_iam_role" "ecs_task" {
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "task_run" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "grafana" {
  name_prefix = "grafana"
  path        = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  role   = aws_iam_role.grafana.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadingMetricsFromCloudWatch",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:DescribeAlarmsForMetric",
        "cloudwatch:DescribeAlarmHistory",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowReadingLogsFromCloudWatch",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:GetLogGroupFields",
        "logs:StartQuery",
        "logs:StopQuery",
        "logs:GetQueryResults",
        "logs:GetLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowReadingTagsInstancesRegionsFromEC2",
      "Effect": "Allow",
      "Action": ["ec2:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeRegions"],
      "Resource": "*"
    },
    {
      "Sid": "AllowReadingResourcesForTags",
      "Effect": "Allow",
      "Action": "tag:GetResources",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_security_group" "grafana" {
  name        = "grafana"
  description = "Allow inbound traffic to grafana"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow connections from the load balancer"
    from_port       = local.grafana_port
    to_port         = local.grafana_port
    protocol        = "tcp"
    security_groups = [ aws_security_group.alb.id ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = local.log_group
  retention_in_days = 7
}


# Connect the application to the application load balancer

resource "aws_lb_target_group" "grafana" {
  # We use a name_prefix because we set create_before_destroy = true
  # We set create_before_destroy = true so that we don't interrupt service
  name_prefix          = "grafan"
  port                 = local.grafana_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path     = "/api/health"
    protocol = "HTTP"
    matcher  = "200"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    host_header {
      values = [ local.domain_name ]
    }
  }
}

########################################################################
#                                                                      #
# An Application Load Balancer for TLS offload                         #
#                                                                      #
########################################################################

resource "aws_lb" "grafana" {
  name               = "grafana"
  load_balancer_type = "application"
  security_groups    = [ aws_security_group.alb.id ]
  internal           = false
  subnets            = var.public_subnets
}

resource "aws_lb_listener" "https" {
  port              = 443
  protocol          = "HTTPS"
  load_balancer_arn = aws_lb.grafana.arn
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.grafana.arn

  default_action {
    type             = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "Oops"
      status_code  = "500"
    }
  }
}

resource "aws_acm_certificate" "grafana" {
  domain_name       = local.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "grafana" {
  allow_overwrite = true
  name            = local.domain_name
  type            = "A"
  zone_id         = var.dns_zone_id

  alias {
    name                   = aws_lb.grafana.dns_name
    zone_id                = aws_lb.grafana.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "grafana-validation" {
  for_each = {
    for dvo in aws_acm_certificate.grafana.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.dns_zone_id
}

resource "aws_acm_certificate_validation" "grafana" {
  certificate_arn         = aws_acm_certificate.grafana.arn
  #validation_record_fqdns = aws_route53_record.grafana-validation.*.fqdn
}

resource "aws_security_group" "alb" {
  name        = "alb"
  description = "Allow TLS inbound traffic"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "alb_ingress" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  description       = "Allow TLS from the internet"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress" {
  type                     = "egress"
  security_group_id        = aws_security_group.alb.id
  from_port                = local.grafana_port
  to_port                  = local.grafana_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.grafana.id
}
