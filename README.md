# fzf-tab-completion

Tab completion using fzf in zsh, bash, GNU readline apps (e.g. `python`, `php -a` etc.)

This is distinct from
[fzf's own implementation for completion](https://github.com/junegunn/fzf#fuzzy-completion-for-bash-and-zsh),
in that it works _with_ the existing completion mechanisms
rather than [creating a new mechanism](https://github.com/junegunn/fzf/wiki/Examples-(completion)).

## Example
<details><summary>Click here to show screencast</summary>

![Example](./example.svg)
</details>

## Installation

1. You need to [install fzf](https://github.com/junegunn/fzf#installation) first.
1. If you are using OSX you may need to install some additional things:
    * e.g. `brew install gawk grep gnu-sed coreutils`
1. Clone this repository: `git clone https://github.com/lincheney/fzf-tab-completion ...`
    * you can also choose to download only the scripts you need, up to you.
1. Follow instructions on how to set up for:
    * [zsh](#zsh)
    * [bash](#bash)
    * [readline](#readline)
    * [nodejs](#nodejs-repl)
    * [python3](#python3)
1. The following environment variables are supported, just as in fzf's "vanilla" completion.
    * `$FZF_TMUX_HEIGHT`
    * `$FZF_COMPLETION_OPTS`
    * `$FZF_DEFAULT_OPTS`

    See also <https://github.com/junegunn/fzf#settings>

    Avoid changing these `fzf` flags: `-n`, `--nth`, `--with-nth`, `-d`

    For bash, also avoid `--expect` and `--print-query`.

## zsh

Add to your `~/.zshrc`:
```bash
source /path/to/fzf-tab-completion/zsh/fzf-zsh-completion.sh
bindkey '^I' fzf_completion
```
If you have also enabled fzf's zsh completion, then the `bindkey` line is optional.

Note that this does not provide `**`-style triggers,
you will need to enable fzf's zsh completion _as well_.

#### --tiebreak=chunk

The default `fzf` tiebreak setting is line: `Prefers line with shorter length`.
The length of the zsh display strings may skew the ordering of the results even though they are not part of the match.
You may find that adding the `fzf` flag `--tiebreak=chunk` to the environment variable `$FZF_COMPLETION_OPTS` provides better behaviour.

#### tmux

`$FZF_TMUX_OPTS` is respected same as in [fzf](https://github.com/junegunn/fzf#key-bindings-for-command-line)
however you must have fzf's keybindings enabled as well.

#### Searching display strings

By default, display strings are shown but cannot be searched in fzf.
This is configurable via `zstyle`:
```bash
# only for git
zstyle ':completion:*:*:git:*' fzf-search-display true
# or for everything
zstyle ':completion:*' fzf-search-display true
```

#### Specifying keybindings

You can specify `fzf` keybindings to execute shell commands *after* `fzf` has closed.
This is configurable via the `fzf-completion-keybindings` zstyle.

Keybinds look like: `KEY:SCRIPT`
When `KEY` is pressed, `fzf` will *exit* and the zsh `SCRIPT` will run.
If the keybind is given in the form `KEY:accept:SCRIPT` then the selected matches will also be completed before `SCRIPT` is run.
`KEY` is any valid `fzf` key.

There is an additional function `repeat-fzf-completion` that can be called in the `SCRIPT` to retrigger `fzf` completion.

No keybinds are configured by default.

```bash
# press ctrl-r to repeat completion *without* accepting i.e. reload the completion
# press right to accept the completion and retrigger it
# press alt-enter to accept the completion and run it
keys=(
    ctrl-r:'repeat-fzf-completion'
    right:accept:'repeat-fzf-completion'
    alt-enter:accept:'zle accept-line'
)

zstyle ':completion:*' fzf-completion-keybindings "${keys[@]}"
# also accept and retrigger completion when pressing / when completing cd
zstyle ':completion::*:cd:*' fzf-completion-keybindings "${keys[@]}" /:accept:'repeat-fzf-completion'
```

Note that you can still specify the normal `--bind ...` options in e.g. `$FZF_COMPLETION_OPTS`
if you need to perform `fzf` specific actions or don't need to run zsh commands.

#### Specifying custom fzf options

You can specify custom `fzf` options with the `fzf-completion-opts` style.
This allows you to have different options based on the command being completed
(as opposed to the `$FZF_DEFAULT_OPTS` etc environment variables which are global).

This is most useful for changing the `--preview` option.
Use `{1}` for the selected text (or `{+1}` if using multi-select).
Note `{1}` or `{+1}` will come through "shell-escaped", so you will need to unescape it, e.g. using `eval` or `printf %b`

```bash
# basic file preview for ls (you can replace with something more sophisticated than head)
zstyle ':completion::*:ls::*' fzf-completion-opts --preview='eval head {1}'

# preview when completing env vars (note: only works for exported variables)
# eval twice, first to unescape the string, second to expand the $variable
zstyle ':completion::*:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-completion-opts --preview='eval eval echo {1}'

# preview a `git status` when completing git add
zstyle ':completion::*:git::git,add,*' fzf-completion-opts --preview='git -c color.status=always status --short'

# if other subcommand to git is given, show a git diff or git log
zstyle ':completion::*:git::*,[a-z]*' fzf-completion-opts --preview='
eval set -- {+1}
for arg in "$@"; do
    { git diff --color=always -- "$arg" | git log --color=always "$arg" } 2>/dev/null
done'
```

#### changing display string color

By default, the display string and the input prefix (i.e. the parts of the strings that are *not* searchable)
are highlighted with `\x1b[37m` which *should* come out as a light grey.

You can change this with the `fzf-completion-secondary-color` zstyle, e.g.:
```bash
# make it red instead
zstyle ':completion:*' fzf-completion-secondary-color red
```

It supports anything that can be used in the zsh prompt escape `%F{...}`, e.g. certain names like `red` or hex sequences like `#ff0000`.
Consult `man --pager='less -p ^\\s*fg=colour' zshzle` for other possible values.
If set to an empty string, no color will be applied at all.

## bash

Add to your `~/.bashrc`:
```bash
source /path/to/fzf-tab-completion/bash/fzf-bash-completion.sh
bind -x '"\t": fzf_bash_completion'
```

Note that this does not provide `**`-style triggers,
you will need to enable fzf's bash completion _as well_.

If you are using a `bash` that is dynamically linked against readline (`LD_PRELOAD= ldd $(which bash)`)
you may prefer (or not!) to use the [readline](#readline) method instead.

#### Selecting a match

fzf opens below the prompt with the word being completed as its query,
which you can keep typing into or erase.
Files and directories are listed by name alone, without the directory part already typed,
and the query starts with the same part of the word.
Among equally good matches, the ones matching nearer their start come first.

* `Tab` and `Shift-Tab` move down and up the list, wrapping around at either end.
* `Ctrl-Space` marks several matches, which are inserted separated by spaces.
* `Backspace` on an empty query closes fzf.
* `/` on a directory inserts it and completes inside it.
* `Enter` inserts the selected match.

Options in `$FZF_COMPLETION_OPTS` are passed on to fzf and can change these keys.

#### Changing fzf prompt

The `FZF_TAB_COMPLETION_PROMPT` environment variable sets fzf's prompt.
The default is `'> '`.
If a loading message hides the line being completed, fzf's prompt also shows the part of it before the query.
You could, for example, change it to `FZF_TAB_COMPLETION_PROMPT='❯ '`. 

#### Autocomplete common prefix

Like `bash`'s own tab completion, the longest prefix common to all matches is completed
*before* showing matches in fzf, when it extends the word being completed and is a match itself.

This is controlled by the variables
* `FZF_COMPLETION_AUTO_COMMON_PREFIX=false` - always shows fzf whenever there are at least 2 matches
* `FZF_COMPLETION_AUTO_COMMON_PREFIX_PART=true` - completes the common prefix even if it is not a match

For example, if we have following files in a directory:
```
abcdef-1234
abcdef-5678
abc
other
```

By default:
* when completing `ls <tab>`, it will display fzf with all 4 files
* when completing `ls a<tab>`, it will automatically complete to `ls abc`.
    Pressing tab again will show fzf with the first 3 files.
* when completing `ls abcd<tab>` it will show fzf with the first 2 files
* With `FZF_COMPLETION_AUTO_COMMON_PREFIX_PART=true` set as well:
    * when completing `ls abcd<tab>`, it will automatically complete to `ls abcdef-`.
        Pressing tab again will show fzf with the first 2 files.
* With `FZF_COMPLETION_AUTO_COMMON_PREFIX=false`:
    * when completing `ls a<tab>`, it will display fzf with the first 3 files.

#### Aliases

An alias at the start of the line is replaced by its text before completing,
so with `alias ll='ls -l'`, `ll <tab>` completes like `ls -l <tab>`.

Set `FZF_COMPLETION_KEEP_ALIASES` to a space-separated list of aliases that keep their own completion
when they have one, or to `:all:` for every alias.
For example, with `alias ls=eza` and `FZF_COMPLETION_KEEP_ALIASES=ls`,
`ls <tab>` uses the completion for `ls` instead of the one for `eza`.

#### tmux

`$FZF_TMUX_OPTS` is respected same as in [fzf](https://github.com/junegunn/fzf#key-bindings-for-command-line)
however you must have fzf's keybindings enabled as well.

#### fzf height

With fzf 0.34 or later, fzf shrinks to fit a short list.
When `$FZF_TMUX_HEIGHT` is unset, fzf grows to fill the space below the cursor
if that is more than 40% of the terminal.
Finding the cursor position takes a round trip to the terminal,
which over a slow SSH connection can take longer than the rest of the completion.
So over SSH fzf always uses 40% of the terminal.
Set `FZF_COMPLETION_SSH_CURSOR_QUERY=true` to look up the cursor position over SSH as well,
for example on a fast local network.

#### Custom loading message

`bash` clears the prompt and input line before running the completion,
so the last line of the prompt and the input line are printed again in their place.
This keeps fast completions from flickering.
A prompt that runs commands through `$(...)` or backticks would run them again on every completion,
so for such prompts, and on `bash` older than 4.4, the message `Loading matches ...` is printed instead.

You can customise the message by defining a `_fzf_bash_completion_loading_msg()` function
that prints it, before or after sourcing the script.
For example the following always prints a fixed message:
```bash
_fzf_bash_completion_loading_msg() { echo 'Loading matches ...'; }
```

## readline

NOTE: This uses a `LD_PRELOAD` hack, is only supported on Linux and only for GNU readline
(*not* e.g. libedit or other readline alternatives).

1. Run: `cd /path/to/fzf-tab-completion/readline/ && cargo build --release`
1. Copy/symlink `/path/to/fzf-tab-completion/readline/bin/rl_custom_complete` into your `$PATH`
1. Add to your `~/.inputrc`:
   ```
   $include function rl_custom_complete /path/to/fzf-tab-completion/readline/target/release/librl_custom_complete.so
   "\t": rl_custom_complete
   ```
1. Build https://github.com/lincheney/rl_custom_function/
   * this should produce a file `librl_custom_function.so` which you will use with `LD_PRELOAD` in the next step.
1. Run something interactive that uses readline, e.g. python:
   ```bash
   LD_PRELOAD=/path/to/librl_custom_function.so python
   ```
1. To apply this all applications more permanently,
   you will need to set `LD_PRELOAD` somewhere like `/etc/environment` or `~/.pam_environment`.
   * NOTE: if you set `LD_PRELOAD` in your `.bashrc`, or similar, it will affect applications run _from_ `bash`
      but not the parent `bash` process itself.
   * See also: [link](https://wiki.archlinux.org/index.php/Environment_variables#Per_user)

These are the applications that I have seen working:
* `python2`, `python3`
    * only `PYTHON_BASIC_REPL=1 python3` if python 3.13+, otherwise see [python3](#python3)
* `php -a`
* `R`
* `lftp`
* `irb --legacy` (the new `irb` in ruby 2.7 uses `ruby-reline` instead of readline)
* `gdb`
* `sqlite3`
* `bash` (only when not statically but dynamically linked to libreadline)

## nodejs repl

1. Copy/symlink `/path/to/fzf-tab-completion/node/rl_custom_complete` into your `$PATH`
1. Then run `node -r /path/to/fzf-tab-completion.git/node/fzf-node-completion.js`
    * You may wish to add a shell alias to your `~/.zshrc`/`~/.bashrc` to avoid typing out the full command each time, e.g.:
        `alias node='node -r /path/to/fzf-tab-completion.git/node/fzf-node-completion.js`

## python3

1. Copy/symlink `/path/to/fzf-tab-completion/python/rl_custom_complete` into your `$PATH`
1. Add the code below to either:
    * your `~/.pythonstartup`
    * your `$PYTHONPATH/usercustomize.py`
        * see <https://docs.python.org/3/tutorial/appendix.html#the-customization-modules>
        * for example, I have `export PYTHONPATH=$HOME/dotfiles/pythonpath` and a file `$HOME/dotfiles/pythonpath/usercustomize.py`
```python
with open('/path/to/fzf-tab-completion.git/python/fzf_python_completion.py') as file:
    exec(file.read())
```

This should work with:
* a normal python shell `python3`, including the new interactive shell from 3.13+
* the old interactive shell i.e. `PYTHON_BASIC_REPL=1 python3`
* (only when added to `usercustomize.py`) anything that uses `readline.set_completer(...)`, including:
    * `python3 -m asyncio`
    * `pdb` / `breakpoint()`

## Related projects

* <https://github.com/rockandska/fzf-obc> (fzf tab completion in bash)
* <https://github.com/Aloxaf/fzf-tab> (fzf tab completion in zsh)
* <https://github.com/lincheney/rl_custom_isearch> (fzf for history search in all readline applications)
