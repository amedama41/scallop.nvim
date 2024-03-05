local ok, cmp = pcall(require, 'cmp')
if ok then
  cmp.register_source('scallop_shell_history', require('cmp_shell_history').new())
end
