module "vpc-1" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"
  name    = "yl-vpc-1"

  cidr             = "10.1.0.0/16"
  azs              = slice(data.aws_availability_zones.available.names, 0, 3)
  #private_subnets  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnets   = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
  # database_subnets = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

  enable_nat_gateway   = false  # set to false if no private subnet
  single_nat_gateway   = false
  enable_dns_hostnames = true # needed for DNS resolution
}

resource "aws_dynamodb_table" "table" {
  name         = "yl-bookinventory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ISBN"

  attribute {
    name = "ISBN"
    type = "S" # todo: fill with apporpriate value
  }
}

resource "aws_iam_policy" "secrets_policy" {
  name        = "yl_ec2_to_secrets_policy"
  path        = "/"
  description = "To allow EC2 to access Secrets"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetRandomPassword",
                "secretsmanager:ListSecrets",
                "secretsmanager:BatchGetSecretValue"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "secretsmanager:*",
            "Resource": "arn:aws:secretsmanager:ap-southeast-1:255945442255:secret:dev/ylroot/secret-VohMeD"
        }
    ]
  })
}

resource "aws_iam_policy" "dbaccess_policy" {
  name = "yl-bookinventory-ddbaccess"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "dynamodb:BatchGetItem",
                "dynamodb:DescribeImport",
                "dynamodb:ConditionCheckItem",
                "dynamodb:DescribeContributorInsights",
                "dynamodb:Scan",
                "dynamodb:ListTagsOfResource",
                "dynamodb:Query",
                "dynamodb:DescribeStream",
                "dynamodb:DescribeTimeToLive",
                "dynamodb:DescribeGlobalTableSettings",
                "dynamodb:PartiQLSelect",
                "dynamodb:DescribeTable",
                "dynamodb:GetShardIterator",
                "dynamodb:DescribeGlobalTable",
                "dynamodb:GetItem",
                "dynamodb:DescribeContinuousBackups",
                "dynamodb:DescribeExport",
                "dynamodb:GetResourcePolicy",
                "dynamodb:DescribeKinesisStreamingDestination",
                "dynamodb:DescribeBackup",
                "dynamodb:GetRecords",
                "dynamodb:DescribeTableReplicaAutoScaling"
            ],
            "Resource": "${aws_dynamodb_table.table.arn}"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "dynamodb:ListContributorInsights",
                "dynamodb:DescribeReservedCapacityOfferings",
                "dynamodb:ListGlobalTables",
                "dynamodb:ListTables",
                "dynamodb:DescribeReservedCapacity",
                "dynamodb:ListBackups",
                "dynamodb:GetAbacStatus",
                "dynamodb:ListImports",
                "dynamodb:DescribeLimits",
                "dynamodb:DescribeEndpoints",
                "dynamodb:ListExports",
                "dynamodb:ListStreams"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
}

resource "aws_iam_role" "yl_ec2_role" {
  name = "yl_ec2_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "yl_attach_lambda_policy" {
  role       = aws_iam_role.yl_ec2_role.name
  policy_arn = aws_iam_policy.secrets_policy.arn
}

resource "aws_iam_role_policy_attachment" "yl_attach_dbaccess_policy" {
  role       = aws_iam_role.yl_ec2_role.name
  policy_arn = aws_iam_policy.dbaccess_policy.arn
}

resource "aws_iam_instance_profile" "yl_ec2_instance_profile" {
  name = "yl_ec2_profile"
  role = aws_iam_role.yl_ec2_role.name
}

resource "aws_instance" "public" {
  ami = "ami-04c913012f8977029"
  instance_type = "t2.micro"
  #subnet_id = "subnet-0caaf48818e0596cc" subnet-068c3fef4b1169bf5
  #subnet_id = "subnet-068c3fef4b1169bf5"
  subnet_id = data.aws_subnets.public-1.ids[0]
  iam_instance_profile = aws_iam_instance_profile.yl_ec2_instance_profile.name
  associate_public_ip_address = true
  #key_name = "yl-key-pair"
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  count = 2

  tags = {
    Name = "yl-ec2-${count.index}"
  }
}

resource "aws_security_group" "allow_ssh" {
  name = "yl-terraform-security-group"
  description = "Allow SSH inbound"
  #vpc_id = "vpc-01c494fe1e8787c82" vpc-0e387e57c766bf7b9
  #vpc_id = "vpc-0e387e57c766bf7b9"
  vpc_id = module.vpc-1.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 22
  ip_protocol = "tcp"
  to_port = 22
}

/*
resource "aws_vpc_security_group_egress_rule" "allow_all_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 443
  ip_protocol = "tcp"
  to_port = 443
}
*/

resource "aws_vpc_security_group_egress_rule" "allow_all_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 0
  ip_protocol = "tcp"
  to_port = 65535
}
