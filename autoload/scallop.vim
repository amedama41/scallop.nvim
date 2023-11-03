function! scallop#start_terminal(args)
  call luaeval('require("scallop").start_terminal(_A)', a:args)
endfunction

function! scallop#start_terminal_edit(args)
  call luaeval('require("scallop").start_terminal_edit(_A)', a:args)
endfunction
