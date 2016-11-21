# Configure the provider
provider "dnsimple" {
  token = "${var.dnsimple_token}"
  email = "${var.dnsimple_email}"
}

resource "dnsimple_record" "vault" {
  domain = "${var.dnsimple_domain}"
  name   = "vault"
  value  = "${aws_instance.vault.public_ip}"
  type   = "A"
  ttl    = 30
}
