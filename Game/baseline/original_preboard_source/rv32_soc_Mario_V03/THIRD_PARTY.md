# Third-party sources

LiteNES is imported from NJU ProjectN `am-kernels/kernels/litenes`, revision
`9c433f7cf4b4e05d09543bf7e269b23502d1b2b6`. The original AbstractMachine MIT
license is preserved at `upstream/litenes/LICENSE`.

The upstream README identifies an earlier source at
https://github.com/yaglo/mynes. The applicable license chain should be checked
against the actual imported revision when redistributing derived emulator code.

Commercial Nintendo ROM bytes are not distributed. The emulator license does
not grant rights to commercial game content. Supply an authorized or homebrew
ROM locally and rebuild the initialization inputs.

The platform RTL, bare-metal compatibility layer, input, scaler, startup and
verification tools are organized under `soc/`, `port/`, `boot/`, `tests/` and
`tools/`. Vendor IP must be regenerated using an authorized installation.
