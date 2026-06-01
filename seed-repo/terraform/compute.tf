resource "aws_instance" "app" {
  ami           = "ami-02fd066b86800f60c"
  instance_type = "m5.4xlarge"

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    DB_PASSWORD=SuperSecret123
    echo "$DB_PASSWORD" > /etc/app.conf
  EOF

  tags = {
    Name = "demo-app"
  }
}
