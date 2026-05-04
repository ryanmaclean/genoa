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
— résumé résolu du manifest

## 2. Adapter le modèle

Copier `examples/agent-port-template.toml`. Modifier :
- `image.name`, `image.version`
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
Nécessite un hôte de build FreeBSD. Définir `target.build_host` pour le dispatch SSH distant.
Sortie : `out/<name>-<version>.raw` + `out/<name>-<version>.receipt.json`

## 6. Déploiement

```
VULTR_API_KEY=<key> nu genoa.nu deploy your-agent.toml
```
Lit l'attestation automatiquement. Retourne : `{ provider, image_id, status, receipt }`

## 7. Commande unique

```
nu genoa.nu run your-agent.toml
```
Enchaîne build → publish → deploy. Code de sortie unique pour usage en CI.
