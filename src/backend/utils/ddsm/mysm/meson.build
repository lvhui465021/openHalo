# mysm: MySQL Supplementary Modules shared library
# Ported from openHalo/UDB-TX

mysm_sources = files(
  'aggregates.c',
  'bpchar.c',
  'common_funcs.c',
  'date_func.c',
  'operators.c',
  'partListColumns.c',
  'strfuncs.c',
  'systemVar.c',
  'time_func.c',
  'timestamp_func.c',
  'user.c',
  'user_var.c',
  'uuid_short.c',
)

mysm = shared_module('mysm',
  mysm_sources,
  include_directories: postgres_inc,
  install: true,
  install_dir: dir_lib_pkg,
)
