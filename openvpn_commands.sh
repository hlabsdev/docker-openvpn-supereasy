#!/bin/bash

# =====================================
# COMMANDES OPENVPN ADAPTÉES À VOTRE STRUCTURE
# =====================================

CONTAINER_NAME="openvpn-supereasy"
EASY_RSA_PATH="/etc/openvpn/server/easy-rsa"

# 1. GÉNÉRATION DE NOUVEAUX CLIENTS
# ---------------------------------
add_new_client() {
    local client_name="$1"
    echo "🔐 Génération du client: $client_name"
    
    # Aller dans le répertoire easy-rsa
    docker compose exec $CONTAINER_NAME bash -c "cd $EASY_RSA_PATH && ./easyrsa build-client-full '$client_name' nopass"
    
    # Utiliser la fonction create_client du script start.sh
    docker compose exec $CONTAINER_NAME bash -c "
        cd $EASY_RSA_PATH
        source /start.sh
        create_client '$client_name'
    "
    
    echo "✅ Client $client_name créé - Configuration: /etc/openvpn/clients/$client_name.ovpn"
}

# 2. LISTE DES CLIENTS CONNECTÉS
# ------------------------------
show_connected_clients() {
    echo "👥 Clients actuellement connectés"
    
    # Chercher les logs de connexion
    docker compose exec $CONTAINER_NAME bash -c "
        if [ -f /var/log/openvpn/openvpn-status.log ]; then
            cat /var/log/openvpn/openvpn-status.log
        else
            # Chercher dans les logs du processus
            ps aux | grep openvpn | grep -v grep
            echo 'Logs de connexion non trouvés dans /var/log/openvpn/'
        fi
    "
}

# 3. LISTER TOUS LES CERTIFICATS ÉMIS
# -----------------------------------
list_all_clients() {
    echo "📋 Tous les certificats émis"
    
    docker compose exec $CONTAINER_NAME bash -c "
        echo '=== Certificats émis ==='
        ls -la $EASY_RSA_PATH/pki/issued/ | grep '.crt' | grep -v server.crt
        
        echo ''
        echo '=== Configurations clients disponibles ==='
        ls -la /etc/openvpn/clients/
        
        echo ''
        echo '=== Index des certificats ==='
        cat $EASY_RSA_PATH/pki/index.txt
    "
}

# 4. RÉVOQUER UN CLIENT (BLACKLIST)
# ---------------------------------
revoke_client() {
    local client_name="$1"
    echo "🚫 Révocation du client: $client_name"
    
    # Vérifier que le certificat existe
    if ! docker compose exec $CONTAINER_NAME bash -c "test -f $EASY_RSA_PATH/pki/issued/$client_name.crt"; then
        echo "❌ Certificat $client_name non trouvé"
        return 1
    fi
    
    # Révoquer le certificat
    docker compose exec $CONTAINER_NAME bash -c "
        cd $EASY_RSA_PATH
        echo 'yes' | ./easyrsa revoke '$client_name'
        ./easyrsa gen-crl
        cp -f pki/crl.pem /etc/openvpn/server/crl.pem
    "
    
    # Recharger OpenVPN pour appliquer la CRL
    docker compose exec $CONTAINER_NAME bash -c "
        pkill -USR1 openvpn
    "
    
    echo "✅ Client $client_name révoqué et blacklisté"
}

# 5. VOIR LES CERTIFICATS RÉVOQUÉS
# --------------------------------
show_revoked_clients() {
    echo "🚫 Certificats révoqués"
    
    docker compose exec $CONTAINER_NAME bash -c "
        echo '=== Certificats révoqués dans index.txt ==='
        cat $EASY_RSA_PATH/pki/index.txt | grep '^R'
        
        echo ''
        echo '=== Contenu du répertoire revoked ==='
        ls -la $EASY_RSA_PATH/pki/revoked/
        
        echo ''
        echo '=== CRL actuelle ==='
        openssl crl -in $EASY_RSA_PATH/pki/crl.pem -text -noout | head -20
    "
}

# 6. DÉCONNECTER UN CLIENT SPÉCIFIQUE
# -----------------------------------
disconnect_client() {
    local client_name="$1"
    echo "🔌 Déconnexion du client: $client_name"
    
    # Tenter de tuer la connexion via signal
    docker compose exec $CONTAINER_NAME bash -c "
        # Chercher le PID du processus openvpn
        openvpn_pids=\$(pgrep openvpn)
        for pid in \$openvpn_pids; do
            echo 'Envoi du signal USR2 au processus \$pid'
            kill -USR2 \$pid
        done
    "
    
    echo "Signal de déconnexion envoyé. Le client sera déconnecté au prochain ping."
}

# 7. VOIR L'UTILISATION DE LA BANDE PASSANTE
# ------------------------------------------
show_bandwidth() {
    echo "📈 Utilisation de la bande passante"
    
    docker compose exec $CONTAINER_NAME bash -c "
        echo '=== Interfaces réseau ==='
        ip addr show | grep -E 'ovpnsetun|eth0|tun'
        
        echo ''
        echo '=== Statistiques réseau ==='
        cat /proc/net/dev | head -2
        cat /proc/net/dev | grep -E 'ovpnsetun|eth0|tun'
        
        echo ''
        echo '=== Connexions actives ==='
        netstat -i
    "
}

# 8. RECHARGER LA CONFIGURATION À CHAUD
# -------------------------------------
reload_config() {
    echo "⚙️ Rechargement de la configuration"
    
    docker compose exec $CONTAINER_NAME bash -c "
        # Recharger tous les processus OpenVPN
        pkill -USR1 openvpn
        echo 'Signal USR1 envoyé à tous les processus OpenVPN'
        
        # Attendre un peu et vérifier le status
        sleep 2
        ps aux | grep openvpn | grep -v grep
    "
}

