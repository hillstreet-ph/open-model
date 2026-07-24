#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root from the Contabo console." >&2
  exit 1
fi

DEPLOY_USER="${DEPLOY_USER:-openmodel}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
if [[ -z "${SSH_PUBLIC_KEY}" ]]; then
  echo "Set SSH_PUBLIC_KEY to the dedicated GitHub Actions public key." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
apt-get install -y ca-certificates curl git ufw unattended-upgrades
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

id "${DEPLOY_USER}" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "${DEPLOY_USER}"
usermod -aG docker "${DEPLOY_USER}"
install -d -m 0700 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"
printf '%s\n' "${SSH_PUBLIC_KEY}" > "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chmod 0600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
install -d -m 0750 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" /opt/open-model/{releases,shared}
cp /opt/open-model/deploy/.env.example /opt/open-model/shared/.env
chown "${DEPLOY_USER}:${DEPLOY_USER}" /opt/open-model/shared/.env
chmod 0600 /opt/open-model/shared/.env

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
systemctl enable --now docker
systemctl enable --now unattended-upgrades

echo "Bootstrap complete. Set MODEL_DOMAIN and secrets in /opt/open-model/shared/.env."
echo "For autonomous deployments, set OPEN_SECRET_URL in .env to fetch secrets from Open-Secret."
