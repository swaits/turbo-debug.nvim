# Contributing

We use **jj** (Jujutsu) for source control, not git.

## Adding a new adapter

1. Create `lua/tiny-debugger/adapters/<language>.lua` (see `go.lua` for reference)
2. Add the module name to the loader list in `adapters/init.lua`
3. Add the language to vimdoc

For simple executable adapters, add them inline in `adapters/init.lua` instead of a separate file.

## Running tests

```sh
for t in tests/test_*.lua; do nvim --headless -u tests/minimal_init.lua -c "luafile $t" -c 'qa!'; done
```
