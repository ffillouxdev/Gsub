# Gsub sous Docker

Environnement reproductible pour ce projet de ~2022 (Python 3.9, pyhmmer/gooey
de l'époque), sans rien installer sur ta machine.

## Démarrage rapide (depuis zéro, ex. Ubuntu 24.04)

```bash
sudo apt install -y docker.io git git-lfs && sudo usermod -aG docker $USER
# (reconnexion de session pour que le groupe docker prenne effet)
git clone https://github.com/ffillouxdev/Gsub.git && cd Gsub
git lfs install && git lfs pull
docker build -t gsub:2.0.0 . && ./start_gsub.sh
```

> ⚠️ `git lfs pull` est **indispensable** : il résout `Gsub/tools/table2asn.linux`
> (~190 Mo). Sans lui, ce fichier reste un pointeur de 134 octets et l'appli
> plante à la génération des fichiers. Vérifie avec :
> `ls -lh Gsub/tools/table2asn.linux` (doit faire ~190M).
>
> Interface graphique : sur un écran local ça marche directement ; via SSH,
> connecte-toi avec `ssh -Y`.

## Construction de l'image

```bash
docker build -t gsub:2.0.0 .
# ou (si docker compose est installé) :  docker compose build
```

Le build :
- part d'une image `python:3.9-slim-bullseye` ;
- installe wxPython (interface Gooey) via les wheels précompilées de l'époque ;
- fige les dépendances Python dans `docker/requirements.lock.txt` ;
- utilise le binaire `table2asn` d'origine du projet (résolu par `git lfs pull`),
  et non une version récente : le code attend son comportement exact.

## Mode ligne de commande (recommandé, sans interface)

Gooey sait tourner sans fenêtre via `--ignore-gooey`. Un dossier `./data` est
monté dans le conteneur sur `/data`.

```bash
mkdir -p data && cp exemple/* data/     # jeu d'exemple fourni dans le repo

docker compose run --rm gsub cli \
  /data/sequence.fasta \
  /data/template.sbt \
  /data/source.tsv \
  /data/output \
  1500 \
  300 \
  --Genome Eukaryote --score 50 --evalue 0.001
```

Ordre des arguments positionnels : `Fasta Template Source Output
Min_Length_Contig Min_Length_ORF`. Les résultats (dossiers `GBF/`, `SQN/`,
rapports d'erreurs) apparaissent dans `data/output/` sur l'hôte.

## Mode interface graphique (X11, Linux)

```bash
xhost +local:docker          # autorise le conteneur à afficher sur ton écran
docker compose up gsub
xhost -local:docker          # à révoquer après usage
```

Sous Wayland, il faut Xwayland actif (généralement présent). Sous macOS/Windows,
il faut un serveur X (XQuartz / VcXsrv) et adapter la variable `DISPLAY`.

## Shell de debug

```bash
docker compose run --rm gsub bash
```

## Ajuster les versions

Toutes les versions Python sont dans `docker/requirements.lock.txt`. Si une
version pose problème au build, c'est le premier endroit à modifier.
