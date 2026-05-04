# エージェントポート クイックスタート

主な読者: LLM エージェント。構成: 正確なコマンドを伴う順次ステップ。

## 1. 3 コールによるディスカバリー

```
nu genoa.nu catalog
```
40 以上のプロバイダーを一覧表示します。各エントリには `id`、`deployment_path`、`byoi_format` が含まれます。

```
nu genoa.nu schema
```
完全な JSON Schema を出力します。`properties` をパースして全有効フィールドを確認します。

```
nu genoa.nu describe examples/agent-port-template.toml
```
解決済みマニフェストのサマリーを表示します。

## 2. テンプレートを修正する

`examples/agent-port-template.toml` をコピーして以下を変更します:
- `image.name`、`image.version`
- `agent.name`、`agent.version`
- `agent.source.type`（`url` / `gitea_release` / `local_path`）
- `agent.source.url` と `sha256`
- `rc_service.name`、`rc_service.command_args`
- `network.hostname`

**sha256 について:** バイナリの実際の SHA-256 を設定してください。全ゼロ値は警告を発生させます。  
計算方法: `sha256sum ./binary`（Linux / FreeBSD）または `shasum -a 256 ./binary`（macOS）

## 3. プリフライトチェック

```
nu genoa.nu validate your-agent.toml
```
返却値: `{ valid: true, errors: [], warnings: [...] }`  
失敗時は `valid=false` とエラー配列が返されます。次の手順に進む前に全エラーを修正してください。

## 4. ドライラン

```
nu genoa.nu build your-agent.toml --dry-run
```
16 ステップのプランを出力します。フェッチ URL（ステップ 3）と rc.d サービス名（ステップ 12）を確認してください。

## 5. ビルド

```
nu genoa.nu build your-agent.toml
```
FreeBSD ビルドホストが必要です。リモート SSH ディスパッチには `target.build_host` を設定してください。  
出力: `out/<name>-<version>.raw` と `out/<name>-<version>.receipt.json`

## 6. デプロイ

```
VULTR_API_KEY=<key> nu genoa.nu deploy your-agent.toml
```
ビルドレシートを自動的に読み込みます。返却値: `{ provider, image_id, status, receipt }`

## 7. ワンショット

```
nu genoa.nu run your-agent.toml
```
ビルド → パブリッシュ → デプロイを連結します。CI 向けに単一の終了コードを返します。
