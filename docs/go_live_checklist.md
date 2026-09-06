# Hotbar 発売手順（実ID投入チェックリスト）

最終更新: 2026-09-05

Polar.sh で本番商品を作ったあと、**何をどの順で差し替えれば売れるか**の手順書。
配布前に、ここに書いてある項目をすべて解消すること。

所要時間の目安: 30〜40分（うち公証の待ち時間が約5分）。

---

## 前提: いま何が終わっていて、何が残っているか

| 項目 | 状態 |
|---|---|
| Developer ID 署名・公証・DMG 化 | ✅ 完了。`scripts/distribute.sh` 一発で公証済みDMGが出る |
| notarytool 認証情報 | ✅ 完了。キーチェーンに `hotbar-notary` プロファイル登録済み |
| ライセンス機構（トライアル/アクティベート/再検証） | ✅ 実装・テスト済み |
| Polar のサンドボックス設定 | ✅ `Config/Debug.xcconfig` に投入済み |
| Polar の**本番**設定 | ✅ `Config/Release.xcconfig` に投入済み。本番 Checkout URL の HTTP 200 を確認済み |
| ランディングページ | ⚠️ プレースホルダは4箇所。EULA / Privacy は `noindex` のまま（STEP 3） |
| EULA / プライバシーポリシー | ❌ 下書きのまま。`[ ]` が未確定（STEP 0） |
| GitHub Release v1.1.0 | ✅ `Info.plist` を 1.1.0 に統一済み（STEP 5） |

---

## STEP 0. 先に決めないといけないこと（コード作業ではない）

`docs/eula_draft.md` と `docs/privacy_draft.md` の `[ ]` を埋める。埋まっていない項目:

| ファイル:行 | 決めること |
|---|---|
| `docs/eula_draft.md:7` | 販売者名（個人事業主名 or 屋号） |
| `docs/eula_draft.md:15` | ライセンス台数（例: 台数無制限 / 3台まで） |
| `docs/eula_draft.md:36` | 返金連絡先（候補: entaku19890818@gmail.com） |
| `docs/eula_draft.md:45` | サポート窓口（GitHub Issues はリポジトリが private なので購入者からは見えない。メール推奨） |
| `docs/eula_draft.md:54` | 準拠法域（例: 日本法） |
| `docs/eula_draft.md:58` | 問い合わせ先 |
| `docs/privacy_draft.md:15` | クラッシュレポートを入れるかどうか（現状は未実装のままでよい） |
| `docs/privacy_draft.md:40` | 問い合わせメールアドレス |

**プライバシーポリシーの事実確認**: 実装は
**Mac のホスト名を送っている**。`LicenseManager.activate()` の既定引数が
`ProcessInfo.processInfo.hostName` で、それが Polar の activate API に `label` として
渡る（`Sources/Hotbar/Licensing/LicenseClient.swift:67`）。ホスト名には
「〜のMacBook Pro」のように本名が入りうる。`docs/privacy_draft.md:36` には「ライセンスキーとデバイス名
（ホスト名）を送信します」と断定形で記載済み。

埋めたら `~/repository/Hotbar-landing/public/eula.html` と `privacy.html` を再生成する
（両ファイル冒頭の警告バナーと `<meta name="robots" content="noindex">` を外すのを忘れずに）。

**ライセンス台数はコードに影響する。** 現在の実装は Polar の activation
（1インストール = 1 activation）に任せていて、アプリ側で台数を数えていない。
台数上限は Polar の商品設定側（License Key benefit の Activation limit）で決めること。

---

## STEP 1. Polar の本番設定を確認する

本番 Checkout URL は 2026-09-05 に HTTP 200 を確認済み。

差し替えるのは **`Config/Release.xcconfig` の4行だけ**。コードには一切ハードコードされていない。

```
Config/Release.xcconfig:4   POLAR_ORGANIZATION_ID = <本番の Organization ID>
Config/Release.xcconfig:5   POLAR_PRODUCT_ID      = <本番の Product ID>
Config/Release.xcconfig:6   POLAR_CHECKOUT_URL    = <本番の Checkout Link>
Config/Release.xcconfig:7   POLAR_API_BASE_URL    = https://api.polar.sh/v1
```

注意点:

- `POLAR_API_BASE_URL` は**すでに本番ホスト** (`https://api.polar.sh/v1`) を指しているので変更不要。
  サンドボックスは `https://sandbox-api.polar.sh/v1`（`Config/Debug.xcconfig`）。
- xcconfig では `//` がコメント開始として解釈されるため、URL は
  `https:/$()/api.polar.sh/v1` の形でエスケープされている。**この書き方を崩さないこと。**
