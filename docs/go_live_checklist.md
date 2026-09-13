# Hotbar 発売手順（実ID投入チェックリスト）

最終更新: 2026-09-13

Polar.sh で本番商品を作ったあと、**何をどの順で差し替えれば売れるか**の手順書。
配布前に、ここに書いてある項目をすべて解消すること。

所要時間の目安: 30〜40分（うち公証の待ち時間が約5分）。

---

## 前提: いま何が終わっていて、何が残っているか

| 項目 | 状態 |
|---|---|
| Developer ID 署名・公証・DMG 化 | ✅ 完了。`scripts/distribute.sh` 一発で公証済みDMGが出る |
| notarytool 認証情報 | ✅ `hotbar-notary` プロファイルは**生きている**（2026-09-13 に `notarytool history` が成功）。ただし **サンドボックス下のシェルからはキーチェーンが読めず失敗する** — issue #10 はその誤検知だった |
| ライセンス機構（トライアル/アクティベート/再検証） | ✅ 実装・テスト済み |
| Polar のサンドボックス設定 | ✅ `Config/Debug.xcconfig` に投入済み |
| Polar の**本番**設定 | 🔴 ID は `Config/Release.xcconfig` に投入済みで価格も ¥1,500 one_time で正しいが、**License Key benefit が未設定（`benefits: []`）＝買ってもキーが出ない**。さらに組織の事業者情報が未提出（`details_submitted_at: null`）で Payout も未完（issue #9） |
| ランディングページ | ✅ 2026-09-13 に `vercel deploy --prod` 済み。Checkout リンク・DMG リンク・規約2ページとも本番で HTTP 200（issue #11 クローズ）。`public/shot-overlay.png` のみ未設置 |
| Apple Developer Program | ✅ 有効。2026-09-06 の DMG が `stapler validate` を通過＝公証が成立している（issue #5 クローズ） |
| 決済基盤の移行 | ✅ Lemon Squeezy → Polar。旧基盤前提の issue #1 / #2 / #7 を整理し、残ブロッカーを #9 に集約 |
| EULA / プライバシーポリシー | ✅ 全13箇所確定。販売者名は **遠藤 拓也**（Developer ID の登録名 `Takuya Endo` に準拠）。`noindex` と下書きバナーを除去して公開済み（issue #4 / #7 クローズ・`ac8f551`） |
| GitHub Release v1.1.0 | ✅ 再ビルド版に差し替え済み。**リポジトリを public 化したので配布先として使える**（STEP 3） |
| 配布用 DMG | ✅ `build/Hotbar-1.1.0.dmg` を 2026-09-06 に再ビルド。公証+staple 済み・Polar本番を向いている |

---

## STEP 0. 先に決めないといけないこと（コード作業ではない）

> **規約の正本は `~/repository/Hotbar-landing/public/eula.html` / `privacy.html`。**
> `docs/eula_draft.md` / `docs/privacy_draft.md` は移行前の下書きで、**もう更新されていない**。
> 参照しないこと（Hotbar-landing `59e62c3` で 13箇所中12箇所を確定済み）。

確定済み（`59e62c3`）:

| 項目 | 入れた値 |
|---|---|
| 連絡先（4箇所） | entaku19890818@gmail.com |
| 準拠法 | 日本法 |
| ライセンス台数 | 購入者本人が所有・管理するMacであれば台数無制限 |
| サポート窓口 | GitHub Issues + メール |
| 対応OS | macOS 13.0 以降（`MACOSX_DEPLOYMENT_TARGET=13.0` で裏取り済み） |
| 返金 | 購入から14日以内・理由を問わず全額 |

**販売者名も確定済み（2026-09-13）: 遠藤 拓也**

Apple Developer Program の登録名に揃えた。個人加入は実名登録なので、これが法的な氏名にあたる。

```
$ spctl --assess --type exec -vv <Hotbar.app>
origin=Developer ID Application: Takuya Endo (4YZQY4C47E)
```

Polar の Account details（STEP 1 ③）を提出するときも**同じ名前を入れること。**
領収書の発行元と規約の表記がズレる。

> Polar の `organization.name` は `"Hotbar"` で製品名と同じだった。これを販売者名にすると
> 「Hotbar（以下「開発者」）が提供するmacOSアプリケーション「Hotbar」」となり成立しないため不採用。

**STEP 0 に残っている作業はない。**

**プライバシーポリシーの事実確認**: 実装は
**Mac のホスト名を送っている**。`LicenseManager.activate()` の既定引数が
`ProcessInfo.processInfo.hostName` で、それが Polar の activate API に `label` として
渡る（`Sources/Hotbar/Licensing/LicenseClient.swift:67`）。ホスト名には
「〜のMacBook Pro」のように本名が入りうる。`docs/privacy_draft.md:36` には「ライセンスキーとデバイス名
（ホスト名）を送信します」と断定形で記載済み。

