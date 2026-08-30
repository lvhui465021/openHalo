#############################################
# MySQL导出文件外键依赖顺序调整脚本使用说明
# 
# 脚本名称： 
# 	convert_mysqldump_file.py
# 
# 脚本运行环境要求： 
# 	python3（不低于3.6）
#   具备相关运行时环境
# 
# 脚本运行方式：
# 	python  convert_mysqldump_file.py  MySQL导出文件路径和名称（例如： **.sql）
# 	（注意：请勿手工预先修改MySQL导出文件。）
#   如果启动后报类似如下错误：
#       File "convert_mysqldump_file.py", line 2
#       SyntaxError: Non-ASCII character '\xe5' in file convert_mysqldump_file.py on line 2, but no encoding declared; see http://python.org/dev/peps/pep-0263/ for details
#       则说明Python版本太低。
# 
# 脚本运行结果：
# 	如果报错，运行中途会有错误输出。
# 	运行成功后，会显示出结果文件（新的.sql文件）的路径和名称（和MySQL导出文件同路径）。
# 
# 调整转换后的结果sql文件（还是MySQL语法），可以通过MySQL命令行客户端等工具，导入到Halo[MySQL]中。
#############################################


import os
from re import I
import time
import datetime 
import sys
import platform


def checkPythonVersion():
    # Version parts must be compared as integers: "3.12" sorts below "3.6"
    # as plain strings, which wrongly rejected every Python >= 3.10.
    versionInfo = platform.python_version_tuple()
    if ((int(versionInfo[0]) < 3)
            or (int(versionInfo[0]) == 3 and int(versionInfo[1]) < 6)):
        print("Python版本过低，请使用3.6或更高版本的Python！")
        sys.exit(0)


def get_table_name(str, startIndex):
    table_name_first_index = 0;
    table_name_last_next_index = 0;
    for index in range(len(str)):
        if (startIndex <= index):
            if (table_name_first_index == 0):
                if ((str[index] != ' ') and (str[index] != '`')):
                    table_name_first_index = index
            else:
                if ((str[index] == ' ') or (str[index] == '`')):
                    table_name_last_next_index = index
                    break

    table_name = str[table_name_first_index : table_name_last_next_index]
    return table_name


def get_database_name(str, startIndex):
    db_name_first_index = 0;
    db_name_last_next_index = 0;
    for index in range(len(str)):
        if (startIndex <= index):
            if (db_name_first_index == 0):
                if (str[index] == '`'):
                    db_name_first_index = index
            else:
                if (str[index] == '`'):
                    db_name_last_next_index = index + 1
                    break

    db_name = str[db_name_first_index : db_name_last_next_index]
    return db_name


def rewrite_foreign_key_stmt(tableName, origStmt):
    # CONSTRAINT `unk_nm1` FOREIGN KEY (`col1`) REFERENCES `tab2` (`nm1`),
    # alter table tab1 add CONSTRAINT `unk_nm1` FOREIGN KEY (`col1`) REFERENCES `tab2` (`nm1`) NOT VALID
    origStmt = origStmt.strip()
    origStmt = origStmt.strip("\n")
    origStmt = origStmt.strip()
    origStmt = origStmt.strip(",")

    ret = "ALTER TABLE "
    ret = ret + tableName
    ret = ret + " ADD "
    ret = ret + origStmt
    ret = ret + " NOT VALID;\n"
    return ret


def passthrough_trigger_ddl(line):
    """mysqldump trigger DDL passes through verbatim.

    The kernel now lexes MySQL version-conditional comments and executes
    them at the MySQL 5.7 level, and CREATE/DROP TRIGGER accept the MySQL
    spellings, so - unlike in the past - no rewriting into two-part
    PostgreSQL DDL is wanted or performed.
    """
    return line


