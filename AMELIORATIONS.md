# Pistes d'amélioration — Gsub

Ce document rassemble des pistes d'amélioration pour Gsub, sur deux axes :
les aspects **informatiques** (robustesse, qualité du code, packaging) et les
aspects **bio-informatiques** (justesse biologique de l'annotation, méthodo).

Les références de type `submission_GenBank_UI.py:422` pointent vers le code
concerné au moment de la rédaction.

---

## 1. Améliorations informatiques

### 1.1 Ne plus masquer les erreurs (priorité haute)

Le code masque systématiquement les erreurs, ce qui rend le diagnostic très
difficile (plusieurs bugs n'ont été trouvés qu'en instrumentant à la main) :

- `submission_GenBank_UI.py:422` — `subprocess.run(..., stdout=DEVNULL, stderr=subprocess.STDOUT)`
  avale toute la sortie de table2asn ; un échec passe totalement inaperçu.
- `submission_GenBank_UI.py:40` — `warnings.filterwarnings("ignore")` masque
  tous les avertissements Python.
- Aucun `check=True` sur les `subprocess.run` → un code retour non nul n'est
  jamais détecté.

**Proposition :** `subprocess.run(..., check=True, capture_output=True)` et, en
cas d'échec, remonter le `stderr` de table2asn à l'utilisateur
(« table2asn a échoué sur le contig X : … »).

### 1.2 Arguments en liste plutôt que `shell=True`

Le bug de casse sur les noms de contigs contenant des parenthèses/espaces
(corrigé par des guillemets en `submission_GenBank_UI.py:422`) et le `mkdir`
via shell dans `sort_output` (`submission_GenBank_UI.py:472`) viennent tous
deux de commandes shell construites par f-string.

**Proposition :**
- Passer une **liste d'arguments** sans `shell=True` :
  `subprocess.run([tool, "-t", template, "-i", fasta, ...])` → le problème de
  quoting disparaît par construction.
- Remplacer le `mkdir` shell par `Path.mkdir(parents=True, exist_ok=True)`.

### 1.3 Bug : collision de longueurs dans `remove_overlaps_gene`

`submission_GenBank_UI.py:149` — le dictionnaire est indexé par la **longueur**
de l'ORF :

```python
dico_length[length] = {...}
```

Si deux ORF ont exactement la même longueur, l'un écrase l'autre et un gène
disparaît silencieusement des résultats.

**Proposition :** indexer par `id_orf` (identifiant unique), pas par la longueur.

### 1.4 Résultats différents selon l'OS

`submission_GenBank_UI.py:33` et `:393-396` — l'import `pyhmmer` et la
détection de polymérase ne tournent que sous Linux ; sous **Windows**,
`dico_pol = {}` → la détection de polymérase est purement sautée, sans
avertissement. L'annotation produite dépend donc de la machine.

**Proposition :** au minimum prévenir explicitement l'utilisateur sous Windows ;
idéalement rendre la détection multi-plateforme.

### 1.5 Dépendance fragile à table2asn v1.26

Le comportement repose sur une version précise du binaire (génération
**systématique** du fichier `.val`, même vide). Une version récente (v1.29)
n'écrit le `.val` qu'en cas d'erreur → `verif_quality` plante avec
`FileNotFoundError`.

**Proposition :** rendre `verif_quality` et `sort_output` tolérants à un `.val`
absent (= aucune erreur de validation), pour découpler le code de la version du
binaire.

### 1.6 Performance : lenteur de table2asn (~76 s)

table2asn v1.26 tente des accès réseau (vérification de version + taxonomie) à
chaque contig ; dans le conteneur ces tentatives attendent un timeout avant de
retomber sur les données intégrées (~7,5 s/contig).

**Proposition (à valider) :** forcer un échec réseau immédiat plutôt qu'un
timeout — p. ex. `CONN_TIMEOUT` bas, ou mapper les hôtes NCBI vers `127.0.0.1`
via `extra_hosts` pour un refus de connexion instantané.

### 1.7 Qualité / maintenabilité

- **Aucun test.** Ajouter des tests sur `search_orf_orffinder`,
  `remove_overlaps_gene`, `parse_src_file` (avec les fichiers d'`exemple/`).
- `orf_pfam` (`submission_GenBank_UI.py:212-264`) : forte imbrication (6 niveaux)
  et duplication de la logique de mise à jour du score → extractible en un
  helper.
- Chemins non portables : `src_file.split('/')[-1]` (`:325`) → `Path(src_file).name`.
- Logging structuré (module `logging`) plutôt que des `print` colorés.

---

## 2. Améliorations bio-informatiques

Contexte supposé : annotation et soumission GenBank de **virus à ARN**,
orientée découverte (virome), avec détection de la **RdRp** par HMM.

### 2.1 Les filtres d'ORF suppriment des gènes viraux réels (priorité haute)

- **`remove_overlaps_gene`** (garder le plus long, jeter les chevauchants) : les
  ORF chevauchants sont fréquents et **réels** chez les virus (compaction
  génomique, cadres décalés). Ce filtre supprime de vrais gènes.
- **`remove_strand_gene`** (garder le brin majoritaire) : les génomes
  **ambisens** (Bunyavirales, arénavirus) et bisens codent sur les deux brins.
  Filtrer le brin minoritaire perd des gènes authentiques.

**Proposition :** désactiver ces filtres **par défaut** pour l'annotation virale
(ou au minimum les signaler), c'est-à-dire l'inverse du réglage actuel.

### 2.2 Frameshift ribosomique et polyprotéines

- Beaucoup de virus à ARN(+) expriment la **RdRp par décalage de cadre −1
  (−1 PRF)** (alphavirus, coronavirus, luteo/sobemo…). Un simple ORF-finder
  coupe alors la RdRp en deux ORF mal annotés.
- Les virus à **polyprotéine** (picorna-like, flavi-like) : un seul grand ORF
  clivé en peptides matures. Les annoter en ORF indépendants déforme la réalité
  — GenBank attend des features `mat_peptide`.

**Proposition :** gérer ces cas (au moins documenter la limite), et produire des
`mat_peptide` pour les polyprotéines.

### 2.3 S'appuyer sur l'infrastructure virale reconnue

- **VADR** est l'outil recommandé/exigé par le NCBI pour valider et annoter de
  nombreux virus. Générer les features « à la main » via table2asn risque de
  produire des enregistrements qui échouent à la validation virale NCBI.
- Pour la **RdRp** : une seule `Polymerase.hmm` maison est limitée. État de
  l'art : **Palmscan/palmprint** (motifs A-B-C conservés), **RdRp-scan**,
  **NeoRdRp** — plus sensibles pour les RdRp divergentes.
- **Seuils** : un `score`/`evalue` global sur tous les profils est grossier ;
  préférer des **seuils de gathering (GA) par profil** (façon Pfam).

### 2.4 Annotation fonctionnelle trop pauvre

Tout ce qui n'est pas polymérase → « hypothetical protein ». En scannant
**Pfam / RVDB / profils viraux** (capside, hélicase, protéase…), on donnerait de
vrais noms de produits et des enregistrements GenBank bien plus riches.

### 2.5 Contexte « découverte de virus » manquant

- **Complétude / qualité** : **CheckV** (complétude, contamination) est standard
  pour justifier une soumission.
- **Taxonomie automatique** : **geNomad**, ou Diamond vs RefSeq viral, plutôt que
  de dépendre du champ `Lineage` saisi manuellement dans le fichier source.
- **Génomes segmentés** (bunya, orthomyxo, reo) et **circulaires** : `circular`
  est codé en dur à `False` (`submission_GenBank_UI.py:416-418`) et rien ne relie
  les segments d'un même virus.

---

## Priorités suggérées

**Informatique :** 1.1 (ne plus masquer les erreurs) → 1.2 (args en liste) →
1.3 (bug de collision). Rapides et à fort impact.

**Bio-informatique :** 2.1 (ne plus jeter les ORF chevauchants/minoritaires par
défaut) → 2.2 (frameshift/polyprotéines) → 2.3 (VADR / Palmscan, plus
structurant à moyen terme).
