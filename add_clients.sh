#!/bin/bash

# Script pour ajouter des clients à la variable OPENVPN_CLIENTS dans un fichier .env
# Usage: ./add_openvpn_clients_env.sh client1 client2 ...

set -e

ENV_FILE=".env.openvpn"
BACKUP_FILE="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

echo "🔧 Ajout de clients OpenVPN via fichier .env"
echo "============================================"

if [[ $# -eq 0 ]]; then
    echo "❌ Aucun nom de client fourni."
    echo "Usage: $0 client1 client2 ..."
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Fichier .env non trouvé: $ENV_FILE"
    exit 1
fi

# Sauvegarde
cp "$ENV_FILE" "$BACKUP_FILE"
echo "💾 Sauvegarde créée: $BACKUP_FILE"

# Extraction de la ligne
LINE=$(grep '^OPENVPN_CLIENTS=' "$ENV_FILE" || echo "OPENVPN_CLIENTS=")
CURRENT_CLIENTS=${LINE#OPENVPN_CLIENTS=}
IFS=' ' read -r -a CLIENT_ARRAY <<< "$CURRENT_CLIENTS"

# Ajout des nouveaux clients sans doublons
NEW_CLIENTS=()
for c in "$@"; do
    if [[ ! " ${CLIENT_ARRAY[*]} " =~ " $c " ]]; then
        echo "➕ Ajout du client: $c"
        CLIENT_ARRAY+=("$c")
        NEW_CLIENTS+=("$c")
    else
        echo "⚠️  Client déjà présent: $c"
    fi
done

if [[ ${#NEW_CLIENTS[@]} -eq 0 ]]; then
    echo "✅ Aucun nouveau client ajouté."
    exit 0
fi

# Tri + réécriture
SORTED_CLIENTS=$(printf "%s\n" "${CLIENT_ARRAY[@]}" | sort | tr '\n' ' ' | sed 's/ *$//')

# Mise à jour dans le .env
sed -i.bak "/^OPENVPN_CLIENTS=/c\OPENVPN_CLIENTS=$SORTED_CLIENTS" "$ENV_FILE"

# Redémarrage
echo "🚀 Redémarrage du conteneur OpenVPN..."
docker compose down
sleep 2
docker compose up -d

echo ""
echo "🎉 Clients ajoutés avec succès: ${NEW_CLIENTS[*]}"
echo "📌 Nouvelle liste: $SORTED_CLIENTS"
