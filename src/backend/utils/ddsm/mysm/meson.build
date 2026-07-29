mysm_sources = files('mysm_minimal.c')
mysm = shared_module('mysm',
  mysm_sources,
  include_directories: postgres_inc,
  install: true,
  install_dir: dir_lib_pkg,
  name_prefix: '',
)
