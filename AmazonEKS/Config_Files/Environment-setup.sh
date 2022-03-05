# This document has been tested in the sa-east-1 region with Amazon linux 2 AMI

: '
AWS EKS Deployment Prerequisites

1. Networking
1.1. VPC
1.2. N Private Subnets (One private subnet per Availability Zone)
1.3. N Private Route Tables (One route table per Private Subnet)
1.4. N Public Subnets (One Public Subnet per Availability Zone)
1.5. One Public Route Table for the N Public Subnets above 
1.5. N Nat Gateways (One Nat Gateway per Public Subnet)
'

# Launch a small new EC2 instance: t3.small
# Public vs Private subnet: To decide where the EC2 will be deployed ask the customers how they will access this EC2 instance
# Volume disk: 80GB gp3
# tag: name: eks-admin
# key pair: create new

# Update the packages on the EC2 Instance
sudo yum update -y

# Set the EC2 instance datetime: sa-east-1
sudo timedatectl set-timezone America/Sao_Paulo

# Create an IAM role (ec2 instance profile); set the AdministratorAccess permissions and attach to the new EC2 instance

#-----INSTALL KUBERNETES TOOLS

# kubectl: get the latest kubectl from the upstream commuity - These binaries are identical to the Amazon EKS vended kubectl binaries
!
sudo curl --silent --location -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/$(curl --silent --location https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
!
sudo chmod +x /usr/local/bin/kubectl
!

# To check kubectl version: (yet it's no possible to check the cluster version)
kubectl version --short --client

# Enable kubectl bash_completion
!
kubectl completion bash >>  ~/.bash_completion
. /etc/profile.d/bash_completion.sh
. ~/.bash_completion
!

# Check the Aws Cli version
aws --version

# If we need to update awscli to version 2
# Check the latest version of aws cli on https://github.com/aws/aws-cli/blob/v2/CHANGELOG.rst
!
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
!

# Check aws cli version (You may need to restart the terminal)
aws --version

#Install jq, envsubst (from GNU gettext utilities) and bash-completion
sudo yum -y install jq gettext bash-completion moreutils

#Install yq for yaml processing
!
echo 'yq() {
  docker run --rm -i -v "${PWD}":/workdir mikefarah/yq "$@"
}' | tee -a ~/.bashrc && source ~/.bashrc
!

# Verify the binaries are in the path and executable

for command in kubectl jq envsubst aws
  do
    which $command &>/dev/null && echo "$command in path" || echo "$command NOT FOUND"
  done

# Set the AWS Load Balancer Controller version
# Check the latest version at https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases
# And if you like to read :) - https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
!
echo 'export LBC_VERSION="v2.2.4"' >>  ~/.bash_profile
.  ~/.bash_profile
!

# We should configure aws cli with the current region as default
!
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
export AZS=($(aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName' --output text --region $AWS_REGION))
!

# Check if AWS_REGION is set to desired region
test -n "$AWS_REGION" && echo AWS_REGION is "$AWS_REGION" || echo AWS_REGION is not set

# Save these into bash_profile
!
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export AZS=(${AZS[@]})" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region
!

# Set the CMK's name and Create a CMK for the EKS cluster to use when encrypting your Kubernetes secrets:
!
CMK_NAME="<CMK_NAME>"
!
aws kms create-alias --alias-name alias/$CMK_NAME --target-key-id $(aws kms create-key --query KeyMetadata.Arn --output text)
!
export MASTER_ARN=$(aws kms describe-key --key-id alias/$CMK_NAME --query KeyMetadata.Arn --output text)
!
echo "export MASTER_ARN=${MASTER_ARN}" | tee -a ~/.bash_profile
!

# Install eksctl
!
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
!
sudo mv -v /tmp/eksctl /usr/local/bin
!

## Confirm the eksctl command works:
eksctl version

## Enable eksctl bash-completion
!
eksctl completion bash >> ~/.bash_completion
. /etc/profile.d/bash_completion.sh
. ~/.bash_completion
!












