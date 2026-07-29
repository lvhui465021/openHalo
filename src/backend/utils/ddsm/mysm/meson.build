mysm_sources = files(
  'strfuncs.c',
  'user_var.c',  
  'aggregates.c',
  'uuid_short.c',
  'texteq_mys.c',
  'mysm_globals.c',
  'uuid_stubs.c',
)
mysm = shared_module('mysm',
  mysm_sources,
  include_directories: postgres_inc,
  c_args: ['-fvisibility=default'],
  install: true,
  install_dir: dir_lib_pkg,
  name_prefix: '',
)
