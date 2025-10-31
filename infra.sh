#!/bin/bash
set -e

echo "--------------------- Infrastructure as Code (IaC) ---------------------"
sleep 1

echo "Nome da instância: "
read NOME_INSTANCIA

echo "Nome da chave PEM: "
read NOME_CHAVE_PEM

echo "Nome do grupo de segurança: "
read GRUPO_SEGURANCA

echo "Tamanho do disco EBS: (GB)"
read TAMANHO_DISCO

echo "Nome do bucket 1: (raw)"
read NOME_BUCKET_UM

echo "Nome do bucket 2: (trusted)"
read NOME_BUCKET_DOIS

echo "Nome do bucket 3: (client)"
read NOME_BUCKET_TRES


if [ -z "$NOME_INSTANCIA" ];
then
    NOME_INSTANCIA="nome-de-instancia-padrao"
fi

if [ -z "$NOME_CHAVE_PEM" ];
then
    NOME_CHAVE_PEM="nome-de-chave-padrao"
fi

if [ -z "$GRUPO_SEGURANCA" ];
then
    GRUPO_SEGURANCA="sg-grupo-padrao"
fi

if [ -z "$TAMANHO_DISCO" ];
then
    TAMANHO_DISCO="10"
fi

SUFIXO=$(date +%s)

if [ -z "$NOME_BUCKET_UM" ];
then
    NOME_BUCKET_UM="nome-de-bucket-padrao-raw-$SUFIXO"
fi

if [ -z "$NOME_BUCKET_DOIS" ];
then
    NOME_BUCKET_DOIS="nome-de-bucket-padrao-trusted-$SUFIXO"
fi

if [ -z "$NOME_BUCKET_TRES" ];
then
    NOME_BUCKET_TRES="nome-de-bucket-padrao-client-$SUFIXO"
fi

# criando ec2
echo "---CRIANDO INSTÂNCIA---"

# obtendo o id da vpc
ID_VPCS=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)

# criando o grupo de seguranca se nao existir
aws ec2 describe-security-groups --group-names "$GRUPO_SEGURANCA" >/dev/null 2>&1 || \
aws ec2 create-security-group \
 --group-name "$GRUPO_SEGURANCA" \
 --vpc-id "$ID_VPCS" \
 --description "Grupo de seguranca PayMetrics" \
 --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$GRUPO_SEGURANCA}]"


# pegando id do grupo de seguranca
ID_SECURITY_GROUP=$(aws ec2 describe-security-groups \
  --query "SecurityGroups[0].GroupId" \
  --filters "Name=group-name,Values=$GRUPO_SEGURANCA" \
  --output text)

# porta http
aws ec2 authorize-security-group-ingress \
 --group-id "$ID_SECURITY_GROUP" \
 --protocol tcp \
 --port 80 \
 --cidr 0.0.0.0/0 || true

# porta ssh
aws ec2 authorize-security-group-ingress \
 --group-id "$ID_SECURITY_GROUP" \
 --protocol tcp \
 --port 22 \
 --cidr 0.0.0.0/0 || true


# criando par de chaves pem
aws ec2 create-key-pair \
 --key-name "$NOME_CHAVE_PEM" \
 --region us-east-1     \
 --query 'KeyMaterial' \
 --output text > "$NOME_CHAVE_PEM.pem"

chmod 400 "$NOME_CHAVE_PEM.pem"

# criando instancia e pegando o id
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --count 1 \
    --security-group-ids "$ID_SECURITY_GROUP" \
    --instance-type t3.small \
    --key-name "$NOME_CHAVE_PEM" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$TAMANHO_DISCO,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NOME_INSTANCIA}]" \
    --query "Instances[0].InstanceId" \
    --output text)

# esperando criar a instancia
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

echo "$INSTANCE_ID"

# pegando ip publico da instancia
IP_PUBLICO=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "IP Público da instância: $IP_PUBLICO"

# criando buckets
aws s3api create-bucket --bucket "$NOME_BUCKET_UM" --region us-east-1
aws s3api create-bucket --bucket "$NOME_BUCKET_DOIS" --region us-east-1
aws s3api create-bucket --bucket "$NOME_BUCKET_TRES" --region us-east-1

# criando diretorios de hardware e processes
aws s3api put-object --bucket "$NOME_BUCKET_UM" --key hardware/
aws s3api put-object --bucket "$NOME_BUCKET_UM" --key processes/