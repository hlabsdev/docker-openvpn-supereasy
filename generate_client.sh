#!/bin/bash

# Génère manuellement le fichier .ovpn d’un client (si le conteneur supporte le mode on-demand)

CLIENT=$1
if [[ -z "$CLIENT" ]]; then
  echo "Usage: $0 <client_name>"
  exit 1
fi

echo "📦 Génération du fichier .ovpn pour le client '$CLIENT'..."

docker compose exec openvpn-supereasy bash -c "
  if [ -f /etc/openvpn/clients/$CLIENT.ovpn ]; then
    echo '✅ Fichier déjà existant : /etc/openvpn/clients/$CLIENT.ovpn'
  else
    echo '❌ Client non présent ou non généré. Ajoutez-le à OPENVPN_CLIENTS et redémarrez.'
  fi
"

mkdir -p ./exported_clients
docker cp openvpn-supereasy:/etc/openvpn/clients/$CLIENT.ovpn ./exported_clients/

echo "📁 Exporté : ./exported_clients/$CLIENT.ovpn"
