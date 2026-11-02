# Third-party content

## omh-ralph-task

- Source: https://github.com/witt3rd/oh-my-hermes (MIT)
- Installed via skills.sh; upstream revision at import: `3b06e33a`
- Kept on its own as executor discipline (file scope, commit, report). The other nine `omh-*` skills
  and the `omh` plugin they needed were removed in 0.7.0; its mentions of `omh-ralph-driver` etc. are
  upstream context only.

Because it is copied here, `hermes skills update` will not refresh it. To take upstream changes, diff
against the upstream repo and merge by hand, then log it in `CHANGELOG.md`.
Upstream licence text: `LICENSES/oh-my-hermes-MIT.txt`.
