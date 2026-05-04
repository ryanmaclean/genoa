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

Enchaîne build → publish → deploy. Retourne un résultat JSON combiné.

## Concepts fondamentaux

**Manifest (TOML) :** spécification déclarative de l'image — OS, noyau, paquets, charge utile agent, réseau, cible de déploiement. Schéma v1, `additionalProperties: false`.

**Profil (`uefi` / `kboot`) :** stratégie de chargeur d'amorçage. `uefi` = `loader.efi` + GPT ESP. `kboot` = `loader.kboot` intégré dans un initrd Linux — satisfait les exigences des fournisseurs ext4-only (Linode, AWS legacy) tout en exécutant un vrai FreeBSD sur UFS2.

**Attestation de build (JSON) :** enveloppe de provenance — sha256 de l'image, sha256 du manifest, source de l'agent + sha256, horodatage de build, `receipt_id` aléatoire.

**Catalogue de fournisseurs :** 40 entrées dans `catalog/providers.v1.json`. Le champ `deployment_path` oriente le dispatch des adaptateurs : `rescue-dd` → `linode.nu`, `snapshot-url` → `vultr.nu`, `byoi-api` → `oci.nu`.

## Hôte de build distant

Définir `target.build_host` dans votre manifest pour déléguer les builds à une machine FreeBSD :

```toml
[target]
build_host = "builder@fb-vm-24:2225"
```

genoa transfèrera le manifest par scp, exécutera `nu genoa.nu build` à distance via SSH, et retournera le résultat structuré.

## Tests

```
nu test/smoke.nu
```

Lance 16 tests de fumée couvrant tous les sous-commandes. Code de sortie 0 = tous réussis.

## Voir aussi

`docs/agent-port-quickstart.md` — empaqueter votre binaire agent dans un manifest genoa.
