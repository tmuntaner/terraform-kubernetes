output "vpc_id" {
  value = "${aws_vpc.main.id}"
}

output "public_subnet_ids" {
  value = ["${aws_subnet.main.*.id}"]
}

output "gateway_id" {
  value = "${aws_internet_gateway.main.id}"
}
