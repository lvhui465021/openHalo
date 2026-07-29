# Copyright (c) 2025, openHalo

install_data(
  'aux_mysql.control',
  kwargs: contrib_data_args,
)

install_data(
  'aux_mysql--1.1.sql',
  'aux_mysql--1.1--1.2.sql',
  'aux_mysql--1.2--1.3.sql',
  'aux_mysql--1.3--1.4.sql',
  'aux_mysql--1.4--1.5.sql',
  install_dir: dir_data_extension,
)

tests += {
  'name': 'aux_mysql',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'versioning',
    ],
  },
  'tap': {
    'tests': [
      't/005_mysql_compat.pl',
    ],
  },
}
