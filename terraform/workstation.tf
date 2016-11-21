# User-data script
data "template_file" "workstation" {
  template = "${file("${path.module}/templates/workstation.sh.tpl")}"
  vars {
    access_key        = "${var.access_key}"
    secret_key        = "${var.secret_key}"
    region            = "${var.region}"
    hostname          = "workstation.${var.dnsimple_domain}"
    vault_address     = "vault.${var.dnsimple_domain}"
    vault_version     = "${var.vault_version}"
    postgres_ip       = "${aws_instance.postgres.private_ip}"
    postgres_username = "${random_id.vault_username.hex}"
    postgres_password = "${random_id.vault_password.hex}"
  }
}

# Workstation server
resource "aws_instance" "workstation" {
  ami           = "${data.aws_ami.ubuntu-1404.id}"
  instance_type = "t2.micro"

  key_name = "${aws_key_pair.default.key_name}"

  subnet_id              = "${aws_subnet.default.id}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  tags {
    Name = "${var.namespace}-workstation"
  }

  user_data = "${data.template_file.workstation.rendered}"
}

output "workstation" {
  value = "${aws_instance.workstation.public_ip}"
}
