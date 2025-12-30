# KeyPath Documentation Site

This is the documentation website for KeyPath, built with Jekyll and hosted on GitHub Pages.

## Local Development

### Prerequisites

- Ruby 3.0+ (check with `ruby --version`)
- Bundler (`gem install bundler`)

### Setup

```bash
# Install dependencies
bundle install

# Serve locally
bundle exec jekyll serve

# Open in browser
open http://localhost:4000
```

### Build

```bash
# Build static site
bundle exec jekyll build

# Output will be in _site/
```

## Deployment

### GitHub Pages

The site is automatically deployed to GitHub Pages when changes are pushed to the `main` branch (if configured) or the `gh-pages` branch.

**Option 1: Deploy from `/docs` folder**

1. Ensure `_config.yml` has `baseurl: ""` (empty)
2. Push changes to `main` branch
3. GitHub Pages will serve from `/docs` folder

**Option 2: Deploy from `gh-pages` branch**

1. Build the site: `bundle exec jekyll build`
2. Copy `_site/` contents to `gh-pages` branch
3. Push to `gh-pages` branch

### Custom Domain

To use a custom domain:

1. Add `CNAME` file with your domain
2. Update `_config.yml` with your domain URL
3. Configure DNS settings

## Structure

```
docs/
├── _config.yml          # Jekyll configuration
├── _layouts/            # Page layouts
├── _includes/           # Reusable components
├── assets/              # CSS, JS, images
├── guides/              # Guide pages
├── architecture/        # Architecture docs
├── migration/           # Migration guides
├── adr/                 # Architecture Decision Records
└── index.md             # Homepage
```

## Adding Content

### New Page

1. Create a new `.md` file in appropriate directory
2. Add front matter:
   ```yaml
   ---
   layout: default
   title: Page Title
   description: Page description
   ---
   ```
3. Add to sidebar navigation in `_includes/sidebar.html`

### New Guide

1. Create file in `guides/` directory
2. Add to sidebar navigation
3. Link from relevant pages

## Styling

The site uses a clean, modern design with:

- SF Pro Display/Text fonts
- Clean, minimal layout
- Responsive design
- Dark mode support

Styles are in `assets/css/main.css`. Follow existing patterns for consistency.

## License

Same as KeyPath project (MIT License).
