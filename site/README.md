# Website development

The site renders the canonical Markdown documentation and compiles the shared
Keybay TUI into a standalone browser demo. From the repository root, with Dart
and Ruby/Bundler installed:

```sh
dart pub get --enforce-lockfile
BUNDLE_GEMFILE=site/Gemfile bundle install
BUNDLE_GEMFILE=site/Gemfile bundle exec ruby tool/build_site.rb build/preview/keybay
python3 -m http.server 5778 --bind 127.0.0.1 --directory build/preview
```

Open <http://127.0.0.1:5778/keybay/>. Rebuild to pick up changes; the default
output directory when omitted is `build/site`, used by GitHub Pages.

`demo/main.dart` mounts the production TUI screens with `fleury_web`.
`demo/store.dart` supplies disposable sample data through the TUI's internal
storage contract. It does not import the native SDK or use browser storage or
network requests. Copy explicitly writes to the browser clipboard. Reset demo
and reload both start fresh; Quit offers a Start demo button.

The demo's Fleury Git revision must match the CLI's pinned revision. Its build
dependencies belong to the workspace development dependencies, not the CLI's
runtime closure. The site build checks generated links and assets, and the
demo's data and model lifecycle are tested with:

```sh
dart test test/site_demo_test.dart
```

Fleury follow-up: `mountApp` currently focuses its keyboard-capture textarea
unconditionally. Embeddable apps need a public initial-focus option, so a demo
lower on a page cannot take keyboard input before interaction. This host blurs
the initially focused element after mounting; explicit Start/Reset retains
focus. Remove that host adjustment once Fleury exposes the policy.
