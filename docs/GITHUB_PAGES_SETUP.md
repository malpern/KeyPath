# GitHub Pages Setup for Documentation

This guide explains how to host the KeyPath documentation HTML files on GitHub Pages so users can view them online.

## Quick Setup

### Option 1: GitHub Actions (Recommended)

1. **Create `.github/workflows/docs.yml`:**

```yaml
name: Build and Deploy Documentation

on:
  push:
    branches:
      - main
    paths:
      - 'docs/**/*.adoc'
      - '.github/workflows/docs.yml'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.1'
          bundler-cache: true

      - name: Install AsciiDoctor
        run: |
          gem install asciidoctor

      - name: Build HTML
        run: |
          ./Scripts/build-docs.sh

      - name: Setup Pages
        uses: actions/configure-pages@v4

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs/

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

2. **Enable GitHub Pages:**
   - Go to repository Settings → Pages
   - Source: "GitHub Actions"
   - Save

3. **Push to main branch:**
   - The workflow will build and deploy automatically
   - Documentation will be available at: `https://YOUR_USERNAME.github.io/KeyPath/docs/KEYPATH_GUIDE.html`

### Option 2: Manual Setup (Simpler, but manual)

1. **Build HTML locally:**
   ```bash
   ./Scripts/build-docs.sh
   ```

2. **Create `docs` branch:**
   ```bash
   git checkout -b docs
   git add docs/*.html
   git commit -m "docs: add HTML documentation"
   git push origin docs
   ```

3. **Enable GitHub Pages:**
   - Go to repository Settings → Pages
   - Source: "Deploy from a branch"
   - Branch: `docs` → `/docs` folder
   - Save

4. **Update HTML files manually** whenever you edit `.adoc` files:
   ```bash
   ./Scripts/build-docs.sh
   git add docs/*.html
   git commit -m "docs: update HTML"
   git push origin docs
   ```

## Updating Links

After setting up GitHub Pages, update links in:

1. **README.md** - Change relative links to absolute GitHub Pages URLs:
   ```markdown
   - **[HTML Version](https://YOUR_USERNAME.github.io/KeyPath/docs/KEYPATH_GUIDE.html)** (recommended)
   ```

2. **docs/README.md** - Add GitHub Pages link

3. **App UI** - If you want to link from the app itself

## Custom Domain (Optional)

If you have a custom domain (e.g., `keypath.app`):

1. Add `CNAME` file to `docs/` folder:
   ```
   keypath.app
   ```

2. Configure DNS:
   - Add CNAME record: `docs.keypath.app` → `YOUR_USERNAME.github.io`

3. Update GitHub Pages settings:
   - Settings → Pages → Custom domain: `docs.keypath.app`

## Troubleshooting

**HTML files not updating?**
- Check GitHub Actions workflow status
- Verify `.adoc` files are in `docs/` folder
- Ensure `build-docs.sh` script is executable

**Links broken?**
- Verify GitHub Pages URL matches your repository name
- Check that HTML files are in `docs/` folder
- Ensure relative paths are correct

**AsciiDoctor errors?**
- Install asciidoctor: `brew install asciidoctor`
- Check `.adoc` syntax errors (warnings are usually OK)
- Run `./Scripts/build-docs.sh` locally to see errors

## Benefits of GitHub Pages

✅ **Always up-to-date** - Auto-rebuilds on every commit  
✅ **No hosting costs** - Free GitHub Pages hosting  
✅ **Fast CDN** - GitHub's global CDN  
✅ **HTTPS** - Automatic SSL certificates  
✅ **Version control** - HTML files tracked in git  

## Alternative: Host Elsewhere

If you prefer not to use GitHub Pages:

- **Netlify** - Free hosting, auto-deploy from git
- **Vercel** - Free hosting, great for static sites
- **Cloudflare Pages** - Free, fast CDN
- **Your own server** - Full control

All of these can auto-build from your repository when `.adoc` files change.

