# ⚾ 野球 全員一致チャレンジ（オンライン）

GitHub Pages で公開する静的サイトです。複数端末の同期には **Supabase** を使用します。GitHubにアップロードするだけではオンライン対戦は動きません。

## 初回セットアップ

1. [Supabase](https://supabase.com/) でプロジェクトを作成。
2. Supabase の **SQL Editor** で `setup.sql` の全文を実行。
3. Supabase の **Project URL** と **Publishable key（または anon key）** を取得。
4. `index.html` 冒頭の次の2つの文字列を実際の値に置き換える。
   - `YOUR_SUPABASE_URL`
   - `YOUR_SUPABASE_PUBLISHABLE_KEY`
   **service_role / secret キーは絶対に使用しないでください。**
5. GitHub で新しい公開リポジトリを作成し、`index.html` と `setup.sql` をアップロード。
6. GitHub の **Settings → Pages → Build and deployment → Deploy from a branch → main / (root) → Save**。
7. 発行された `https://ユーザー名.github.io/リポジトリ名/` にアクセス。
8. ホストがルームを作り、友達にサイトURLとルームコードを送って参加してもらう。

## 注意
- 設定済みの公開用キーはブラウザから参照できますが、公開用キーはそれを前提としたものです。秘密鍵は使用しないでください。
- この試作品は2.2秒ごとの同期方式です。実機の複数端末テストは未実施です。
- 誰でもルームコードで参加できる簡易設計です。個人情報や機密情報は入力しないでください。
