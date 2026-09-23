# Publish the QRide admin website

The admin site is the **same Flutter app** in a browser. Hosting is “static files,” but login, map, and live GPS still talk to **Supabase**.

You do **not** need Next.js.

## 1. Build

```bash
cd flutter_application_1
flutter pub get
flutter build web --release --no-web-resources-cdn
```

`--no-web-resources-cdn` ships CanvasKit with the site so Chrome does not need `gstatic.com` (that CDN is what caused `Failed to fetch … canvaskit.js`).

Output folder: `flutter_application_1/build/web`

## 2. Put it on the internet (pick one)

### Netlify (simple)

1. Sign up at [netlify.com](https://www.netlify.com).
2. **Add new site → Deploy manually**.
3. Drag the `build/web` folder onto the page.
4. Netlify gives a URL like `https://random-name.netlify.app`.

Or connect the GitHub repo and set:

- Build command: `cd flutter_application_1 && flutter build web --release --no-web-resources-cdn`
- Publish directory: `flutter_application_1/build/web`  
  (Netlify must have Flutter in CI, or keep using drag-and-drop.)

### Firebase Hosting

```bash
npm install -g firebase-tools
firebase login
cd flutter_application_1
firebase init hosting
```

Set public directory to `build/web`, then:

```bash
flutter build web --release --no-web-resources-cdn
firebase deploy
```

### Vercel (no Next.js)

Vercel does not include the Flutter SDK. Build locally, then upload the static `build/web` folder.

```bash
cd flutter_application_1
flutter pub get
flutter build web --release --no-web-resources-cdn
npx vercel --prod --cwd build/web
```

The first time, Vercel will ask you to log in and pick a team/project. You get a URL like `https://something.vercel.app`.

After it is live, add that hostname (no `https://`) to your CARTO basemap key domains, or request a new key that includes it, then rebuild and redeploy if the map shows **API KEY REQUIRED**.

To update the site later, run the same three commands again.

## 3. Use it

Open the URL → **log in as an admin**. Riders should use the **Android app**.

Optional: buy a domain and point it at Netlify/Firebase (their docs: custom domain).

## 4. After each app update

Run `flutter build web --release --no-web-resources-cdn` again and **redeploy** the new `build/web` folder, or the live site stays on the old build.
