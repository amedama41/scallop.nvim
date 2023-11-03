command! -nargs=? Scallop
      \ call scallop#start_terminal(<q-args>)
command! -nargs=? ScallopEdit
      \ call scallop#start_terminal_edit(<q-args>)
