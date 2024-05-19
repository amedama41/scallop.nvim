function! scallop#open_terminal(args)
  call luaeval('require("scallop").open_terminal(_A)', a:args)
endfunction

function! scallop#open_edit(args)
  call luaeval('require("scallop").open_edit(_A)', a:args)
endfunction
