<div align="center">

<img src="app/Icon.png" alt="Dossier" width="180" />

# Dossier

**Give your AI the right context — every time.**

Don't outsource the thinking. Keep control.
Build the perfect prompt and enjoy AI acceleration.

Read the story: [JaaS — Juniors as a Service](https://medium.com/@cafc.aouad.jad/jaas-juniors-as-a-service-d81e7550676f)

![Dossier — file explorer, prompt builder, and live preview](docs/screenshot.png)

</div>

---


## Install

Clone the repo and install the `dossier` CLI engine with
[uv](https://docs.astral.sh/uv/):

```sh
git clone https://github.com/Jad1908/dossier.git
cd dossier
uv tool install .
```

This puts the `dossier` command on your PATH (`~/.local/bin`). The app shells
out to it for every preview. To update it later, pull and run
`uv tool install --force .`.

## Launch the app

```sh
cd app
make run
```

Requires macOS 14 (Sonoma) or newer and a Swift toolchain (the Xcode Command
Line Tools are enough). See [`app/README.md`](app/README.md) for details.

---

## Keyboard shortcuts

Build prompts without leaving the keyboard. These work in the builder pane
whenever you're **not** typing in a text field — press `?` any time for the
full in-app cheat sheet.

| Key | Action |
| --- | --- |
| `t` | Add a text section |
| `⇧t` | Add a tree section |
| `f` | Add a file section |
| `⇧f` | Add a folder section |
| `?` | Show the shortcuts cheat sheet |
| `↑` / `↓` | Select the previous / next section |
| `↩` | Edit the selected section |
| `⌫` | Delete the selected section(s) |
| `d` `d` | Delete the selected section(s) |

---

## License

[MIT](LICENSE). Issues and pull requests welcome.
