# genoa — interface CLI unifiée pour la construction et le déploiement d'images smolBSD

genoa est un outil d'orchestration AX-first (agent en priorité) pour construire des images cloud FreeBSD et NetBSD avec des agents embarqués, puis les expédier vers des fournisseurs cloud via des manifests structurés et des attestations vérifiées.

## Démarrage rapide

### 1. Lister les fournisseurs disponibles
```
nu genoa.nu catalog
```

Liste l'ensemble des 40+ fournisseurs cloud supportés depuis `catalog/providers.v1.json`, avec les mécanismes de déploiement, la compatibilité d'architecture et les capacités natives BSD.

### 2. Inspecter le schéma
```
nu genoa.nu schema
```

Affiche `schema/manifest.v1.json` — le schéma JSON pour les fichiers TOML de manifest. Les agents l'utilisent pour découvrir et valider la structure d'un manifest sans connaissance préalable.

### 3. Valider un manifest
```
nu genoa.nu validate examples/freebsd-vultr-aarch64.toml
```

Effectue 12 vérifications pré-vol : version du schéma, champs requis, enum arch/OS, consultation du catalogue de fournisseurs, existence du fichier de profil, type de source de l'agent, détection de placeholder sha256.

### 4. Construire une image
```
nu genoa.nu build examples/freebsd-vultr-aarch64.toml --profile uefi
```

Exécute le profil (`uefi` / `kboot`). Sur FreeBSD : création réelle d'image disque. Sur macOS/Linux : émet un plan would-run. Ajouter `--dry-run` pour toujours obtenir le plan.

### 5. Déployer
```
VULTR_API_KEY=<key> nu genoa.nu deploy examples/freebsd-vultr-aarch64.toml
```

Téléverse l'image en tant que snapshot Vultr depuis une URL, attend la disponibilité, puis lance l'instance.

### 6. Pipeline en une seule commande
```
nu genoa.nu run examples/freebsd-vultr-aarch64.toml
```

Enchaîne validate → build → publish → deploy. Retourne un résultat JSON combiné.

## Concepts fondamentaux

**Manifest (TOML) :** spécification déclarative de l'image — OS, noyau, paquets, charge utile agent, réseau, cible de déploiement. Schéma v1, `additionalProperties: false`.

**Profil (`uefi` / `kboot`) :** stratégie de chargeur d'amorçage. `uefi` = `loader.efi` + GPT ESP. `kboot` = `loader.kboot` intégré dans un initrd Linux — satisfait les exigences des fournisseurs ext4-only (Linode, AWS legacy) tout en exécutant un vrai FreeBSD sur UFS2.

**Attestation de build / Reçu (JSON) :** enveloppe de provenance v1 conforme, structurée en objets imbriqués : `image`, `build`, `agent`, `hashes`, `claims`. Contient sha256 de l'image, sha256 du manifest, source de l'agent + sha256, horodatage de build, `receipt_id` aléatoire, et un tableau de claims vérifiables pour intégration fleet-eval.

**Signature :** si `signing.tool = "signify"` est défini dans le manifest, genoa lit la configuration de signature et signe l'image à l'issue du build. La signature est fonctionnelle — elle n'est pas un simple champ réservé.

**Répertoire de sortie :** `image.output_dir` (valeur par défaut : `"./out"`) détermine l'emplacement des artefacts produits. L'image brute et le reçu JSON y sont écrits après un build réussi.

**Catalogue de fournisseurs :** 40 entrées dans `catalog/providers.v1.json`. Le champ `deployment_path` oriente le dispatch des adaptateurs : `rescue-dd` → `linode.nu`, `snapshot-url` → `vultr.nu`, `byoi-api` → `oci.nu`.

## Hôte de build distant

Définir `target.build_host` dans votre manifest pour déléguer les builds à une machine FreeBSD :

```toml
[target]
build_host = "builder@fb-vm-24:2225"
```

genoa transfèrera le manifest par SCP, exécutera `nu genoa.nu build` à distance via SSH, puis rapatriera l'image et le reçu vers le répertoire `[image].output_dir` local (par défaut `./out`) via SCP.

## Tests

```
nu test/smoke.nu
```

Lance 16 tests de fumée couvrant tous les sous-commandes. Code de sortie 0 = tous réussis.

## Sous-commandes

```nushell
genoa catalog                            # Lister les fournisseurs depuis catalog/providers.v1.json
genoa schema                             # Afficher le schéma du manifest (JSON Schema)
genoa describe <manifest.toml>           # Parser le manifest, afficher le résumé complet de toutes les sections et leurs valeurs résolues
genoa validate <manifest.toml>           # Valider le manifest contre le schéma, retourner les résultats
genoa build <manifest.toml> [--profile uefi|kboot] [--dry-run]
genoa publish <image> [--backend r2|s3|gitea]
genoa deploy <manifest.toml> --provider <id>
genoa verify <image> <receipt.json>
genoa status [--dir <chemin>]            # Scanner les reçus, retourner un résumé agrégé des builds
genoa run <manifest.toml> [--provider <id>] [--backend r2|s3|gitea] [--dry-run]
```

`run` est le pipeline complet : validate → build → publish → deploy, retournant un résultat JSON combiné.

## Voir aussi

`docs/agent-port-quickstart.md` — empaqueter votre binaire agent dans un manifest genoa.
