# Cod

Cod creates CodeHS-container computers.

## How to use Cod

1. Go to https://codehs.com/explore/sandbox
2. Replace the code with

```js
await import('https://esm.sh/gadidae')
```

<details>

<summary>or, if that doesn't work</summary>

```js
await import("https://fastly.jsdelivr.net/npm/gadidae/+esm")
```

</details>

3. Press Run
4. Press Cod

## Apps

- Firefox is automatically installed, set as default, and launched.
- Prism Launcher is automatically installed. Use a valid Microsoft account, and once you're playing, ctrl+click to enable relative mouse.
- opencode is automatically installed. Launch with the UI or with `opencode web` to avoid problems with Cod's terminal.
- A terminal is always available. Use the Tasks tab to view logs for various Cod processes. Make a new tab to use bash. Long lines may behave unexpectedly.

> [!WARNING]
> While we install the latest versions of:
>
> - `firefox`
> - `prismlauncher`
> - `opencode`
>
> These tools you may want to use inside the terminal use CodeHS's default versions:
>
> - `node` (12.22.9)
> - `npm` (8.5.1)
> - `python`/`python3`/`python3.8` (3.8.20)
> - `python3.10` (3.10.12)
> - `python3.11`/`~/.pyvenv311/bin/python` (3.11.14)
> - `python3.12` (3.12.12)
> - `pip` (21.3.1)
> - `git` (2.34.1)
> - `dotnet` (6.0.428)
> - `java` (1.8.0_472)
> - `make` (4.3)
> - `clang` (13.0.0)
> - `gcc`/`g++` (11.4.0)
