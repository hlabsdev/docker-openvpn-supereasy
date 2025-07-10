#!/bin/bash

# Script de déploiement OpenVPN optimisé
# Usage: ./deploy_openvpn.sh

set -e

echo "🔧 Déploiement OpenVPN optimisé"
echo "================================"

# Vérifications préalables
echo "📋 Vérifications préalables..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker n'est pas installé"
    exit 1
fi

if ! command -v nginx &> /dev/null; then
    echo "❌ Nginx n'est pas installé"
    exit 1
fi

# Sauvegarde des configurations actuelles
echo "💾 Sauvegarde des configurations actuelles..."
cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
cp /etc/nginx/sites-enabled/oif /etc/nginx/sites-enabled/oif.backup.$(date +%Y%m%d_%H%M%S)

# Arrêt du service OpenVPN
echo "⏹️  Arrêt du service OpenVPN..."
docker compose down || true

# Attente pour s'assurer que les ports sont libérés
sleep 5

# Vérification que les ports sont libres
echo "🔍 Vérification des ports..."
if netstat -tuln | grep -q ":1443 "; then
    echo "⚠️  Le port 1443 est déjà utilisé"
    netstat -tuln | grep ":1443"
    echo "Voulez-vous continuer ? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Démarrage avec la nouvelle configuration
echo "🚀 Démarrage avec la nouvelle configuration..."
docker compose up -d

# Attente du démarrage complet
echo "⏳ Attente du démarrage complet..."
sleep 10

# Vérification du status
echo "✅ Vérification du status..."
docker compose ps

# Test de connectivité
echo "🔗 Test de connectivité..."
if docker compose exec openvpn-supereasy ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "✅ Connectivité Internet OK"
else
    echo "❌ Problème de connectivité Internet"
fi

# Vérification des ports
echo "🔍 Vérification des ports ouverts..."
echo "UDP 1194: $(netstat -uln | grep :1194 && echo "✅ OK" || echo "❌ Fermé")"
echo "TCP 1443: $(netstat -tln | grep :1443 && echo "✅ OK" || echo "❌ Fermé")"

# Affichage des logs récents
echo "📋 Logs récents:"
docker compose logs --tail=20

echo ""
echo "🎉 Déploiement terminé!"
echo ""
echo "📌 Prochaines étapes:"
echo "1. Mettre à jour la configuration Nginx si nécessaire"
echo "2. Redémarrer Nginx: sudo systemctl reload nginx"
echo "3. Télécharger les nouvelles configurations client"
echo "4. Tester la connectivité avec les clients"
echo ""
echo "📁 Répertoire des configurations client: ./clients/"
echo "🌐 Interface web: https://www.oifdev.info/vpn-configs/"
echo ""
echo "🔧 Commandes utiles:"
echo "- Voir les logs: docker compose logs -f"
echo "- Redémarrer: docker compose restart"
echo "- Arrêter: docker compose down"
echo "- Voir le status: docker compose ps"