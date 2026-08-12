# Token Burn promo site

Static promo site for Token Burn, built with Next.js (App Router, static export) and Tailwind CSS,
hosted on Azure Static Web Apps at <https://tokenburn.dotnetgeek.co.uk>.

The site deliberately reuses the game's own presentation: the palette comes from
[`presentation/asset_catalog.json`](../presentation/asset_catalog.json), the fonts (Bebas Neue,
Inter, Share Tech Mono) are copied from [`presentation/fonts`](../presentation/fonts), and the
screenshots come from [`shots/`](../shots).

## Local development

```bash
cd site
npm install
npm run dev      # http://localhost:3000
npm run build    # static export into site/out
```

`site/.gdignore` keeps the Godot editor from importing anything in here.

## Pages

| Route        | Content                                                     |
| ------------ | ----------------------------------------------------------- |
| `/`          | Hero, pitch, feature teasers, download CTA                   |
| `/overview/` | Round loop, contracts, heat, locations, perks, the investor  |
| `/tutorial/` | Corrigan's intro, the wall checklist, first-run walkthrough  |
| `/download/` | Android APK download and sideloading instructions            |

## Updating imagery

Web-sized WebP files in `public/img` are generated from the Godot project's art:

```bash
node scripts/prepare-assets.mjs
```

Edit the `jobs` array in [`scripts/prepare-assets.mjs`](scripts/prepare-assets.mjs) to add or swap
screenshots, then commit the regenerated files.

## Publishing a build

The download button points at `/downloads/token-burn.apk`. APKs are gitignored, so either:

- drop the signed APK into `site/public/downloads/token-burn.apk` before a manual deploy, or
- attach it to a GitHub release and change `apkHref` in [`src/lib/site.ts`](src/lib/site.ts) to that
  URL.

Version, size and Android requirement shown on the page also live in `src/lib/site.ts`.

## Deployment

[`.github/workflows/deploy-site.yml`](../.github/workflows/deploy-site.yml) builds the static export
and uploads it to Azure Static Web Apps on every push to `main` that touches `site/**`. Pull
requests get a preview environment that is torn down when the PR closes.

### One-time Azure setup

1. Create a **Static Web App** (Free tier is enough) in the Azure portal. Choose **Other** as the
   deployment source so Azure does not create its own workflow.
2. From the resource, open **Manage deployment token** and copy the token.
3. In GitHub, add it as the repository secret `AZURE_STATIC_WEB_APPS_API_TOKEN`
   (Settings → Secrets and variables → Actions).
4. Push to `main` (or run the workflow manually) and confirm the site appears on the generated
   `*.azurestaticapps.net` hostname.

### Custom domain

1. In the Static Web App, go to **Custom domains → Add → Custom domain on other DNS**, and enter
   `tokenburn.dotnetgeek.co.uk`.
2. Azure gives you a CNAME target. At the DNS host for `dotnetgeek.co.uk`, create:

   ```
   tokenburn  CNAME  <name>.azurestaticapps.net
   ```

3. Back in Azure, validate the domain. The TLS certificate is issued and renewed automatically.

`public/staticwebapp.config.json` is copied into the export and handles the 404 fallback, the APK
MIME type and security headers.
