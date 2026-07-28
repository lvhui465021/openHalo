# Copyright (c) 2025, openHalo

install_data(
  'mysql_adapter.control',
  kwargs: contrib_data_args,
)

install_data(
  'sql/mysql_adapter--1.0.sql',
  'sql/mysql_adapter--1.0--1.1.sql',
  'sql/mysql_adapter--1.1--1.0.sql',
  'sql/mysql_adapter--1.1.sql',
  install_dir: dir_data_extension,
)

tests += {
  'name': 'mysql_adapter',
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
