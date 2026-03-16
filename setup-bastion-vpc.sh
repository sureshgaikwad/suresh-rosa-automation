#!/usr/bin/env bash
set -euo pipefail

REGION="ap-south-1"
AZ="${REGION}a"
KEY_NAME="sgaikwad"
AMI_ID="ami-019715e0d74f695be"
INSTANCE_TYPE="t3.micro"
NEW_VPC_CIDR="172.16.0.0/16"
PUBLIC_SUBNET_CIDR="172.16.1.0/24"
VNC_PASSWORD="bastion1"
NAME_PREFIX="bastion"

OLD_VPC_ID="vpc-0ceb64adbd6e490ef"

log() { echo ">>> $*"; }
err() { echo "ERROR: $*" >&2; }

########################################################################
# PHASE 1 — Destroy the old bastion VPC
########################################################################
destroy_old_vpc() {
    log "===== PHASE 1: Destroying old bastion VPC ${OLD_VPC_ID} ====="

    # Check if old VPC still exists
    if ! aws ec2 describe-vpcs --vpc-ids "$OLD_VPC_ID" --region "$REGION" &>/dev/null; then
        log "Old VPC ${OLD_VPC_ID} does not exist — skipping Phase 1"
        return 0
    fi

    # 1. Terminate any running instances
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=${OLD_VPC_ID}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text --region "$REGION")
    if [[ -n "$instance_ids" ]]; then
        log "Terminating instances: ${instance_ids}"
        aws ec2 terminate-instances --instance-ids $instance_ids --region "$REGION" > /dev/null
        aws ec2 wait instance-terminated --instance-ids $instance_ids --region "$REGION"
        log "Instances terminated"
    else
        log "No running instances found"
    fi

    # 2. Delete VPC endpoints
    local vpce_ids
    vpce_ids=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=${OLD_VPC_ID}" \
        --query 'VpcEndpoints[*].VpcEndpointId' --output text --region "$REGION")
    if [[ -n "$vpce_ids" ]]; then
        log "Deleting VPC endpoints: ${vpce_ids}"
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $vpce_ids --region "$REGION" > /dev/null
    fi

    # 3. Delete non-default security groups
    local sg_ids
    sg_ids=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${OLD_VPC_ID}" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region "$REGION")
    for sg in $sg_ids; do
        log "Deleting security group: ${sg}"
        aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null || true
    done

    # 4. Disassociate and delete non-main route tables
    local rtb_ids
    rtb_ids=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${OLD_VPC_ID}" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text --region "$REGION")
    for rtb in $rtb_ids; do
        local assoc_ids
        assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rtb" \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text --region "$REGION")
        for assoc in $assoc_ids; do
            log "Disassociating route table ${rtb} (assoc ${assoc})"
            aws ec2 disassociate-route-table --association-id "$assoc" --region "$REGION"
        done
        log "Deleting route table: ${rtb}"
        aws ec2 delete-route-table --route-table-id "$rtb" --region "$REGION"
    done

    # 5. Delete subnets
    local subnet_ids
    subnet_ids=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${OLD_VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text --region "$REGION")
    for subnet in $subnet_ids; do
        log "Deleting subnet: ${subnet}"
        aws ec2 delete-subnet --subnet-id "$subnet" --region "$REGION"
    done

    # 6. Detach and delete Internet Gateway
    local igw_ids
    igw_ids=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=${OLD_VPC_ID}" \
        --query 'InternetGateways[*].InternetGatewayId' --output text --region "$REGION")
    for igw in $igw_ids; do
        log "Detaching IGW: ${igw}"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$OLD_VPC_ID" --region "$REGION"
        log "Deleting IGW: ${igw}"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region "$REGION"
    done

    # 7. Delete the VPC
    log "Deleting VPC: ${OLD_VPC_ID}"
    aws ec2 delete-vpc --vpc-id "$OLD_VPC_ID" --region "$REGION"
    log "Old bastion VPC destroyed successfully"
}

