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

Apple Silicon, one command:

```sh
curl -fsSL https://raw.githubusercontent.com/Jad1908/dossier/main/install.sh | sh
```

Requires macOS 14 (Sonoma) or newer. On Intel, build from source — see
[`app/README.md`](app/README.md).

### CLI engine only

The app shells out to the `dossier` command-line engine. The installer above
sets it up for you, but you can also install it on its own with
[uv](https://docs.astral.sh/uv/):

```sh
uv tool install git+https://github.com/Jad1908/dossier.git
```

This puts the `dossier` command on your PATH (`~/.local/bin`). To update it
later, run `uv tool upgrade dossier`.

## Launch the app


```sh
cd app
make run
```

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