- 商品には **License Key benefit を必ず付ける**。これが無いと購入者にキーが発行されず、
  アプリのアクティベート画面が永久に通らない。
- 価格は ¥1,500 買い切り（one-time）。サブスクにしないこと。

差し替えたらビルドし直す:

```bash
xcodebuild build -project Hotbar.xcodeproj -scheme Hotbar -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test  -project Hotbar.xcodeproj -scheme Hotbar -configuration Debug CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
```

---

## STEP 2. 公証済み DMG を作る

```bash
cd ~/repository/Hotbar
./scripts/distribute.sh          # バージョンは Sources/Hotbar/Info.plist から読む
```

これ一発で「アーカイブ → Developer ID 署名 → .app を公証・staple → DMG 作成 →
DMG を署名・公証・staple → 検証」まで通る。所要 5〜7分（Apple の公証待ちが大半）。

成功していれば最後にこう出る:

```
--- spctl --assess --type exec -vv (app) ---
/tmp/Hotbar-1.1.0-export/Hotbar.app: accepted
source=Notarized Developer ID
--- stapler validate (dmg) ---
The validate action worked!
```

`accepted` と `The validate action worked!` の両方が出ていなければ配らないこと。

成果物: `build/Hotbar-<version>.dmg`

### 認証情報について

キーチェーンに `hotbar-notary` プロファイルが登録済みなので、通常は何も要らない。
別のMacでやる場合は先に一度だけ:

```bash
xcrun notarytool store-credentials "hotbar-notary" \
  --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 \
  --key-id <KEYID> --issuer <ISSUER-UUID>
```

---

## STEP 3. DMG を配置し、ランディングページのプレースホルダを差し替える

DMG をどこかに置いて公開URLを得る（GitHub Release / R2 / Vercel の static など）。

そのうえで `~/repository/Hotbar-landing/public/index.html` に残る**2種類、4箇所のプレースホルダ**を置換する:

| プレースホルダ | 出現行 | 置換先 |
|---|---|---|
| `__POLAR_CHECKOUT_URL__` | 260, 318 | Polar の本番 Checkout Link |
| `__DMG_DOWNLOAD_URL__` | 262, 317 | 公証済みDMGの公開URL |

```bash
cd ~/repository/Hotbar-landing
sed -i '' 's|__POLAR_CHECKOUT_URL__|https://buy.polar.sh/XXXX|g; s|__DMG_DOWNLOAD_URL__|https://XXXX/Hotbar-1.1.0.dmg|g' public/index.html
grep -c '__' public/index.html      # 0 になること
```

スクリーンショットも入れる:

- `public/shot-overlay.png` に ⌥Tab のオーバーレイ画面を置く。
  置かなければ枠ごと自動で非表示になる（壊れた画像は出ない）ので、無くても配れるが
  **購入判断には効くので入れたほうがよい**。

デプロイ:

```bash
cd ~/repository/Hotbar-landing && vercel deploy --prod
```

---

## STEP 4. 実際に買って通しで確認する（これをやらずに告知しない）

サンドボックスでは「有効なキーで解除できる」ところまで確認できない。
**本番商品で自分で1本買って、通しで確認すること。**

1. トライアル切れを再現する
   ```bash
   defaults write com.entaku.Hotbar licenseTrialStartDate -date "$(date -v-20d '+%Y-%m-%d %H:%M:%S +0000')"
   ```
   → Hotbar を再起動して ⌥Tab → `LicenseGateView` が出ること
2. でたらめなキーを入れて**拒否される**こと（エラーメッセージが出て解除されない）
3. 購入して届いた**本物のキー**を入れて解除されること
4. 解除後に ⌥Tab でオーバーレイが出ること
5. 後片付け:
   ```bash
   defaults delete com.entaku.Hotbar licenseTrialStartDate
   ```

### ライセンス状態をリセットしたいとき

```bash
defaults delete com.entaku.Hotbar licenseKey
defaults delete com.entaku.Hotbar licenseInstanceID
defaults delete com.entaku.Hotbar licenseLastValidatedAt
defaults delete com.entaku.Hotbar licenseTrialStartDate
```

---

## STEP 5. リリース公開

GitHub Release `v1.1.0` と `Sources/Hotbar/Info.plist` のバージョンは
**1.1.0 に統一済み**。`UpdateChecker` が起動ごとに誤って更新通知を出す衝突は解消した。

公証済みの `Hotbar-1.1.0.dmg` を Release `v1.1.0` の配布アセットにすること。

---

## 触ってはいけないもの

- `Config/Release.xcconfig` の値を**コミットメッセージや issue に平文で書かない**
- `Config/Debug.xcconfig` はサンドボックスのまま置いておく。
  開発中に誤って本番決済に触れないための切り分けなので、本番値で上書きしないこと
