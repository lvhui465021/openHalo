# Copyright (c) 2022-2025, PostgreSQL Global Development Group

backend_sources += files(
  'analyze.c',
  'parse_agg.c',
  'parse_clause.c',
  'parse_coerce.c',
  'parse_collate.c',
  'parse_cte.c',
  'parse_enr.c',
  'parse_expr.c',
  'parse_func.c',
  'parse_jsontable.c',
  'parse_merge.c',
  'parse_node.c',
  'parse_oper.c',
  'parse_param.c',
  'parse_relation.c',
  'parse_target.c',
  'parse_type.c',
  'parse_utilcmd.c',
  'scansup.c',
)

# Build a small utility static lib for the parser. The generation of the
# parser is slow, and building this separately avoids other parts of the
# backend having to wait till gram.h is generated.
parser_sources = files('parser.c', 'parsereng.c')

backend_scanner = custom_target('scan',
  input: 'scan.l',
  output: 'scan.c',
  command: [flex_cmd, '--no-backup', '--', '-CF', '-p', '-p'],
)
generated_sources += backend_scanner
parser_sources += backend_scanner

backend_parser = custom_target('gram',
  input: 'gram.y',
  kwargs: bison_kw,
)
generated_sources += backend_parser.to_list()
parser_sources += backend_parser

# MySQL scanner generation
mys_backend_scanner = custom_target('mys_scan',
  input: 'mysql/mys_scan.l',
  output: 'mys_scan.c',
  command: [flex_cmd, '--no-backup', '--', '-CF', '-p', '-p'],
)
generated_sources += mys_backend_scanner

# MySQL grammar generation
mys_backend_parser = custom_target('mys_gram',
  input: 'mysql/mys_gram.y',
  kwargs: bison_kw,
)
generated_sources += mys_backend_parser.to_list()

# MySQL keyword source needs the generated mys_kwlist_d.h header
parser_sources += files('mysql/mys_keywords.c')
parser_sources += files('mysql/mys_parser.c')
parser_sources += mys_backend_scanner
parser_sources += mys_backend_parser

# MySQL parser runtime stubs (to be replaced with full migration)
parser_sources += files('mysql/mys_gram_globals.c', 'mysql/mys_namespace_stubs.c')
parser = static_library('parser',
  parser_sources,
  dependencies: [backend_code],
  include_directories: include_directories('.'),
  kwargs: internal_lib_args,
)
backend_link_with += parser