########################################################################
# PHASE 2 — Create new bastion VPC + host
########################################################################
create_new_vpc() {
    log "===== PHASE 2: Creating new bastion VPC (${NEW_VPC_CIDR}) ====="

    # 1. Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block "$NEW_VPC_CIDR" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${NAME_PREFIX}-vpc}]" \
        --query 'Vpc.VpcId' --output text --region "$REGION")
    log "Created VPC: ${VPC_ID}"

    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}' --region "$REGION"
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}' --region "$REGION"

    # 2. Create and attach Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${NAME_PREFIX}-igw}]" \
        --query 'InternetGateway.InternetGatewayId' --output text --region "$REGION")
    aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
    log "Created and attached IGW: ${IGW_ID}"

    # 3. Create public subnet
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$PUBLIC_SUBNET_CIDR" \
        --availability-zone "$AZ" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-subnet}]" \
        --query 'Subnet.SubnetId' --output text --region "$REGION")
    aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$REGION"
    log "Created public subnet: ${SUBNET_ID}"

    # 4. Create route table with IGW route
    RTB_ID=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${NAME_PREFIX}-public-rtb}]" \
        --query 'RouteTable.RouteTableId' --output text --region "$REGION")
    aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGW_ID" --region "$REGION" > /dev/null
    aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_ID" \
        --region "$REGION" > /dev/null
    log "Created route table: ${RTB_ID}"

    # 5. Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${NAME_PREFIX}-sg" \
        --description "Bastion host security group - SSH access" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${NAME_PREFIX}-sg}]" \
        --query 'GroupId' --output text --region "$REGION")
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION" > /dev/null
    log "Created security group: ${SG_ID}"

    # 6. Launch bastion instance with user data
    USERDATA=$(cat <<'USERDATA_EOF'
#!/bin/bash
set -ex
exec > /var/log/bastion-setup.log 2>&1

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y xfce4 xfce4-goodies tigervnc-standalone-server tigervnc-common firefox unzip curl

BASTION_USER="ubuntu"
BASTION_HOME="/home/${BASTION_USER}"

# --- VNC setup ---
sudo -u "$BASTION_USER" mkdir -p "${BASTION_HOME}/.vnc"

echo -e "bastion1\nbastion1\nn" | sudo -u "$BASTION_USER" vncpasswd 2>/dev/null

cat > "${BASTION_HOME}/.vnc/xstartup" <<'XSTARTUP'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XSTARTUP
chmod +x "${BASTION_HOME}/.vnc/xstartup"
chown -R "${BASTION_USER}:${BASTION_USER}" "${BASTION_HOME}/.vnc"

cat > /etc/systemd/system/vncserver@.service <<'VNCUNIT'
[Unit]
Description=TigerVNC Server for display %i
After=syslog.target network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/usr/bin/vncserver :%i -geometry 1920x1080 -depth 24 -fg
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
VNCUNIT

systemctl daemon-reload
systemctl enable vncserver@1
systemctl start vncserver@1

# --- rosa CLI ---
curl -sLO https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz
tar xzf rosa-linux.tar.gz
mv rosa /usr/local/bin/
rm -f rosa-linux.tar.gz

# --- oc CLI ---
curl -sLO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar xzf openshift-client-linux.tar.gz
mv oc kubectl /usr/local/bin/
rm -f openshift-client-linux.tar.gz README.md

# --- AWS CLI v2 ---
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -qo awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# --- DNS fix for .local domains (needed for ROSA HCP private clusters) ---
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/rosa-hypershift.conf <<'DNSFIX'
[Resolve]
DNS=172.16.0.2
Domains=~hypershift.local
DNSFIX
systemctl restart systemd-resolved

echo "===== Bastion setup complete at $(date) ====="
USERDATA_EOF
    )

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --subnet-id "$SUBNET_ID" \
        --security-group-ids "$SG_ID" \
        --associate-public-ip-address \
        --user-data "$USERDATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_PREFIX}-host}]" \
        --query 'Instances[0].InstanceId' --output text --region "$REGION")
    log "Launched instance: ${INSTANCE_ID} — waiting for it to be running..."

    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$REGION")

    log "Instance is running"
}

########################################################################
# Main
########################################################################
destroy_old_vpc
create_new_vpc

echo ""
echo "============================================================"
echo "  Bastion VPC Setup Complete"
echo "============================================================"
echo ""
echo "  VPC ID:          ${VPC_ID}"
echo "  Subnet ID:       ${SUBNET_ID}"
echo "  Security Group:  ${SG_ID}"
echo "  IGW ID:          ${IGW_ID}"
echo "  Instance ID:     ${INSTANCE_ID}"
echo "  Public IP:       ${PUBLIC_IP}"
echo ""
echo "  SSH:"
echo "    ssh -i ~/.ssh/sgaikwad.pem ubuntu@${PUBLIC_IP}"
echo ""
echo "  VNC (via SSH tunnel):"
echo "    ssh -L 5901:localhost:5901 -i ~/.ssh/sgaikwad.pem ubuntu@${PUBLIC_IP}"
echo "    Then connect VNC client to localhost:5901"
echo "    VNC password: ${VNC_PASSWORD}"
echo ""
echo "  NOTE: User-data bootstrap (GUI + CLI installs) takes ~5-10"
echo "  minutes after instance starts. Monitor progress with:"
echo "    ssh -i ~/.ssh/sgaikwad.pem ubuntu@${PUBLIC_IP} tail -f /var/log/bastion-setup.log"
echo "============================================================"