# 9. TESTER LA CONNECTIVITÉ
# -------------------------
test_connectivity() {
    echo "🔍 Test de connectivité"
    
    docker compose exec $CONTAINER_NAME bash -c "
        echo '=== Test ping DNS publics ==='
        ping -c 3 8.8.8.8
        ping -c 3 1.1.1.1
        
        echo ''
        echo '=== Test résolution DNS ==='
        nslookup google.com
        
        echo ''
        echo '=== Routes actives ==='
        ip route show
    "
}

# 10. BACKUP DES CONFIGURATIONS
# -----------------------------
backup_configs() {
    echo "💾 Sauvegarde des configurations"
    
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_name="openvpn-backup-$timestamp.tar.gz"
    
    # Créer le backup depuis l'host
    tar -czf "$backup_name" ./server ./clients
    
    echo "✅ Sauvegarde créée: $backup_name"
    echo "📁 Contient: ./server et ./clients"
    ls -lh "$backup_name"
}

# 11. VÉRIFIER L'ÉTAT DU SERVEUR
# ------------------------------
server_status() {
    echo "🔍 État du serveur OpenVPN"
    
    docker compose exec $CONTAINER_NAME bash -c "
        echo '=== Processus OpenVPN ==='
        ps aux | grep openvpn | grep -v grep
        
        echo ''
        echo '=== Ports ouverts ==='
        netstat -tuln | grep -E '1194|1443|445'
        
        echo ''
        echo '=== Interfaces TUN ==='
        ip addr show | grep -A 3 -B 1 ovpnsetun
        
        echo ''
        echo '=== Règles iptables NAT ==='
        iptables -t nat -L POSTROUTING -v
        
        echo ''
        echo '=== Fichiers de configuration ==='
        ls -la /etc/openvpn/server/
    "
}

# 12. MONITORING DES RESSOURCES
# -----------------------------
monitor_resources() {
    echo "📊 Monitoring des ressources"
    
    echo "=== Ressources du conteneur ==="
    docker stats $CONTAINER_NAME --no-stream
    
    echo ""
    echo "=== Utilisation mémoire dans le conteneur ==="
    docker compose exec $CONTAINER_NAME bash -c "
        free -h
        echo ''
        echo '=== Top des processus ==='
        top -bn1 | head -10
    "
}

# 13. OBTENIR UN FICHIER DE CONFIGURATION CLIENT
# ----------------------------------------------
get_client_config() {
    local client_name="$1"
    echo "📥 Récupération de la configuration pour: $client_name"
    
    if [ -f "./clients/$client_name.ovpn" ]; then
        echo "✅ Configuration trouvée: ./clients/$client_name.ovpn"
        echo ""
        echo "=== Début de la configuration ==="
        head -20 "./clients/$client_name.ovpn"
        echo "..."
        echo "=== Fin du fichier ==="
        tail -5 "./clients/$client_name.ovpn"
    else
        echo "❌ Configuration non trouvée pour $client_name"
        echo "Configurations disponibles:"
        ls -1 ./clients/*.ovpn 2>/dev/null | sed 's/.*\///' | sed 's/\.ovpn$//' || echo "Aucune configuration trouvée"
    fi
}

# 14. LOGS EN TEMPS RÉEL
# ----------------------
live_logs() {
    echo "🔄 Logs en temps réel (Ctrl+C pour arrêter)"
    docker compose logs -f $CONTAINER_NAME
}

# 15. NETTOYER LES CONFIGURATIONS ORPHELINES
# ------------------------------------------
cleanup_configs() {
    echo "🧹 Nettoyage des configurations orphelines"
    
    docker compose exec $CONTAINER_NAME bash -c "
        echo '=== Régénération de toutes les configurations clients ==='
        cd $EASY_RSA_PATH
        
        # Supprimer les anciens fichiers clients
        rm -f /etc/openvpn/clients/*.ovpn
        
        # Recréer toutes les configurations pour les certificats valides
        for cert_file in \$(ls pki/issued/*.crt); do
            client_name=\$(basename \"\$cert_file\" .crt)
            if [ \"\$client_name\" != \"server\" ]; then
                echo \"Recréation de la configuration pour: \$client_name\"
                source /etc/openvpn/start.sh
                create_client \"\$client_name\"
            fi
        done
        
        echo 'Nettoyage terminé'
        ls -la /etc/openvpn/clients/
    "
}

# FONCTIONS D'AIDE
# ===============

usage() {
    echo "🛡️  Gestionnaire OpenVPN - Commandes disponibles:"
    echo ""
    echo "add_new_client <nom>        - Ajouter un nouveau client"
    echo "show_connected_clients      - Voir les clients connectés"
    echo "list_all_clients           - Lister tous les certificats"
    echo "revoke_client <nom>         - Révoquer un client"
    echo "show_revoked_clients        - Voir les clients révoqués"
    echo "disconnect_client <nom>     - Déconnecter un client"
    echo "show_bandwidth              - Voir la bande passante"
    echo "reload_config               - Recharger la configuration"
    echo "test_connectivity           - Tester la connectivité"
    echo "backup_configs              - Sauvegarder les configurations"
    echo "server_status               - État du serveur"
    echo "monitor_resources           - Monitoring des ressources"
    echo "get_client_config <nom>     - Obtenir config client"
    echo "live_logs                   - Logs en temps réel"
    echo "cleanup_configs             - Nettoyer les configurations"
    echo ""
    echo "Exemple: add_new_client MonNouveauClient"
}

# Appel de la fonction si script exécuté directement
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    if [ $# -eq 0 ]; then
        usage
    else
        "$@"
    fi
fi