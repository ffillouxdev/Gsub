#!/usr/bin/env bash
# Lance Gsub et son interface graphique dans Docker.
#   ./start_gsub.sh
# Construit l'image au premier lancement, puis affiche l'interface.
# Fonctionne en local ET via une session SSH (X11 forwarding : ssh -X / -Y).
set -euo pipefail

cd "$(dirname "$0")"
IMAGE="gsub:2.0.0"

# Ajoute sudo si l'utilisateur n'est pas dans le groupe docker.
if docker info >/dev/null 2>&1; then DOCKER="docker"; else DOCKER="sudo docker"; fi

# Construit l'image si elle n'existe pas encore.
if ! $DOCKER image inspect "$IMAGE" >/dev/null 2>&1; then
  echo ">> Premier lancement : construction de l'image (quelques minutes)..."
  $DOCKER build -t "$IMAGE" .
fi

if [ -z "${DISPLAY:-}" ]; then
  echo "!! DISPLAY vide. En SSH, connecte-toi avec 'ssh -X' (ou -Y) puis relance." >&2
  exit 1
fi

mkdir -p data
RUN_ARGS=(--rm -it -e "DISPLAY=$DISPLAY" -v "$PWD/data":/data)

case "$DISPLAY" in
  :*)
    # Affichage local : partage du socket X11 Unix.
    xhost +local:docker >/dev/null 2>&1 || true
    RUN_ARGS+=(-v /tmp/.X11-unix:/tmp/.X11-unix:rw)
    ;;
  *)
    # Affichage distant (SSH X11 forwarding) : réseau hôte + cookie Xauthority.
    # On copie le cookie dans un fichier lisible et on le monte dans le conteneur.
    XAUTH="$(mktemp)"
    xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' | xauth -f "$XAUTH" nmerge - 2>/dev/null || true
    chmod 644 "$XAUTH"
    RUN_ARGS+=(--network host -e "XAUTHORITY=/tmp/.docker.xauth" -v "$XAUTH":/tmp/.docker.xauth:ro)
    ;;
esac

$DOCKER run "${RUN_ARGS[@]}" "$IMAGE" gui

case "$DISPLAY" in :*) xhost -local:docker >/dev/null 2>&1 || true ;; esac
