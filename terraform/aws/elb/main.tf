resource "aws_security_group" "main" {
  vpc_id = "${var.vpc_id}"

  lifecycle {
    create_before_destroy = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "api_internal" {
  name            = "kubernetes-api-internal"
  subnets         = ["${var.subnet_ids}"]
  internal        = true
  security_groups = ["${aws_security_group.main.id}"]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    target              = "HTTP:80/healthz"
  }
}

resource "aws_elb" "api_public" {
  name            = "kubernetes-api-public"
  subnets         = ["${var.subnet_ids}"]
  internal        = false
  security_groups = ["${aws_security_group.main.id}"]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    target              = "HTTP:80/healthz"
  }
}
