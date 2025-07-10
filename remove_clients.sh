#!/bin/bash

# Suppression d’un client OpenVPN du fichier .env et redémarrage du conteneur

set -e

ENV_FILE=".env.openvpn"
CLIENT_TO_REMOVE=$1

if [[ -z "$CLIENT_TO_REMOVE" ]]; then
  echo "❌ Fournir un nom de client à supprimer."
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Fichier .env non trouvé: $ENV_FILE"
  exit 1
fi

cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

CURRENT_CLIENTS=$(grep '^OPENVPN_CLIENTS=' "$ENV_FILE" | cut -d '=' -f2-)
NEW_CLIENTS=$(echo "$CURRENT_CLIENTS" | tr ' ' '\n' | grep -v "^${CLIENT_TO_REMOVE}$" | tr '\n' ' ' | sed 's/ *$//')

if [[ "$CURRENT_CLIENTS" == "$NEW_CLIENTS" ]]; then
  echo "⚠️ Client non trouvé dans OPENVPN_CLIENTS."
  exit 0
fi

sed -i.bak "/^OPENVPN_CLIENTS=/c\OPENVPN_CLIENTS=$NEW_CLIENTS" "$ENV_FILE"

echo "♻️ Redémarrage du service..."
docker compose down
docker compose up -d

echo "✅ Client '$CLIENT_TO_REMOVE' supprimé avec succès."
