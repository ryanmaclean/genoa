# genoa — smolBSD イメージビルド・デプロイ統合 CLI

genoa は、エージェントを組み込んだ FreeBSD / NetBSD クラウドイメージをビルドし、構造化マニフェストと検証済みビルドレシートを通じてクラウドプロバイダーへデプロイするための AX ファースト（エージェントファースト）オーケストレーションツールです。

## クイックスタート

### 1. 利用可能なプロバイダーを一覧表示する
```
nu genoa.nu catalog
```

`catalog/providers.v1.json` に登録された 40 以上のクラウドプロバイダーを、デプロイメカニズム・アーキテクチャサポート・BSD ネイティブ対応状況とともに一覧表示します。

### 2. スキーマを確認する
```
nu genoa.nu schema
```

`schema/manifest.v1.json` を出力します。これはマニフェスト TOML ファイルの JSON Schema です。エージェントはこれを使って、事前知識なしにマニフェスト構造を検出・検証できます。

### 3. マニフェストを検証する
```
nu genoa.nu validate examples/freebsd-vultr-aarch64.toml
```

12 項目のプリフライトチェックを実行します: スキーマバージョン、必須フィールド、arch/OS 列挙値、プロバイダーカタログ照合、プロファイルファイルの存在確認、エージェントソースタイプ、sha256 プレースホルダー検出。

### 4. イメージをビルドする
```
nu genoa.nu build examples/freebsd-vultr-aarch64.toml --profile uefi
```

指定したプロファイル（`uefi` / `kboot`）を実行します。FreeBSD 上では実際のディスクイメージを作成します。macOS / Linux 上では実行予定プランを出力します。常にプランだけ取得したい場合は `--dry-run` を追加してください。

### 5. デプロイする
```
VULTR_API_KEY=<key> nu genoa.nu deploy examples/freebsd-vultr-aarch64.toml
```

イメージを Vultr のスナップショット（URL 経由）としてアップロードし、準備完了までポーリングした後、インスタンスを起動します。

### 6. ワンショットパイプライン
```
nu genoa.nu run examples/freebsd-vultr-aarch64.toml
```

ビルド → パブリッシュ → デプロイを連結します。結果を統合 JSON で返します。

## コアコンセプト

**マニフェスト（TOML）:** 宣言的なイメージ仕様 — OS、カーネル、パッケージ、エージェントペイロード、ネットワーク、デプロイターゲット。スキーマ v1、`additionalProperties: false`。

**プロファイル（`uefi` / `kboot`）:** ブートローダー戦略。`uefi` = `loader.efi` + GPT ESP。`kboot` = Linux initrd 内の `loader.kboot` — ext4 のみ対応プロバイダー（Linode、旧 AWS 等）の要件を満たしながら、UFS2 上で実際の FreeBSD を動作させます。

**ビルドレシート（JSON）:** プロベナンスエンベロープ — イメージ sha256、マニフェスト sha256、エージェントソースと sha256、ビルドタイムスタンプ、ランダムな `receipt_id`。

**プロバイダーカタログ:** `catalog/providers.v1.json` に 40 エントリ。`deployment_path` フィールドがアダプタディスパッチを制御します: `rescue-dd` → `linode.nu`、`snapshot-url` → `vultr.nu`、`byoi-api` → `oci.nu`。

## リモートビルドホスト

マニフェストの `target.build_host` に設定することで、FreeBSD マシンにビルドを委譲できます:

```toml
[target]
build_host = "builder@fb-vm-24:2225"
```

genoa はマニフェストを `scp` で転送し、SSH 経由でリモートの `nu genoa.nu build` を実行して、構造化された結果を返します。

## テスト

```
nu test/smoke.nu
```

全サブコマンドをカバーする 16 項目のスモークテストを実行します。終了コード 0 = 全テスト合格。

## サブコマンド一覧

```nushell
genoa catalog                            # catalog/providers.v1.json からプロバイダーを一覧表示
genoa schema                             # マニフェストスキーマ（JSON Schema）を出力
genoa describe <manifest.toml>           # パース + 検証してプラン JSON を表示
genoa validate <manifest.toml>           # マニフェストをスキーマに対して検証し結果を返す
genoa build <manifest.toml> [--profile uefi|kboot] [--dry-run]
genoa publish <image> [--backend r2|s3|gitea]
genoa deploy <manifest.toml> --provider <id>
genoa verify <image> <receipt.json>
genoa status <receipt.json>              # ビルドレシートからデプロイ状況を表示
genoa run <manifest.toml> [--provider <id>] [--backend r2|s3|gitea] [--dry-run]
```

`run` はエンドツーエンドのパイプラインです: build → publish → deploy を連結し、統合 JSON 結果を返します。

## 関連ドキュメント

`docs/agent-port-quickstart.md` — エージェントバイナリを genoa マニフェストにパッケージングする手順。
