# KeyPath Documentation Site

Beautiful, Apple WWDC-inspired documentation website for KeyPath, built with Jekyll and hosted on GitHub Pages.

## Local Development

### Prerequisites

- Ruby 3.0 or later
- Bundler gem

### Setup

1. Install dependencies:
```bash
bundle install
```

2. Build and serve locally:
```bash
bundle exec jekyll serve
```

3. Open http://localhost:4000 in your browser

### Build for Production

```bash
bundle exec jekyll build
```

The site will be built to `_site/` directory.

## GitHub Pages Deployment

This site is configured to work with GitHub Pages. To deploy:

1. Push the `docs/` directory to your repository
2. In GitHub repository settings, enable GitHub Pages
3. Select source: "Deploy from a branch"
4. Choose branch: `main` (or your default branch)
5. Choose folder: `/docs`

The site will be available at `https://yourusername.github.io/KeyPath/` (or your custom domain).

## Project Structure

```
docs/
├── _config.yml          # Jekyll configuration
├── _layouts/            # Page layouts
├── _includes/           # Reusable components
├── assets/              # CSS, JS, images
├── getting-started/     # Getting started guides
├── guides/              # Detailed guides
├── migration/           # Migration guides
├── architecture/        # Architecture documentation
├── adr/                 # Architecture Decision Records
└── index.md             # Homepage
```

## Customization

### Colors

Edit CSS variables in `assets/css/main.css`:

```css
:root {
    --color-primary: #007AFF;
    --color-background: #FFFFFF;
    /* ... */
}
```

### Navigation

Edit `_config.yml`:

```yaml
navigation:
  - title: Getting Started
    url: /getting-started
```

### Sidebar

Edit `_includes/sidebar.html` to customize the navigation tree.

## Contributing

When adding new documentation:

1. Create markdown files in the appropriate directory
2. Add front matter with `layout`, `title`, and `description`
3. Update `_includes/sidebar.html` to add navigation links
4. Test locally with `bundle exec jekyll serve`

## License

Same as KeyPath project (MIT License).
