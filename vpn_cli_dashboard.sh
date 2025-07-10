#!/bin/bash

ENV_FILE=".env.openvpn"
clear

while true; do
  echo "==============================="
  echo "🛡️  Dashboard OpenVPN (CLI)"
  echo "==============================="
  echo "1. ➕ Ajouter un client"
  echo "2. ❌ Supprimer un client"
  echo "3. ⛔ Bloquer temporairement"
  echo "4. 📦 Générer fichier .ovpn"
  echo "5. 📧 Envoyer par email"
  echo "6. 📋 Lister les clients"
  echo "0. 🚪 Quitter"
  echo "-------------------------------"
  read -p "👉 Choix: " CHOICE

  case "$CHOICE" in
    1)
      read -p "Nom du client à ajouter : " CLIENT
      ./add_clients.sh "$CLIENT"
      ;;
    2)
      read -p "Nom du client à supprimer : " CLIENT
      ./remove_clients.sh "$CLIENT"
      ;;
    3)
      read -p "Nom du client à bloquer temporairement : " CLIENT
      echo "⏳ Suppression temporaire..."
      ./remove_clients.sh "$CLIENT"
      echo "📝 Client bloqué. Pour le réactiver, réutilisez l'option 1."
      ;;
    4)
      read -p "Nom du client pour .ovpn : " CLIENT
      ./generate_client.sh "$CLIENT"
      ;;
    5)
      read -p "Nom du client : " CLIENT
      read -p "Adresse email destinataire : " EMAIL
      ./send_ovpn_mail.sh "$CLIENT" "$EMAIL"
      ;;
    6)
      echo "📋 Liste actuelle :"
      grep '^OPENVPN_CLIENTS=' "$ENV_FILE" | cut -d= -f2-
      ;;
    0)
      echo "👋 Au revoir."
      exit 0
      ;;
    *)
      echo "❌ Choix invalide"
      ;;
  esac
  echo ""
done