（実施済み。`eula.html` の販売者名を置換し、両ファイルから `noindex`・`<div class="draft">` バナー・
`<blockquote>` 注記を除去してデプロイ済み。Hotbar-landing `ac8f551`）

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

### 2026-09-13 実測: 何が設定済みで、何が未設定か

本番 Checkout Link が返す公開ペイロード（`curl -sL <Checkout URL>`）から直接読めた:

| 項目 | 実測値 | 判定 |
|---|---|---|
| 価格 | `type: one_time` / `price_currency: jpy` / `price_amount: 1500` / `tax_behavior: inclusive` | ✅ |
| サブスクか | `is_recurring: false` | ✅ |
| License Key benefit | `benefits: []`（2箇所の product 表現とも空）。ペイロード全体の `license` 検索もヒット0件 | 🔴 **未設定** |
| 組織 | `name: "Hotbar"` / `status: "created"` / `details_submitted_at: null` | 🔴 **事業者情報未提出＝Payout 不可** |

> **USD 価格が併存している。** `prices` に 2026-07-17 作成の `$9.99`（usd/999）が残っており、
> 2026-09-05 追加の JPY ¥1,500 と2本立て。現在の Checkout は JPY を選んでいるので実害はないが、
> 規約は「¥1,500」としか書いていないので、表記を揃えるか USD 価格を archive すること。

この3つを調べるのに**ダッシュボードへのログインは不要**（上の curl だけで分かる）。
設定を変えたあとの答え合わせも同じ方法でできる。

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

> **注意: サンドボックス下では見えない。**
> notarytool はプロファイルを data-protection keychain に置くため、
> `security dump-keychain | grep notary` には**出てこないのが正常**。存在確認は必ず
> `xcrun notarytool history --keychain-profile hotbar-notary` で行うこと。
> また、サンドボックス付きのシェル（エージェントの既定実行環境など）ではキーチェーンに
> アクセスできず `No Keychain password item found` になる。`distribute.sh` は
> **サンドボックスなしのシェルから実行すること**。

別のMacでやる場合は先に一度だけ:

```bash
xcrun notarytool store-credentials "hotbar-notary" \
  --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 \
  --key-id <KEYID> --issuer <ISSUER-UUID>
```

---

## STEP 3. DMG を配置し、ランディングページのプレースホルダを差し替える

### 配布先: GitHub Release（リポジトリを public 化して確定）

2026-09-06 にリポジトリを **public** にした。これで Release アセットが
認証なしでダウンロードできる。

```
$ curl -o /dev/null -w '%{http_code}' -L \
    https://github.com/entaku0818/Hotbar/releases/download/v1.1.0/Hotbar-1.1.0.dmg
200
$ curl -o /dev/null -w '%{http_code}' \
    https://api.github.com/repos/entaku0818/Hotbar/releases/latest
200
```

**DMG の公開URL**（ランディングの `__DMG_DOWNLOAD_URL__` に入れる値）:

```
https://github.com/entaku0818/Hotbar/releases/download/v1.1.0/Hotbar-1.1.0.dmg
```

配信されているのが再ビルド版であることは Content-Length で確認済み（655,663 bytes、手元と一致）。

#### public 化にあたって確認したこと

41コミットの全履歴を秘密情報パターンで走査し、**APIキー・トークン・秘密鍵は0件**だった。

- Lemon Squeezy 時代の残骸は Store ID / Product ID の数値のみ。APIキーは含まれていない
- Polar の値は Organization / Product の UUID と、公開前提の Checkout URL
- notarytool の認証情報はキーチェーン管理で、ドキュメント上は `AuthKey_XXXXXXXXXX` 等の伏せ字のみ

**引き換えに、ライセンス検証の実装（`Sources/Hotbar/Licensing/` 4ファイル・423行）が公開される。**
解除ロジックが読める前提で、今後ライセンス周りを変更すること。

#### UpdateChecker も本番で動くようになった

private の間は `UpdateChecker` が叩く `api.github.com/.../releases/latest` が
未認証で404になり、更新通知は一度も出ていなかった（`UpdateChecker.swift:21`）。
public 化で解消。

> したがって、以前この手順書にあった「1.0.0 を配ると毎起動で更新通知が出る」は
> **private の間は起きなかった**。今後は実際に効くので、
> リリースのたびに `Info.plist` と Release タグを揃えること。

---

