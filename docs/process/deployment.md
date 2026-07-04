# Deploying KeyPath Documentation

This guide explains how to deploy the KeyPath documentation site to GitHub Pages.

## Option 1: GitHub Pages from `/docs` folder (Recommended)

This is the simplest approach - GitHub Pages will serve directly from the `/docs` folder.

### Setup

1. Ensure `_config.yml` has:
   ```yaml
   baseurl: ""  # Empty for root domain
   url: "https://yourusername.github.io"  # Or custom domain
   ```

2. Push changes to `main` branch

3. In GitHub repository settings:
   - Go to **Settings** → **Pages**
   - Source: **Deploy from a branch**
   - Branch: **main** → **/docs**
   - Save

GitHub Pages will automatically build and serve your site.

## Option 2: GitHub Actions (Advanced)

For more control over the build process:

### Create `.github/workflows/docs.yml`

```yaml
name: Deploy Documentation

on:
  push:
    branches:
      - main
    paths:
      - 'docs/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.0'
          bundler-cache: true
          working-directory: docs
      
      - name: Install dependencies
        working-directory: docs
        run: bundle install
      
      - name: Build site
        working-directory: docs
        run: bundle exec jekyll build
      
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: docs/_site
```

This builds the site and deploys to `gh-pages` branch automatically.

## Option 3: Manual Deployment

1. Build the site locally:
   ```bash
   cd docs
   bundle exec jekyll build
   ```

2. Copy `_site/` contents to `gh-pages` branch:
   ```bash
   git checkout gh-pages
   cp -r docs/_site/* .
   git add .
   git commit -m "Update docs"
   git push origin gh-pages
   ```

## Custom Domain

To use a custom domain (e.g., `docs.keypath.app`):

1. Create `CNAME` file in `docs/`:
   ```
   docs.keypath.app
   ```

2. Update `_config.yml`:
   ```yaml
   url: "https://docs.keypath.app"
   baseurl: ""
   ```

3. Configure DNS:
   - Add CNAME record: `docs` → `yourusername.github.io`

4. In GitHub Pages settings, add your custom domain

## Troubleshooting

### Site not updating

- Clear GitHub Pages cache
- Check build logs in Actions tab
- Verify `_config.yml` settings

### Build errors

- Check Ruby version matches `.ruby-version`
- Verify all dependencies in `Gemfile`
- Check Jekyll version compatibility

### 404 errors

- Verify `baseurl` is correct
- Check file paths are relative
- Ensure `index.md` exists

## Local Testing

Always test locally before deploying:

```bash
cd docs
bundle exec jekyll serve
open http://localhost:4000
```

## Continuous Deployment

With GitHub Actions, every push to `main` automatically rebuilds and deploys the site. No manual steps required!
