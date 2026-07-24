# Copyright (c) 2025-2026, PostgreSQL Global Development Group

# MySQL scanner generation
mys_backend_scanner = custom_target('mys_scan',
  input: 'mys_scan.l',
  output: 'mys_scan.c',
  command: [flex_cmd, '--no-backup', '--', '-CF', '-p', '-p'],
)
generated_sources += mys_backend_scanner

# MySQL grammar generation
mys_backend_parser = custom_target('mys_gram',
  input: 'mys_gram.y',
  kwargs: bison_kw,
)
generated_sources += mys_backend_parser.to_list()

# MySQL parser sources
mys_parser_sources = files(
  'mys_keywords.c',
)

mys_parser_gen_sources = [
  mys_backend_scanner,
  mys_backend_parser,
]

# Keyword list hash generation
gen_keywordlist = find_program('gen_keywordlist.pl', dirs: [join_paths(meson.project_source_root(), 'src', 'tools')])
mys_kwlist_d = custom_target('mys_kwlist_d',
  input: join_paths(meson.project_source_root(), 'src', 'include', 'parser', 'mysql', 'mys_kwlist.h'),
  output: 'mys_kwlist_d.h',
  command: [perl, gen_keywordlist, '--extern', '--varname=MysScanKeywords', '@INPUT@'],
)
generated_sources += mys_kwlist_d

# Add dependency: keywords needs the generated keyword header
mys_keywords = static_library('mys_keywords',
  mys_parser_sources,
  dependencies: [backend_code],
  include_directories: include_directories('.'),
  kwargs: internal_lib_args,
)
backend_link_with += mys_keywords

# The generated scanner and grammar are added to the parent parser static_library via this directory's files
# The mys_parser.o is already registered via mys_parser.c in ../meson.build
backend_sources += files('mys_parser.c')
