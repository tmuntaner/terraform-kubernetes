output "public_dns_name" {
  value = "${aws_elb.api_public.dns_name}"
}

output "public_elb_id" {
  value = "${aws_elb.api_public.id}"
}

output "internal_dns_name" {
  value = "${aws_elb.api_internal.dns_name}"
}

output "internal_elb_id" {
  value = "${aws_elb.api_internal.id}"
}
