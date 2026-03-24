# tacky

A CLI to manage the macOS pasteboard.

## Install

``` bash
cargo install --path .
```

## Usage

### Copying

- Copy file to pasteboard as UTI: `tacky copy -i public.html index.html`
- Copy stdin to pasteboard as UTI:
  `echo "hello" | tacky copy -i public.utf8-plain-text -`
- Copy multiple items:
  `tacky copy -i public.html index.html -i public.utf8-plain-text fallback.txt`

### Pasting

- Paste from pasteboard to stdout as UTI:
  `tacky paste -u public.utf8-plain-text`
- List available UTIs from pasteboard to stdout: `tacky paste --list`
