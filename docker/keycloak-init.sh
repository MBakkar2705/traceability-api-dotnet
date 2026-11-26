#!/bin/bash
# Lot 14 : cree les 4 comptes de demonstration dans le realm "traceability" de Keycloak.
# Lance par le conteneur keycloak-init, avec kcadm.sh (l'outil d'administration de Keycloak).
# Les mots de passe viennent des variables d'environnement (fichier .env), jamais du depot.
set -euo pipefail

SERVER="http://keycloak:8080"
REALM="traceability"
CONFIG="/tmp/kcadm.config"
kc() { /opt/keycloak/bin/kcadm.sh "$@" --config "$CONFIG"; }

# Keycloak met environ une minute a demarrer et a importer le realm : on reessaie.
ready=0
for ((i = 0; i < 60; i++)); do
  if kc config credentials --server "$SERVER" --realm master \
       --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 5
done
[ "$ready" = "1" ] || { echo "Keycloak ne repond pas apres 5 minutes." >&2; exit 1; }

# $1 compte, $2 role, $3 prenom. Rejouable : un compte qui existe deja est complete, pas recree.
create_account() {
  local out
  if ! out=$(kc create users -r "$REALM" -s username="$1" -s enabled=true \
        -s email="$1@example.com" -s emailVerified=true -s firstName="$3" -s lastName=Test 2>&1); then
    if [[ "${out,,}" == *exists* ]]; then
      echo "$1 existe deja."
    else
      echo "$out" >&2
      exit 1
    fi
  fi
  kc set-password -r "$REALM" --username "$1" --new-password "$DEMO_USER_PASSWORD"
  kc add-roles -r "$REALM" --uusername "$1" --rolename "$2"
  echo "Compte $1 pret (role $2)."
}

create_account reader-test     reader     Reader
create_account writer-test     writer     Writer
create_account supervisor-test supervisor Supervisor
create_account auditor-test    auditor    Auditor
