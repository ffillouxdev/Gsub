# Gsub — environnement reproductible pour un projet de ~2022 (Python 3.9)
# Base Debian bullseye : c'est la seule sur laquelle wxPython (requis par Gooey)
# dispose de wheels précompilées, ce qui évite une compilation GTK interminable.
FROM python:3.9-slim-bullseye

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# --- Dépendances système ---
#  * GTK / libSDL / etc. : runtime de wxPython (l'interface Gooey)
#  * libgomp1, libidn11 : requis par le binaire table2asn de NCBI
#  * ca-certificates, wget : téléchargement de table2asn
#  * gosu, passwd : abandon des privilèges root vers l'utilisateur hôte
#    (fichiers générés dans /data appartenant à l'utilisateur, cf entrypoint.sh)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget \
        gosu passwd \
        libgtk-3-0 libgomp1 libidn11 \
        libsdl2-2.0-0 libnotify4 libsm6 libxxf86vm1 libgl1 \
        libpng16-16 libjpeg62-turbo libtiff5 \
        libxtst6 libxext6 libx11-6 libxrender1 libxi6 \
        libxrandr2 libxcursor1 libxinerama1 libxdamage1 \
        libxcomposite1 libxfixes3 xauth \
        libpcre2-32-0 libegl1 \
        libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
        libjavascriptcoregtk-4.0-18 libwebkit2gtk-4.0-37 \
        dbus dbus-x11 libcanberra-gtk3-module \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/gsub

# --- Dépendances Python figées à l'époque du projet (mai 2022) ---
# wxPython vient de l'index de wheels prébuildées de l'époque (debian-11).
COPY docker/requirements.lock.txt /tmp/requirements.lock.txt
RUN pip install --retries 10 --timeout 120 --upgrade "pip<24" "setuptools<66" wheel \
    && pip install --retries 10 --timeout 120 \
        -f https://extras.wxpython.org/wxPython4/extras/linux/gtk3/debian-11/ \
        -r /tmp/requirements.lock.txt

# --- Code du projet (inclut table2asn.linux d'origine, résolu depuis git-lfs) ---
# On utilise le binaire table2asn livré par l'auteur (v1.26.678, ~2022) plutôt
# qu'une version récente : le code attend son comportement exact (génération
# systématique du fichier .val de validation, même vide).
COPY . /opt/gsub
RUN chmod +x /opt/gsub/Gsub/tools/table2asn.linux \
    && cp /opt/gsub/Gsub/tools/table2asn.linux /opt/gsub/Gsub/tools/tbl2asn.linux

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["gui"]
