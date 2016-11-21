# User-data script
data "template_file" "vault" {
  template = "${file("${path.module}/templates/vault.sh.tpl")}"
  vars {
    hostname      = "vault.${var.dnsimple_domain}"
    vault_address = "${var.vault_address}"
    vault_version = "${var.vault_version}"
    certbot_email = "${var.certbot_email}"
  }
}

# Vault server
resource "aws_instance" "vault" {
  ami           = "${data.aws_ami.ubuntu-1404.id}"
  instance_type = "t2.micro"

  key_name = "${aws_key_pair.default.key_name}"

  subnet_id              = "${aws_subnet.default.id}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  tags {
    Name = "${var.namespace}-vault"
  }

  user_data = "${data.template_file.vault.rendered}"
}

output "vault" {
  value = "${aws_instance.vault.public_ip}"
}
