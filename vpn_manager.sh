#!/bin/bash

# =====================================
# SCRIPT DE GESTION OPENVPN ADAPTÉ
# Structure: julman99/openvpn-supereasy
# =====================================

CONTAINER_NAME="openvpn-supereasy"
EASY_RSA_PATH="/etc/openvpn/server/easy-rsa"
HOST_CLIENTS_DIR="./clients"
HOST_SERVER_DIR="./server"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonction d'affichage avec couleur
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Vérification que le conteneur existe et fonctionne
check_container() {
    if ! docker ps --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        error "Le conteneur $CONTAINER_NAME n'est pas en cours d'exécution"
        echo "Conteneurs Docker actifs:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        exit 1
    fi
    success "Conteneur $CONTAINER_NAME détecté et actif"
}

# Vérification de la structure OpenVPN
check_openvpn_structure() {
    info "Vérification de la structure OpenVPN..."
    
    # Vérifier que easy-rsa existe dans le conteneur
    if ! docker exec $CONTAINER_NAME test -d "$EASY_RSA_PATH"; then
        error "Répertoire easy-rsa non trouvé: $EASY_RSA_PATH"
        info "Structure détectée dans le conteneur:"
        docker exec $CONTAINER_NAME find /etc/openvpn -maxdepth 3 -type d
        exit 1
    fi
    
    success "Structure OpenVPN validée"
    docker exec $CONTAINER_NAME ls -la /etc/openvpn/
}

# Menu principal
show_menu() {
    clear
    echo -e "${PURPLE}===============================================${NC}"
    echo -e "${CYAN}🛡️  GESTIONNAIRE OPENVPN OIF - ADAPTÉ${NC}"
    echo -e "${PURPLE}===============================================${NC}"
    echo -e "${YELLOW}Structure: julman99/openvpn-supereasy${NC}"
    echo -e "${YELLOW}Easy-RSA: $EASY_RSA_PATH${NC}"
    echo ""
    echo "1.  📊 Status et informations du serveur"
    echo "2.  👥 Gestion des clients (ajouter/lister)"
    echo "3.  🔍 Monitoring et surveillance"
    echo "4.  🚫 Révocation et blacklist"
    echo "5.  📋 Logs et diagnostics"
    echo "6.  ⚙️  Maintenance et configuration"
    echo "7.  💾 Sauvegarde et restauration"
    echo "8.  🔧 Outils avancés"
    echo "9.  🌐 Interface web"
    echo "0.  ❌ Quitter"
    echo -e "${PURPLE}===============================================${NC}"
    read -p "Choisissez une option (0-9): " choice
}

# 1. Status et informations
show_status() {
    clear
    log "📊 STATUS DU SERVEUR OPENVPN"
    echo "============================================="
    
    # Status du conteneur Docker
    info "🐳 Status du conteneur:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|$CONTAINER_NAME"
    echo ""
    
    # Processus OpenVPN dans le conteneur
    info "🔧 Processus OpenVPN:"
    docker exec $CONTAINER_NAME bash -c "ps aux | grep openvpn | grep -v grep" || echo "Aucun processus OpenVPN détecté"
    echo ""
    
    # Ports ouverts
    info "🔌 Ports réseau:"
    docker exec $CONTAINER_NAME bash -c "netstat -tuln | grep -E ':1194|:1443|:445'" || echo "Ports OpenVPN non détectés"
    echo ""
    
    # Interfaces TUN
    info "🌐 Interfaces TUN/TAP:"
    docker exec $CONTAINER_NAME bash -c "ip addr show | grep -A 3 -B 1 'ovpnsetun\|tun'" || echo "Interfaces TUN non trouvées"
    echo ""
    
    # Certificats émis
    info "📜 Certificats émis:"
    cert_count=$(docker exec $CONTAINER_NAME bash -c "ls -1 $EASY_RSA_PATH/pki/issued/*.crt 2>/dev/null | wc -l" || echo "0")
    echo "Total certificats: $cert_count"
    docker exec $CONTAINER_NAME bash -c "ls -1 $EASY_RSA_PATH/pki/issued/*.crt 2>/dev/null | sed 's|.*/||' | sed 's|\.crt||'" | head -10
    echo ""
    
    # Certificats révoqués
    info "🚫 Certificats révoqués:"
    revoked_count=$(docker exec $CONTAINER_NAME bash -c "cat $EASY_RSA_PATH/pki/index.txt 2>/dev/null | grep '^R' | wc -l" || echo "0")
    echo "Total révoqués: $revoked_count"
    echo ""
    
    # Ressources système
    info "💻 Ressources du conteneur:"
    docker stats $CONTAINER_NAME --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || echo "Statistiques non disponibles"
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
}

