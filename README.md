# TeXpresso.vim9
vim mode for texpresso, written in vim9script.

An almost 1:1 port of the lua plugin [texpresso.vim](https://github.com/let-def/texpresso.vim.git).
One could even say a complete rip-off :D
All credits to the original [author](https://github.com/let-def/texpresso).

## Installation

Assuming you have [texpresso](https://github.com/let-def/texpresso) installed.
```sh
mkdir -p $HOME/.vim/pack/downloads/opt
cd $HOME/.vim/pack/downloads/opt
git clone https://github.com/gcanat/texpresso.vim9
```

Add the following lines to your `$HOME/.vimrc` file:
```vim
" if texpresso is not in your $PATH
let g:texpresso_path = "/path/to/texpresso"
" source the plugin
packadd texpresso.vim9
```

## Usage

Open a `.tex` file and do `:Texpresso %` to start viewing it in texpresso.

Both documents should be syncrhonized. Moving around in one, should also move the other.

Updating the `.tex` should also update the viewer live.

Compilation errors should be in the quickfix list.

Switching colorscheme in vim should also change background and foreground colors in texpresso.
