resource "aws_vpc" "main" {
  cidr_block           = "${var.cidr_block}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags {
    Name = "${terraform.env}-vpc"
  }
}

resource "aws_vpc_dhcp_options" "main" {
  domain_name         = "eu-central-1.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = "${aws_vpc.main.id}"
  dhcp_options_id = "${aws_vpc_dhcp_options.main.id}"
}

resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${terraform.env}-gateway"
  }
}

resource "aws_subnet" "main" {
  count = "${length(var.azs)}"

  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 5, count.index + 1)}"
  availability_zone       = "${element(var.azs, count.index)}"
  map_public_ip_on_launch = "true"

  tags {
    Name = "${terraform.env}-public-subnet-${element(var.azs, count.index)}"
  }
}

resource "aws_route" "internet" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.main.id}"
}

resource "aws_eip" "gateway_eip" {
  count = "${length(var.azs)}"
  vpc   = "true"
}
