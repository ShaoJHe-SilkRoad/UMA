# Roboto font provenance

- Official repository: `https://github.com/google/fonts`
- Source commit: `113bac0943d5b85dcc6c2c01b48fae88d4b5c52a`
- Source directory: `ofl/roboto/static`
- License source: `ofl/roboto/OFL.txt`
- Upstream change: Google Fonts Roboto v3 ("Roboto Classic"), signed commit
  `113bac0943d5b85dcc6c2c01b48fae88d4b5c52a`

Only the three application-required upright weights are bundled:

| Resource | PostScript name | SHA-256 |
| --- | --- | --- |
| `Roboto-Regular.ttf` | `Roboto-Regular` | `79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95` |
| `Roboto-Medium.ttf` | `Roboto-Medium` | `f205cc511821ea56078a105557fcea6253129404d411c997e1866fbd006abb68` |
| `Roboto-Bold.ttf` | `Roboto-Bold` | `7d0b991ee3e0be7af01ad7ea8cd2beea6c00a25e679a0226b6737f079aafff86` |
| `OFL.txt` | SIL Open Font License 1.1 | `32a83e642d85658ed423e0e235ec2c4d159c398ee0f533b11c06a70e278b0a20` |

The bundled license differs from upstream only by removal of one trailing
space on line 21 so repository whitespace validation remains clean.

The application registers these files with CoreText at process scope before
constructing UI. Simplified Chinese glyphs use the explicit macOS fallback
`PingFang SC`; no private system font file is copied or redistributed.