### 置換作業 — ✅ 完了・本番反映済み（2026-09-13, Hotbar-landing `ac8f551`）

> **2026-09-13 に `vercel deploy --prod` を実行し、本番へ出た。**
> それまで本番は購入導線が入る前の旧ビルドで、`/eula.html` は 404 だった（issue #11）。
>
> ```
> $ curl -s https://hotbar-landing.vercel.app/ | grep -oE 'href="[^"]*"' | sort -u
> href="/eula.html"
> href="/icon.png"
> href="/privacy.html"
> href="https://buy.polar.sh/polar_cl_..."
> href="https://github.com/entaku0818/Hotbar/releases/download/v1.1.0/Hotbar-1.1.0.dmg"
> href="mailto:entaku19890818@gmail.com"
> $ curl -s -o /dev/null -w '%{http_code}' https://hotbar-landing.vercel.app/eula.html
> 200
> ```
>
> **教訓: コミットしただけでは世に出ない。** ランディングを触ったら必ず本番URLを
> `curl` で叩いて確認すること。手順書が「✅ 完了」と書いていたのはローカルの話で、
> 実際には購入導線の無い旧ビルドを配信し続けていた。


`~/repository/Hotbar-landing/public/index.html` の**2種類、4箇所**を実URLに置換済み。
残プレースホルダは 0、両URLとも HTTP 200 を確認済み。目印の `<!-- PLACEHOLDER -->` コメントも除去した。

| プレースホルダ | 入れた値 |
|---|---|
| `__POLAR_CHECKOUT_URL__`（2箇所） | `https://buy.polar.sh/polar_cl_iUxD54IxQTe3c47adVIaG0EyfUutyG3fmJkzN0kxyRB`（= `Config/Release.xcconfig` と同一） |
| `__DMG_DOWNLOAD_URL__`（2箇所） | `https://github.com/entaku0818/Hotbar/releases/download/v1.1.0/Hotbar-1.1.0.dmg` |

Checkout URL はアプリ内購入導線と同じ値なので、**Release.xcconfig を変えたらランディングも一緒に直すこと**。
DMG URL はバージョン固定なので、v1.1.1 を出したらここも上げる（`releases/latest/download/` に
しなかったのは、公証済みでない中間リリースを踏ませないため）。

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

### バージョンの統一は完了している

`Info.plist` を **1.1.0** に上げて、公開中の Release タグ `v1.1.0` と揃えた（`407be3d`）。
`SemanticVersion.isNewer` は厳密な `>` 比較なので、`v1.1.0` と `1.1.0` では
`.upToDate` になり「更新があります」は出ない（`UpdateChecker.swift:45-55`）。

### 古いアセットは差し替え済み

Release `v1.1.0` には Lemon Squeezy 時代のDMG（2026-07-03公開・589,295 bytes）が
ぶら下がったままだった。Polar への移行コミット `33a7075` は 2026-07-18 なので、
中身は**もう使っていない決済基盤を叩く**ものだった。ダウンロード数 0 のうちに差し替え済み。

```bash
gh release upload v1.1.0 build/Hotbar-1.1.0.dmg --clobber -R entaku0818/Hotbar
# → Hotbar-1.1.0.dmg  655,663 bytes  2026-09-06 更新
```

リポジトリを public 化したので、このアセットがそのまま配布物になる（STEP 3 参照）。

### ローカルに残っている古いDMGに注意

`build/Hotbar-1.1.0.dmg.stale-20260829` は **2026-08-29 15:56 のビルド**で、
ライセンス強化コミット `778c76a`（同日 16:01）より前のもの。
バイナリに `licenseLastValidatedAt` が入っておらず、
**`defaults write com.entaku.Hotbar licenseKey any` で恒久的に解除できてしまう版**。
公証も staple も通るので、見た目では正しいDMGと区別がつかない。**配らないこと。**

配る DMG が正しいかは、これで確かめられる:

```bash
mnt=$(hdiutil attach -nobrowse -readonly build/Hotbar-1.1.0.dmg | grep -o '/Volumes/.*')
strings "$mnt/Hotbar.app/Contents/MacOS/Hotbar" | grep -c licenseLastValidatedAt  # 0 なら配らない
strings "$mnt/Hotbar.app/Contents/MacOS/Hotbar" | grep -o 'sandbox-api\.polar\.sh' # 出たら配らない
hdiutil detach "$mnt"
```

---

## 触ってはいけないもの

- `Config/Release.xcconfig` の値を**コミットメッセージや issue に平文で書かない**
- `Config/Debug.xcconfig` はサンドボックスのまま置いておく。
  開発中に誤って本番決済に触れないための切り分けなので、本番値で上書きしないこと
