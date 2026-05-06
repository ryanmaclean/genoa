# Démarrage rapide — portage d'agent

Lecteur principal : agent LLM. Structure : étapes séquentielles avec commandes exactes.

## 1. Découverte en trois appels

```
nu genoa.nu catalog
```
— liste 40+ fournisseurs, chacun avec `id`, `deployment_path`, `byoi_format`

```
nu genoa.nu schema
```
— schéma JSON complet ; analyser `properties` pour connaître tous les champs valides

```
nu genoa.nu describe examples/agent-port-template.toml
```
— résumé complet de toutes les sections du manifest et de leurs valeurs résolues, y compris les champs placeholder

## 2. Adapter le modèle

Copier `examples/agent-port-template.toml`. Modifier :
- `image.name`, `image.version`
- `image.output_dir` (répertoire de destination des artefacts, par défaut `"./out"`)
- `agent.name`, `agent.version`
- `agent.source.type` (`url` / `gitea_release` / `local_path`)
- `agent.source.url` + `sha256`
- `rc_service.name`, `rc_service.command_args`
- `network.hostname`

**Note sha256 :** définir la vraie valeur SHA-256 de votre binaire. Une valeur à zéros déclenche un avertissement.
Calculer : `sha256sum ./binary` (Linux/FreeBSD) ou `shasum -a 256 ./binary` (macOS)

## 3. Vérification pré-vol

```
nu genoa.nu validate your-agent.toml
```
Retourne : `{ valid: true, errors: [], warnings: [...] }`
`valid=false` + tableau `errors` en cas d'échec. Corriger toutes les erreurs avant de continuer.

## 4. Simulation à sec

```
nu genoa.nu build your-agent.toml --dry-run
```
Plan en 16 étapes. Vérifier l'URL de récupération (étape 3), le nom du service rc.d (étape 12).

## 5. Construction

```
nu genoa.nu build your-agent.toml
```
Nécessite un hôte de build FreeBSD. Définir `target.build_host` pour le dispatch SSH distant. Après un build distant, genoa rapatrie l'image et le reçu vers `[image].output_dir` local via SCP.

Sortie dans `[image].output_dir` (par défaut `./out`) :
```
out/<name>-<version>.raw
out/<name>-<version>.receipt.json
```

Le reçu est une enveloppe JSON de provenance v1 conforme avec des objets imbriqués : `image`, `build`, `agent`, `hashes`, `claims`. Conserver ce fichier — l'étape de déploiement le lit automatiquement.

## 6. Déploiement

```
VULTR_API_KEY=<key> nu genoa.nu deploy your-agent.toml
```
Lit l'attestation automatiquement depuis `[image].output_dir`. Retourne : `{ provider, image_id, status, receipt }`

## 7. Commande unique

```
nu genoa.nu run your-agent.toml
```
Enchaîne validate → build → publish → deploy. Code de sortie unique pour usage en CI.