if __name__ == "__main__":
    checkPythonVersion();

    if (len(sys.argv) != 2):
        print("对本工具的使用方式不正确！")
        print("本工具用法:  python convert_mysqldump_file.py 目标文件名")
        sys.exit(0)

    mysqldump_file = sys.argv[1]
    if (not os.path.exists(mysqldump_file)):
        print(f"目标文件 \"{mysqldump_file}\" 不存在！")
        sys.exit(0)

    print("本工具只能转换mysqldump（及其他MySQL官方工具）导出的脚本文件，")
    print("且只对涉及到外键引用并且顺序“错乱”的建表语句块（及相关insert语句块）进行调整。")
    print("要求待转换文件导出生成后没有被修改过。")
    print("转换得到的结果文件只能用于向Halo[MySQL]数据库导入。")
    print("\n")

    mysqldump_path_file = os.path.split(mysqldump_file)
    mysqldump_file_path = mysqldump_path_file[0]
    if (mysqldump_file_path == "") :
        mysqldump_file_path = "."
    mysqldump_file_name = mysqldump_path_file[1]
    converted_mysqldump_file_name = "converted_" + mysqldump_file_name
    converted_mysqldump_file = mysqldump_file_path + "/" + converted_mysqldump_file_name

    if (os.path.exists(converted_mysqldump_file)):
        os.remove(converted_mysqldump_file)

    mysqldump_file_fp = open(mysqldump_file, 'r')
    mysqldump_file_lines = mysqldump_file_fp.readlines()
    mysqldump_file_fp.close()

    converted_mysqldump_file_lines = []
    create_foreign_key_stmt_blocks = []
    use_db_stmt = ""
    delimiter = ";"
    cur_table_name = ""
    ref_table_names = []

    for line in mysqldump_file_lines:
        temp_line = line.strip()
        temp_line = temp_line.strip("\n")
        temp_line = temp_line.lower()
        if (temp_line.startswith("delimiter ")):
            converted_mysqldump_file_lines.append(line)
            items = temp_line.split()
            delimiter = items[1]
        elif (temp_line.startswith("use ")):
            converted_mysqldump_file_lines.append(line)
            use_db_stmt = line
        elif (temp_line.startswith("create database")):
            #CREATE DATABASE /*!32312 IF NOT EXISTS*/ `fork` /*!40100 DEFAULT CHARACTER SET utf8mb4 */;
            databaseName = get_database_name(temp_line, 15)
            newCreateDatabaseStmt = "CREATE DATABASE " + databaseName + ";\n"
            converted_mysqldump_file_lines.append(newCreateDatabaseStmt)
        elif (temp_line.startswith("create table")):
            converted_mysqldump_file_lines.append(line)
            cur_table_name = get_table_name(temp_line, 13)
        elif (temp_line.startswith("constraint") and (temp_line.find(" foreign key (") > 0)):
            create_foreign_key_stmt = rewrite_foreign_key_stmt(cur_table_name, line)
            create_foreign_key_stmt_blocks.append([use_db_stmt, create_foreign_key_stmt])
            if (not temp_line.endswith(",")):
                preLine = converted_mysqldump_file_lines[len(converted_mysqldump_file_lines) - 1]
                preLine = preLine.rstrip()
                preLine = preLine.rstrip("\n")
                preLine = preLine.rstrip()
                preLine = preLine.rstrip(",")
                preLine = preLine + "\n"
                converted_mysqldump_file_lines = converted_mysqldump_file_lines[0 : (len(converted_mysqldump_file_lines) - 1)]
                converted_mysqldump_file_lines.append(preLine)
        else:
            converted_mysqldump_file_lines.append(line)

    converted_mysqldump_file_fp = open(converted_mysqldump_file, 'w')
    for line in converted_mysqldump_file_lines:
        converted_mysqldump_file_fp.write(line)
    converted_mysqldump_file_fp.write("\n")
    for create_foreign_key_stmt_block in create_foreign_key_stmt_blocks:
        converted_mysqldump_file_fp.write(create_foreign_key_stmt_block[0])
        converted_mysqldump_file_fp.write(create_foreign_key_stmt_block[1])
    converted_mysqldump_file_fp.write("\n")
    converted_mysqldump_file_fp.close()

    print(f"文件转换完成。\n结果文件：\"{converted_mysqldump_file}\"")

