#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="${REPOSITORY:-https://github.com/hillstreet-ph/open-model.git}"
REVISION="${REVISION:?REVISION is required}"
ROOT=/opt/open-model
RELEASE="${ROOT}/releases/${REVISION}"

mkdir -p "${ROOT}/releases"
if [[ ! -d "${RELEASE}/.git" ]]; then
  git clone --filter=blob:none "${REPOSITORY}" "${RELEASE}"
fi
git -C "${RELEASE}" fetch --depth=1 origin "${REVISION}"
git -C "${RELEASE}" checkout --detach FETCH_HEAD
ln -sfn "${ROOT}/shared/.env" "${RELEASE}/deploy/.env"
ln -sfn "${RELEASE}" "${ROOT}/current"

cd "${RELEASE}/deploy"
docker compose config --quiet
docker compose pull
docker compose up -d --remove-orphans
timeout 180 bash -c 'until docker compose exec -T ollama ollama list >/dev/null 2>&1; do sleep 5; done'

DEFAULT_MODEL="$(sed -n 's/^DEFAULT_MODEL=//p' .env | tail -1)"
if [[ -n "${DEFAULT_MODEL}" ]]; then
  docker compose exec -T ollama ollama pull "${DEFAULT_MODEL}"
fi

curl --fail --silent --show-error http://127.0.0.1/api/tags >/dev/null
find "${ROOT}/releases" -mindepth 1 -maxdepth 1 -type d ! -path "${RELEASE}" -printf '%T@ %p\n' |
  sort -nr | tail -n +4 | cut -d' ' -f2- | xargs -r rm -rf --
echo "Deployed ${REVISION}"