# 2. Gestion des clients
manage_clients() {
    clear
    log "👥 GESTION DES CLIENTS"
    echo "============================================="
    echo "1. ➕ Ajouter un nouveau client"
    echo "2. 📋 Lister tous les clients émis"
    echo "3. 👀 Voir clients connectés"
    echo "4. 📥 Afficher configuration client"
    echo "5. 🔄 Régénérer toutes les configurations"
    echo "6. ⬅️  Retour au menu principal"
    echo ""
    read -p "Choisissez une option: " client_choice
    
    case $client_choice in
        1) add_client ;;
        2) list_clients ;;
        3) show_connected_clients ;;
        4) show_client_config ;;
        5) regenerate_all_configs ;;
        6) return ;;
        *) error "Option invalide"; sleep 2; manage_clients ;;
    esac
}

# Ajouter un client
add_client() {
    clear
    log "➕ AJOUT D'UN NOUVEAU CLIENT"
    echo "============================================="
    
    read -p "Nom du nouveau client: " client_name
    
    if [[ -z "$client_name" ]]; then
        error "Le nom du client ne peut pas être vide"
        sleep 2
        return
    fi
    
    # Validation du nom (alphanumerique + _ - seulement)
    if [[ ! "$client_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Le nom du client ne peut contenir que des lettres, chiffres, _ et -"
        sleep 2
        return
    fi
    
    # Vérifier si le certificat existe déjà
    if docker exec $CONTAINER_NAME test -f "$EASY_RSA_PATH/pki/issued/$client_name.crt" 2>/dev/null; then
        error "Le client '$client_name' existe déjà"
        sleep 2
        return
    fi
    
    info "Création du certificat pour '$client_name'..."
    
    # Créer le certificat via easy-rsa
    if docker exec $CONTAINER_NAME bash -c "cd $EASY_RSA_PATH && ./easyrsa --batch build-client-full '$client_name' nopass" 2>/dev/null; then
        success "✅ Certificat créé avec succès"
        
        # Utiliser la fonction create_client du script start.sh
        info "Génération du fichier de configuration..."
        docker exec $CONTAINER_NAME bash -c "
            cd $EASY_RSA_PATH
            client='$client_name'
            mkdir -p /etc/openvpn/clients
            client_file=\"/etc/openvpn/clients/\$client.ovpn\"
            
            echo '' > \"\$client_file\"
            echo 'client' >> \"\$client_file\"
            echo 'dev tun' >> \"\$client_file\"
            echo 'nobind' >> \"\$client_file\"
            echo 'key-direction 1' >> \"\$client_file\"
            echo 'auth SHA256' >> \"\$client_file\"
            echo 'resolv-retry infinite' >> \"\$client_file\"
            echo 'persist-key' >> \"\$client_file\"
            echo 'persist-tun' >> \"\$client_file\"
            echo 'mute-replay-warnings' >> \"\$client_file\"
            echo 'remote-cert-tls server' >> \"\$client_file\"
            echo 'verb 3' >> \"\$client_file\"
            
            echo '<key>' >> \"\$client_file\"
            cat \"./pki/private/\$client.key\" >> \"\$client_file\"
            echo '</key>' >> \"\$client_file\"
            
            echo '<cert>' >> \"\$client_file\"
            cat \"./pki/issued/\$client.crt\" >> \"\$client_file\"
            echo '</cert>' >> \"\$client_file\"
            
            echo '<ca>' >> \"\$client_file\"
            cat /etc/openvpn/server/ca.crt >> \"\$client_file\"
            echo '</ca>' >> \"\$client_file\"
            
            echo '<tls-auth>' >> \"\$client_file\"
            cat /etc/openvpn/server/ta.key >> \"\$client_file\"
            echo '</tls-auth>' >> \"\$client_file\"
            
            # Ajouter les connexions UDP et TCP
            echo '<connection>' >> \"\$client_file\"
            echo 'proto udp' >> \"\$client_file\"
            echo 'remote www.oifdev.info 1194' >> \"\$client_file\"
            echo '</connection>' >> \"\$client_file\"
            
            echo '<connection>' >> \"\$client_file\"
            echo 'proto tcp' >> \"\$client_file\"
            echo 'remote www.oifdev.info 1443' >> \"\$client_file\"
            echo '</connection>' >> \"\$client_file\"
        "
        
        # Copier la configuration vers l'hôte
        docker cp $CONTAINER_NAME:/etc/openvpn/clients/$client_name.ovpn $HOST_CLIENTS_DIR/
        
        success "✅ Configuration générée: $HOST_CLIENTS_DIR/$client_name.ovpn"
        info "🌐 Également disponible via: https://www.oifdev.info/vpn-configs/$client_name.ovpn"
        
        echo ""
        info "Configuration créée avec succès!"
        echo "Le client peut maintenant se connecter avec ce fichier."
    else
        error "Erreur lors de la création du certificat"
    fi
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    manage_clients
}

# Lister tous les clients
list_clients() {
    clear
    log "📋 LISTE COMPLÈTE DES CLIENTS"
    echo "============================================="
    
    info "📜 Certificats émis dans easy-rsa:"
    docker exec $CONTAINER_NAME bash -c "
        cd $EASY_RSA_PATH
        echo 'Certificats dans pki/issued/:'
        ls -la pki/issued/*.crt 2>/dev/null | grep -v server.crt | awk '{print \$9, \$6, \$7, \$8}' | sed 's|pki/issued/||' | sed 's|\.crt||'
    " || echo "Aucun certificat trouvé"
    
    echo ""
    
    info "📁 Fichiers de configuration (.ovpn) sur l'hôte:"
    if ls $HOST_CLIENTS_DIR/*.ovpn 1> /dev/null 2>&1; then
        ls -la $HOST_CLIENTS_DIR/*.ovpn | awk '{print $9, $6, $7, $8}' | sed "s|$HOST_CLIENTS_DIR/||"
    else
        echo "Aucun fichier .ovpn trouvé"
    fi
    
    echo ""
    
    info "📁 Fichiers de configuration dans le conteneur:"
    docker exec $CONTAINER_NAME bash -c "ls -la /etc/openvpn/clients/ 2>/dev/null" || echo "Répertoire clients vide"
    
    echo ""
    
    info "📊 Index des certificats (R=Révoqué, V=Valide):"
    docker exec $CONTAINER_NAME bash -c "cat $EASY_RSA_PATH/pki/index.txt 2>/dev/null | cut -f1,6 | sed 's|/CN=| |'" || echo "Fichier index non trouvé"
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    manage_clients
}

# Voir clients connectés
show_connected_clients() {
    clear
    log "👀 CLIENTS ACTUELLEMENT CONNECTÉS"
    echo "============================================="
    
    info "🔍 Recherche des connexions actives..."
    
    # Méthode 1: Logs de status OpenVPN
    info "📋 Fichier de status OpenVPN:"
    docker exec $CONTAINER_NAME bash -c "
        if [ -f /var/log/openvpn/openvpn-status.log ]; then
            cat /var/log/openvpn/openvpn-status.log
        else
            echo 'Fichier de status non trouvé dans /var/log/openvpn/'
        fi
    "
    
    echo ""
    
    # Méthode 2: Logs récents du conteneur
    info "📋 Logs récents de connexion:"
    docker logs $CONTAINER_NAME --tail=20 | grep -i "client\|connection\|peer" | tail -10 || echo "Aucun log de connexion récent"
    
    echo ""
    
    # Méthode 3: Interfaces et routes
    info "🌐 Interfaces TUN actives:"
    docker exec $CONTAINER_NAME bash -c "
        ip addr show | grep -A 5 ovpnsetun
        echo ''
        echo 'Routes actives:'
        ip route show | grep ovpnsetun
    " || echo "Interfaces TUN non trouvées"
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    manage_clients
}

# Afficher configuration client
show_client_config() {
    clear
    log "📥 AFFICHER CONFIGURATION CLIENT"
    echo "============================================="
    
    info "Clients disponibles:"
    if ls $HOST_CLIENTS_DIR/*.ovpn 1> /dev/null 2>&1; then
        ls -1 $HOST_CLIENTS_DIR/*.ovpn | sed "s|$HOST_CLIENTS_DIR/||" | sed 's|\.ovpn||'
    else
        echo "Aucun fichier .ovpn trouvé"
    fi
    
    echo ""
    read -p "Nom du client: " client_name
    
    if [[ -z "$client_name" ]]; then
        error "Nom du client requis"
        sleep 2
        return
    fi
    
    config_file="$HOST_CLIENTS_DIR/$client_name.ovpn"
    
    if [[ -f "$config_file" ]]; then
        success "📁 Configuration trouvée: $config_file"
        info "🌐 URL web: https://www.oifdev.info/vpn-configs/$client_name.ovpn"
        
        echo ""
        echo "=== DÉBUT DE LA CONFIGURATION ==="
        head -30 "$config_file"
        echo "..."
        echo "=== FIN DE LA CONFIGURATION ==="
        tail -10 "$config_file"
        
        echo ""
        info "Taille du fichier: $(wc -c < "$config_file") bytes"
        info "Lignes: $(wc -l < "$config_file")"
    else
        error "Configuration non trouvée pour $client_name"
        warning "Essayez de régénérer la configuration"
    fi
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    manage_clients
}

# Régénérer toutes les configurations
regenerate_all_configs() {
    clear
    log "🔄 RÉGÉNÉRATION DE TOUTES LES CONFIGURATIONS"
    echo "============================================="
    
    warning "⚠️  Cette action va régénérer tous les fichiers .ovpn"
    read -p "Continuer? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Opération annulée"
        sleep 2
        return
    fi
    
    info "Suppression des anciens fichiers .ovpn..."
    docker exec $CONTAINER_NAME bash -c "rm -f /etc/openvpn/clients/*.ovpn"
    
    info "Régénération basée sur les certificats existants..."
    docker exec $CONTAINER_NAME bash -c "
        cd $EASY_RSA_PATH
        for cert_file in \$(ls pki/issued/*.crt 2>/dev/null); do
            client_name=\$(basename \"\$cert_file\" .crt)
            if [ \"\$client_name\" != \"server\" ]; then
                echo \"Génération de: \$client_name\"
                client=\"\$client_name\"
                client_file=\"/etc/openvpn/clients/\$client.ovpn\"
                
                echo '' > \"\$client_file\"
                echo 'client' >> \"\$client_file\"
                echo 'dev tun' >> \"\$client_file\"
                echo 'nobind' >> \"\$client_file\"
                echo 'key-direction 1' >> \"\$client_file\"
                echo 'auth SHA256' >> \"\$client_file\"
                echo 'resolv-retry infinite' >> \"\$client_file\"
                echo 'persist-key' >> \"\$client_file\"
                echo 'persist-tun' >> \"\$client_file\"
                echo 'mute-replay-warnings' >> \"\$client_file\"
                echo 'remote-cert-tls server' >> \"\$client_file\"
                echo 'verb 3' >> \"\$client_file\"
                
                echo '<key>' >> \"\$client_file\"
                cat \"./pki/private/\$client.key\" >> \"\$client_file\"
                echo '</key>' >> \"\$client_file\"
                
                echo '<cert>' >> \"\$client_file\"
                cat \"./pki/issued/\$client.crt\" >> \"\$client_file\"
                echo '</cert>' >> \"\$client_file\"
                
                echo '<ca>' >> \"\$client_file\"
                cat /etc/openvpn/server/ca.crt >> \"\$client_file\"
                echo '</ca>' >> \"\$client_file\"
                
                echo '<tls-auth>' >> \"\$client_file\"
                cat /etc/openvpn/server/ta.key >> \"\$client_file\"
                echo '</tls-auth>' >> \"\$client_file\"
                
                echo '<connection>' >> \"\$client_file\"
                echo 'proto udp' >> \"\$client_file\"
                echo 'remote www.oifdev.info 1194' >> \"\$client_file\"
                echo '</connection>' >> \"\$client_file\"
                
                echo '<connection>' >> \"\$client_file\"
                echo 'proto tcp' >> \"\$client_file\"
                echo 'remote www.oifdev.info 1443' >> \"\$client_file\"
                echo '</connection>' >> \"\$client_file\"
            fi
        done
        
        echo 'Configurations générées:'
        ls -la /etc/openvpn/clients/
    "
    
    # Synchroniser avec l'hôte
    info "Synchronisation avec l'hôte..."
    docker exec $CONTAINER_NAME bash -c "ls /etc/openvpn/clients/*.ovpn 2>/dev/null" | while read config_file; do
        client_name=$(basename "$config_file" .ovpn)
        docker cp $CONTAINER_NAME:$config_file $HOST_CLIENTS_DIR/
        info "Copié: $client_name.ovpn"
    done
    
    success "✅ Régénération terminée"
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    manage_clients
}

# 3. Monitoring et surveillance
monitoring() {
    clear
    log "🔍 MONITORING ET SURVEILLANCE"
    echo "============================================="
    echo "1. 📊 Ressources système (CPU, RAM, réseau)"
    echo "2. 🌐 Interfaces et trafic réseau"
    echo "3. 📈 Statistiques de connexion"
    echo "4. 🔄 Logs en temps réel"
    echo "5. 🔍 Test de connectivité"
    echo "6. ⬅️  Retour au menu principal"
    echo ""
    read -p "Choisissez une option: " monitor_choice
    
    case $monitor_choice in
        1) show_system_resources ;;
        2) show_network_interfaces ;;
        3) show_connection_stats ;;
        4) show_live_logs ;;
        5) test_connectivity ;;
        6) return ;;
        *) error "Option invalide"; sleep 2; monitoring ;;
    esac
}

# Ressources système
show_system_resources() {
    clear
    log "📊 RESSOURCES SYSTÈME"
    echo "============================================="
    
    info "🐳 Ressources du conteneur Docker:"
    docker stats $CONTAINER_NAME --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
    
    echo ""
    
    info "💻 Processus dans le conteneur:"
    docker exec $CONTAINER_NAME bash -c "
        echo '=== Top processus par CPU ==='
        top -bn1 | head -15
        echo ''
        echo '=== Mémoire ==='
        free -h
        echo ''
        echo '=== Disque ==='
        df -h
    "
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    monitoring
}

# Interfaces réseau
show_network_interfaces() {
    clear
    log "🌐 INTERFACES ET TRAFIC RÉSEAU"
    echo "============================================="
    
    info "🔗 Interfaces réseau actives:"
    docker exec $CONTAINER_NAME bash -c "
        echo '=== Toutes les interfaces ==='
        ip addr show
        echo ''
        echo '=== Statistiques des interfaces ==='
        cat /proc/net/dev
        echo ''
        echo '=== Routes actives ==='
        ip route show
        echo ''
        echo '=== Règles iptables NAT ==='
        iptables -t nat -L POSTROUTING -v -n
    "
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    monitoring
}

# Statistiques de connexion
show_connection_stats() {
    clear
    log "📈 STATISTIQUES DE CONNEXION"
    echo "============================================="
    
    info "📊 Connexions et ports:"
    docker exec $CONTAINER_NAME bash -c "
        echo '=== Ports en écoute ==='
        netstat -tuln
        echo ''
        echo '=== Connexions établies ==='
        netstat -tun | grep ESTABLISHED
        echo ''
        echo '=== Processus réseau ==='
        netstat -tulnp | grep openvpn
    "
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    monitoring
}

# Logs en temps réel
show_live_logs() {
    clear
    log "🔄 LOGS EN TEMPS RÉEL"
    echo "============================================="
    info "Affichage des logs en temps réel (Ctrl+C pour arrêter)..."
    echo ""
    
    docker logs -f $CONTAINER_NAME
    
    monitoring
}

# Test de connectivité
test_connectivity() {
    clear
    log "🔍 TEST DE CONNECTIVITÉ"
    echo "============================================="
    
    info "🌐 Test de connectivité Internet:"
    docker exec $CONTAINER_NAME bash -c "
        echo '=== Test ping DNS publics ==='
        ping -c 3 8.8.8.8
        echo ''
        ping -c 3 1.1.1.1
        echo ''
        echo '=== Test résolution DNS ==='
        nslookup google.com
        echo ''
        echo '=== Test wget ==='
        timeout 10 wget -qO- http://ipinfo.io/ip && echo ' (IP publique)'
    "
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    monitoring
}

# 4. Révocation et blacklist
revocation_menu() {
    clear
    log "🚫 RÉVOCATION ET BLACKLIST"
    echo "============================================="
    echo "1. 🚫 Révoquer un certificat client"
    echo "2. 📋 Voir les certificats révoqués"
    echo "3. 🔄 Régénérer la CRL"
    echo "4. 🔌 Déconnecter tous les clients"
    echo "5. ⬅️  Retour au menu principal"
    echo ""
    read -p "Choisissez une option: " revoke_choice
    
    case $revoke_choice in
        1) revoke_client ;;
        2) show_revoked_clients ;;
        3) regenerate_crl ;;
        4) disconnect_all_clients ;;
        5) return ;;
        *) error "Option invalide"; sleep 2; revocation_menu ;;
    esac
}

# Révoquer un client
revoke_client() {
    clear
    log "🚫 RÉVOCATION D'UN CERTIFICAT"
    echo "============================================="
    
    info "Clients actifs (certificats non révoqués):"
    docker exec $CONTAINER_NAME bash -c "
        cd $EASY_RSA_PATH
        for cert in \$(ls pki/issued/*.crt 2>/dev/null); do
            client_name=\$(basename \"\$cert\" .crt)
            if [ \"\$client_name\" != \"server\" ]; then
                # Vérifier si pas révoqué
                if ! grep -q \"CN=\$client_name\" pki/index.txt | grep -q '^R'; then
                    echo \"  - \$client_name\"
                fi
            fi
        done
    "
    
    echo ""
    read -p "Nom du client à révoquer: " client_name
    
    if [[ -z "$client_name" ]]; then
        error "Nom du client requis"
        sleep 2
        return
    fi
    
    # Vérifier si le certificat existe
    if ! docker exec $CONTAINER_NAME test -f "$EASY_RSA_PATH/pki/issued/$client_name.crt" 2>/dev/null; then
        error "Certificat '$client_name' non trouvé"
        sleep 2
        return
    fi
    
    warning "⚠️  Cette action est IRRÉVERSIBLE!"
    warning "Le client '$client_name' sera immédiatement déconnecté et blacklisté"
    read -p "Confirmer la révocation (tapez 'REVOKE'): " confirm
    
    if [[ "$confirm" != "REVOKE" ]]; then
        info "Révocation annulée"
        sleep 2
        return
    fi
    
    info "Révocation du certificat '$client_name'..."
    
    # Révoquer le certificat
    if docker exec $CONTAINER_NAME bash -c "cd $EASY_RSA_PATH && echo 'yes' | ./easyrsa revoke '$client_name'" 2>/dev/null; then
        info "Régénération de la CRL..."
        
        # Régénérer la CRL
        if docker exec $CONTAINER_NAME bash -c "cd $EASY_RSA_PATH && ./easyrsa gen-crl" 2>/dev/null; then
            # Copier la nouvelle CRL
            docker exec $CONTAINER_NAME bash -c "cp $EASY_RSA_PATH/pki/crl.pem /etc/openvpn/server/"
            
            # Recharger OpenVPN
            info "Rechargement de la configuration OpenVPN..."
            docker exec $CONTAINER_NAME bash -c "pkill -USR1 openvpn" 2>/dev/null
            
            success "✅ Certificat '$client_name' révoqué avec succès"
            info "Le client est maintenant blacklisté et sera déconnecté"
            
            # Supprimer le fichier de configuration
            rm -f "$HOST_CLIENTS_DIR/$client_name.ovpn"
            docker exec $CONTAINER_NAME bash -c "rm -f /etc/openvpn/clients/$client_name.ovpn"
            info "Configuration supprimée"
            
        else
            error "Erreur lors de la régénération de la CRL"
        fi
    else
        error "Erreur lors de la révocation du certificat"
    fi
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    revocation_menu
}

# Voir les certificats révoqués
show_revoked_clients() {
    clear
    log "📋 CERTIFICATS RÉVOQUÉS"
    echo "============================================="
    
    info "📜 Liste des certificats révoqués:"
    docker exec $CONTAINER_NAME bash -c "
        cd $EASY_RSA_PATH
        echo 'Index des certificats révoqués (R = Révoqué):'
        cat pki/index.txt 2>/dev/null | grep '^R' | while read line; do
            client=\$(echo \$line | cut -d'/' -f2 | cut -d'=' -f2)
            date=\$(echo \$line | cut -f2)
            echo \"  - \$client (révoqué le: \$date)\"
        done
        
        echo ''
        echo 'Contenu du répertoire revoked/:'
        ls -la pki/revoked/ 2>/dev/null
    " || echo "Aucun certificat révoqué ou erreur d'accès"
    
    echo ""
    
    info "🔍 Détails de la CRL actuelle:"
    docker exec $CONTAINER_NAME bash -c "
        if [ -f $EASY_RSA_PATH/pki/crl.pem ]; then
            echo 'CRL générée le:'
            openssl crl -in $EASY_RSA_PATH/pki/crl.pem -text -noout | grep -E 'Last Update|Next Update'
            echo ''
            echo 'Nombre de certificats révoqués:'
            openssl crl -in $EASY_RSA_PATH/pki/crl.pem -text -noout | grep -c 'Serial Number'
        else
            echo 'Fichier CRL non trouvé'
        fi
    "
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    revocation_menu
}

# Régénérer la CRL
regenerate_crl() {
    clear
    log "🔄 RÉGÉNÉRATION DE LA CRL"
    echo "============================================="
    
    info "Régénération de la Certificate Revocation List..."
    
    if docker exec $CONTAINER_NAME bash -c "cd $EASY_RSA_PATH && ./easyrsa gen-crl" 2>/dev/null; then
        # Copier la nouvelle CRL
        docker exec $CONTAINER_NAME bash -c "cp $EASY_RSA_PATH/pki/crl.pem /etc/openvpn/server/"
        
        # Recharger OpenVPN
        docker exec $CONTAINER_NAME bash -c "pkill -USR1 openvpn" 2>/dev/null
        
        success "✅ CRL régénérée avec succès"
        info "La nouvelle CRL a été appliquée au serveur OpenVPN"
        
        # Afficher les détails
        info "Détails de la nouvelle CRL:"
        docker exec $CONTAINER_NAME bash -c "
            openssl crl -in $EASY_RSA_PATH/pki/crl.pem -text -noout | grep -E 'Last Update|Next Update|Serial Number' | head -10
        "
    else
        error "Erreur lors de la régénération de la CRL"
    fi
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    revocation_menu
}

# Déconnecter tous les clients
disconnect_all_clients() {
    clear
    log "🔌 DÉCONNEXION DE TOUS LES CLIENTS"
    echo "============================================="
    
    warning "⚠️  Cette action va déconnecter TOUS les clients connectés"
    read -p "Êtes-vous sûr? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Opération annulée"
        sleep 2
        return
    fi
    
    info "Envoi du signal de rechargement à tous les processus OpenVPN..."
    
    docker exec $CONTAINER_NAME bash -c "
        echo 'Processus OpenVPN avant déconnexion:'
        ps aux | grep openvpn | grep -v grep
        echo ''
        echo 'Envoi du signal USR2 (déconnexion gracieuse)...'
        pkill -USR2 openvpn
        sleep 2
        echo 'Statut après déconnexion:'
        ps aux | grep openvpn | grep -v grep
    "
    
    success "✅ Signal de déconnexion envoyé"
    info "Les clients vont être déconnectés et pourront se reconnecter"
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    revocation_menu
}

# 7. Sauvegarde et restauration
backup_menu() {
    clear
    log "💾 SAUVEGARDE ET RESTAURATION"
    echo "============================================="
    echo "1. 💾 Créer une sauvegarde complète"
    echo "2. 📁 Lister les sauvegardes"
    echo "3. 🔄 Restaurer une sauvegarde"
    echo "4. 🧹 Nettoyer les anciennes sauvegardes"
    echo "5. ⬅️  Retour au menu principal"
    echo ""
    read -p "Choisissez une option: " backup_choice
    
    case $backup_choice in
        1) create_backup ;;
        2) list_backups ;;
        3) restore_backup ;;
        4) cleanup_backups ;;
        5) return ;;
        *) error "Option invalide"; sleep 2; backup_menu ;;
    esac
}

# Créer une sauvegarde
create_backup() {
    clear
    log "💾 CRÉATION D'UNE SAUVEGARDE COMPLÈTE"
    echo "============================================="
    
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_name="openvpn-backup-$timestamp.tar.gz"
    
    info "Création de la sauvegarde: $backup_name"
    
    # Créer le répertoire de sauvegarde
    mkdir -p ./backups
    
    # Sauvegarder depuis l'hôte
    info "Sauvegarde des fichiers locaux..."
    tar -czf "./backups/$backup_name" \
        --exclude='./backups' \
        ./server ./clients ./docker-compose.yml \
        ./*.sh 2>/dev/null || true
    
    # Sauvegarder aussi depuis le conteneur
    info "Sauvegarde des données du conteneur..."
    temp_backup="/tmp/container-backup-$timestamp.tar.gz"
    docker exec $CONTAINER_NAME bash -c "
        cd /etc/openvpn
        tar -czf $temp_backup server/ clients/ 2>/dev/null
    "
    docker cp $CONTAINER_NAME:$temp_backup "./backups/container-$backup_name"
    docker exec $CONTAINER_NAME rm -f $temp_backup
    
    if [[ -f "./backups/$backup_name" ]]; then
        backup_size=$(du -h "./backups/$backup_name" | cut -f1)
        success "✅ Sauvegarde créée avec succès"
        info "📁 Fichier: ./backups/$backup_name"
        info "📊 Taille: $backup_size"
        
        echo ""
        info "Contenu de la sauvegarde:"
        tar -tzf "./backups/$backup_name" | head -20
        echo "..."
        
    else
        error "Erreur lors de la création de la sauvegarde"
    fi
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    backup_menu
}

# Lister les sauvegardes
list_backups() {
    clear
    log "📁 LISTE DES SAUVEGARDES"
    echo "============================================="
    
    if ls ./backups/*.tar.gz 1> /dev/null 2>&1; then
        info "Sauvegardes disponibles:"
        ls -lah ./backups/*.tar.gz | awk '{print $9, $5, $6, $7, $8}'
        
        echo ""
        info "Espace total utilisé:"
        du -sh ./backups/ 2>/dev/null || echo "Répertoire backups non trouvé"
    else
        warning "Aucune sauvegarde trouvée dans ./backups/"
    fi
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    backup_menu
}

# Interface web
web_interface() {
    clear
    log "🌐 INTERFACE WEB"
    echo "============================================="
    
    info "Interface de gestion web disponible à:"
    echo "🔗 https://www.oifdev.info/vpn-configs/"
    echo ""
    info "Pour installer l'interface HTML complète:"
    echo "1. Copiez le fichier manager.html vers votre serveur web"
    echo "2. Configurez l'authentification dans Nginx"
    echo "3. Adaptez les appels d'API si nécessaire"
    echo ""
    
    if [[ -f "./manager.html" ]]; then
        success "✅ Fichier manager.html détecté localement"
        info "Pour l'utiliser:"
        echo "   sudo cp ./manager.html /home/oif/"
        echo "   # Puis configurer Nginx pour servir ce fichier"
    else
        warning "Fichier manager.html non trouvé"
        info "Générez-le avec l'interface fournie précédemment"
    fi
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
}

# Menu principal et boucle
main() {
    # Vérifications initiales
    check_container
    check_openvpn_structure
    
    while true; do
        show_menu
        case $choice in
            1) show_status ;;
            2) manage_clients ;;
            3) monitoring ;;
            4) revocation_menu ;;
            5) # Logs - redirection vers monitoring
               info "Redirection vers monitoring..."
               sleep 1
               monitoring ;;
            6) # Maintenance - fonctionnalités de base
               warning "Fonctionnalités de maintenance de base disponibles"
               info "Utilisez les autres menus pour les actions spécifiques"
               sleep 3 ;;
            7) backup_menu ;;
            8) # Outils avancés - redirige vers les autres menus
               info "Outils avancés disponibles dans les autres sections"
               sleep 2 ;;
            9) web_interface ;;
            0) success "👋 Au revoir!"; exit 0 ;;
            *) error "Option invalide"; sleep 2 ;;
        esac
    done
}

# Point d'entrée
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi