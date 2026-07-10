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

# --- Abandon des privileges root -------------------------------------------
# Le conteneur demarre en root, mais on veut que les fichiers ecrits dans le
# volume /data appartiennent a l'utilisateur HOTE (pas a root). On determine
# son UID/GID puis on relance l'appli sous cette identite avec gosu.
#
# Source de l'UID/GID, par ordre de priorite :
#   1. les variables HOST_UID / HOST_GID (passees par le lanceur)
#   2. le proprietaire du volume /data monte (il porte l'identite de l'hote)
#   3. a defaut : on reste root (ancien comportement)
EXEC_PREFIX=()
if [ "$(id -u)" = "0" ]; then
  if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
    TARGET_UID="$HOST_UID"; TARGET_GID="$HOST_GID"
  elif [ -d /data ]; then
    TARGET_UID="$(stat -c '%u' /data)"; TARGET_GID="$(stat -c '%g' /data)"
  else
    TARGET_UID=0; TARGET_GID=0
  fi

  if [ "$TARGET_UID" != "0" ]; then
    # Cree groupe et utilisateur correspondants (idempotent, -o autorise un
    # UID/GID deja existant).
    getent group "$TARGET_GID" >/dev/null 2>&1 || groupadd -o -g "$TARGET_GID" gsub
    getent passwd "$TARGET_UID" >/dev/null 2>&1 || \
      useradd -o -u "$TARGET_UID" -g "$TARGET_GID" -m -d /home/gsub -s /bin/bash gsub
    # HOME accessible en ecriture : indispensable pour dbus / GTK.
    HOME_DIR="$(getent passwd "$TARGET_UID" | cut -d: -f6)"
    export HOME="${HOME_DIR:-/home/gsub}"
    mkdir -p "$HOME"
    chown "$TARGET_UID:$TARGET_GID" "$HOME"
    EXEC_PREFIX=(gosu "$TARGET_UID:$TARGET_GID")
  fi
fi

# Lance $@ sous l'identite cible (ou tel quel si on reste root).
run() {
  if [ "${#EXEC_PREFIX[@]}" -gt 0 ]; then
    exec "${EXEC_PREFIX[@]}" "$@"
  else
    exec "$@"
  fi
}

case "${1:-gui}" in
  gui)
    # dbus-run-session cree une session D-Bus privee, indispensable pour que
    # le selecteur de fichiers de GTK fonctionne dans le conteneur.
    run dbus-run-session -- python "$SCRIPT"
    ;;
  cli)
    shift
    # "Files options" est le sous-parseur ; les positionnels suivent :
    #   Fasta Template Source Output Min_Length_Contig Min_Length_ORF [options]
    run python "$SCRIPT" --ignore-gooey "Files options" "$@"
    ;;
  bash|sh|shell)
    run /bin/bash
    ;;
  *)
    # Passthrough : tout autre argument est transmis tel quel au script.
    run python "$SCRIPT" "$@"
    ;;
esac
