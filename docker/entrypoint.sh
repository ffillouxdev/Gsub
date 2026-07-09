#!/usr/bin/env bash
# Point d'entrée Gsub.
#   gui  (defaut) -> lance l'interface graphique Gooey (necessite X11, cf README.docker.md)
#   cli  ...      -> lance en mode ligne de commande, sans interface (--ignore-gooey)
#   bash / shell  -> ouvre un shell dans le conteneur
set -euo pipefail

SCRIPT=/opt/gsub/Gsub/submission_GenBank_UI.py

# Empeche GTK d'utiliser le portail xdg (via D-Bus) pour les selecteurs de
# fichiers : sinon "Browse" se fige dans un conteneur sans bureau.
export GTK_USE_PORTAL=0
export NO_AT_BRIDGE=1

case "${1:-gui}" in
  gui)
    # dbus-run-session cree une session D-Bus privee, indispensable pour que
    # le selecteur de fichiers de GTK fonctionne dans le conteneur.
    exec dbus-run-session -- python "$SCRIPT"
    ;;
  cli)
    shift
    # "Files options" est le sous-parseur ; les positionnels suivent :
    #   Fasta Template Source Output Min_Length_Contig Min_Length_ORF [options]
    exec python "$SCRIPT" --ignore-gooey "Files options" "$@"
    ;;
  bash|sh|shell)
    exec /bin/bash
    ;;
  *)
    # Passthrough : tout autre argument est transmis tel quel au script.
    exec python "$SCRIPT" "$@"
    ;;
esac
