if !has('vim9script') ||  v:version < 900
  finish
endif

vim9script

if get(g:, 'loaded_texpresso_vim9', false)
  finish
endif
g:loaded_texpresso_vim9 = true

import autoload '../autoload/texpresso.vim'

# Define user command
command! -nargs=* -complete=file TeXpresso texpresso.Launch(<f-args>)
# vim: ts=2 sts=2 sw=2
