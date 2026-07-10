# Hotbar 有料販売化 Step 1 調査報告

## ⚠️ 最重要: ビルドが壊れています(未コミット状態で修正済み)

- `bdd6078`(AltTab風設定機能追加, 2026-07-04)で新規追加した `AppSettings.swift` が `project.pbxproj` のターゲットに登録されておらず、それ以降の**直近7コミット(v1.1.0リリースコミット含む)でCIが全て失敗**している(`gh run list`で確認)
- ローカルで再現・検証済み: 作業ツリーの未コミット差分(`project.pbxproj`への`AppSettings.swift`追加)を`git stash`で外すと`xcodebuild build`が失敗、戻すと成功
- つまり**現在のワーキングツリーには修正が既に存在するが、コミットされていない**。GitHub Release v1.1.0のDMGがどうやってビルドされたか(Xcode GUIでローカルの別状態からビルドした可能性)を本人に確認する必要あり
- 対応: この`project.pbxproj`の差分をコミットしてCIが green になることを確認するのが最優先

## (1) 現状把握

- リポジトリはv0.1.0だけでなく**既にv1.1.0まで進行・GitHub Releaseも公開済み**(2026-07-03)。「v0.1.0リリース済み」という前提は古い
- 配布形態: Developer ID + 公証+ DMG(`scripts/distribute.sh`が実装済み、`ExportOptions.plist`は`method: developer-id`, Team ID `4YZQY4C47E`)。`build/`に1.0.0・1.1.0のDMGが既に存在
- **決済/ライセンス機構は皆無**(Gumroad/LemonSqueezy/StoreKit/license関連の文字列を全文検索してもゼロ件) — 「お金を払って購入」の導線は現状ゼロから
- TestFlight関連ファイル(Fastfile, Appfile等)は存在せず、TestFlightに向けた作業は着手されていない((2)参照、そもそも今の設計では不要な可能性が高い)
- README/CHANGELOG/LICENSE等のドキュメントは一切なし
- Appアイコン: `AppIcon.appiconset`はスロット定義のみで**実画像ファイルが0個**(空)
- GitHub Issues/PRはオープン0件 — 残タスクは何もトラッキングされていない

## (2) 配布経路の技術判断: Developer ID + 公証 + 外部決済を推奨

- Hotbarのコア機能(他アプリのウィンドウ列挙/アクティブ化のためのAccessibility API、グローバルホットキー用CGEventTap、`NSAppleScript`経由のSystem Events操作、ScreenCaptureKitでのサムネイル取得)は**すべてApp Sandbox非互換**
- 根拠: `Hotbar.entitlements`は既に`com.apple.security.app-sandbox = false`と明示されており、開発時点で「サンドボックスでは動かない」という判断がすでに下されている(再確認済み)
- Mac App Storeはこの種のシステムユーティリティに対する例外カテゴリを持たず、AltTab/Rectangle/BetterTouchToolなど同種アプリも全てMAS外配布
- **結論**: Developer ID配布を継続。理由は技術的整合性に加え、配布パイプライン(`distribute.sh`, `ExportOptions.plist`)が既にこの前提で構築済みで手戻りがほぼゼロ
- **TestFlightは使えない**: TestFlightはApp Store提供アプリ専用の仕組みのため、Developer ID配布では原理的に利用不可。実機ベータテストが必要な場合はDMGを直接配って検証する形になる(「TestFlight予定だったはず」という認識は、この技術的制約とは矛盾するため要確認)

## (3) 「購入可能」までの残作業リスト(検証方法つき)

1. **ビルド修復のコミット** — `project.pbxproj`の差分をコミット / 検証: CIの`build-and-test`がgreenになる
2. **クリーンな署名・公証済みビルドの再作成** — (1)修復後に`distribute.sh`を実行 / 検証: `spctl --assess --type exec -vv`が"accepted"、`stapler validate`成功、開発ツールなしの別MacでGatekeeper警告なしに起動
3. **アプリアイコンの追加** — 現在空の`AppIcon.appiconset`に全サイズの画像を追加 / 検証: Dock/Finder/DMGでデフォルトアイコンでなく独自アイコンが表示される
4. **ライセンス/決済ゲートの実装** — トライアル方式か買い切りかを決め、Gumroad/Lemon SqueezyのLicense検証APIを組み込む / 検証: 未ライセンス版でゲートが出る、有効なテストライセンスキーで解除、無効キーは拒否される
5. **販売ページの作成** — Gumroad or Lemon Squeezyで価格・説明・スクリーンショット・DMG配布を設定 / 検証: テスト購入(サンドボックスまたは$0クーポン)が完了し、DMG+ライセンスキーが届く一連の流れが通る
6. **ランディングページ/サポート窓口** — スクショ、対応OS(macOS 13+)、サポート連絡先を明記 / 検証: 公開URLが存在し購入前に必要情報が揃っている
7. **法的基本文書** — 簡易プライバシー説明(Accessibility権限で何を取得/取得しないか、ローカル保存のみ等)、簡易EULA/販売規約 / 検証: 決済プラットフォームの公開必須項目が全て入力済み
8. **アップデート手段** — MAS外のため自動更新の仕組み(Sparkle導入 or GitHub Releasesへの手動確認リンク)が必要 / 検証: 新バージョン公開後、既存ユーザーが更新方法を迷わず実行できる
9. **README整備** — インストール手順・Accessibility権限を求める理由の説明 / 検証: GitHub上でREADMEが表示され、購入者が読んでセットアップできる

## (4) 人間にしか決められない項目

- 価格設定(買い切り額 or サブスク、金額)
- 決済プラットフォームの選定・アカウント開設(Gumroad vs Lemon Squeezy — 手数料・税務/VAT対応・振込先国)
- Apple Developer Program(Team ID `4YZQY4C47E`)が現在有効(年会費$99支払い済み)かどうかの確認 — 公証にはアクティブな会員資格が必須
- トライアル期間の有無・長さ、ライセンスキー方式の採否
- サポート窓口・返金ポリシー
- ローンチタイミングと告知先
