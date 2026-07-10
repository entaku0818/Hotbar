# Hotbar

macOS用のウィンドウスイッチャーです。ホットキーでウィンドウ一覧を呼び出し、キーボードだけで目的のウィンドウに切り替えられます。

## 対応OS

- macOS 13.0 (Ventura) 以降
- Apple Silicon / Intel 両対応

## インストール

1. [Releases](https://github.com/entaku0818/Hotbar/releases) から最新の `Hotbar-x.x.x.dmg` をダウンロード
2. DMGを開き、`Hotbar.app` を `アプリケーション` フォルダにドラッグ
3. `Hotbar.app` を起動
4. 初回起動時にアクセシビリティ権限の許可を求められるので、案内に従って許可する(詳細は下記)
5. デフォルトのホットキー `⌥ Tab`(Optionキーを押しながらTab)でウィンドウ一覧を開けます

Hotbarはメニューバーアプリとして常駐します(Dockには表示されません)。ホットキーや外観はメニューバーアイコンから「設定」を開いて変更できます。

## アクセシビリティ権限について

Hotbarは他のアプリのウィンドウ一覧を取得し、選択したウィンドウを最前面に切り替えるために、macOSの**アクセシビリティ(Accessibility)権限**を必要とします。

- **なぜ必要か**: ウィンドウの切り替え自体がmacOSの制限された領域の操作であり、これを行うにはAccessibility APIを使う以外の方法がありません。ホットキーのグローバル検知や、他アプリのウィンドウをアクティブ化する処理にこの権限を使用しています
- **権限が無い場合**: ウィンドウの切り替え機能は動作しませんが、それ以外の部分でアプリがクラッシュしたり不安定になることはありません
- **許可方法**: 「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」でHotbarをオンにしてください。権限設定後にHotbarの再起動が必要な場合があります
- 加えて、ウィンドウのサムネイル表示(任意機能)には「画面録画」権限を使用します。この権限を許可しない場合もサムネイルなしでウィンドウ切り替え自体は利用できます

Hotbarはアクセシビリティ/画面録画のいずれの権限で取得した情報も外部に送信しません。すべてローカルで処理されます。

## ビルド方法(開発者向け)

```bash
xcodebuild build -project Hotbar.xcodeproj -scheme Hotbar -configuration Debug CODE_SIGNING_ALLOWED=NO
```

テストの実行:

```bash
xcodebuild test -project Hotbar.xcodeproj -scheme Hotbar -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## サポート

不具合や要望は [GitHub Issues](https://github.com/entaku0818/Hotbar/issues) で受け付けています。
