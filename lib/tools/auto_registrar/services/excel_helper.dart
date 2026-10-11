import 'dart:convert';
import 'dart:io';

import '../models/registered_account.dart';

class ExcelHelper {
  /// 调用原生 python3 openpyxl 解析 Excel 文件的表格行，返回列表
  static Future<List<RegisteredAccount>> parseExcelFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ArgumentError('文件不存在: $filePath');
    }

    const script = r'''
import sys, json, openpyxl

file_path = sys.argv[1]
try:
    wb = openpyxl.load_workbook(file_path, data_only=True)
    ws = wb.active
    header = [str(ws.cell(row=1, column=c).value or '').strip() for c in range(1, ws.max_column + 1)]
    
    col_map = {}
    for idx, h in enumerate(header, 1):
        if '邮箱' in h or '账号' in h or 'email' in h.lower():
            col_map['email'] = idx
        elif '密码' in h or 'password' in h.lower():
            col_map['password'] = idx
        elif '姓' in h or 'lastname' in h.lower():
            col_map['lastName'] = idx
        elif '名' in h or 'firstname' in h.lower():
            col_map['firstName'] = idx
        elif '生日' in h or 'birth' in h.lower():
            col_map['birthDate'] = idx
        elif '时间' in h or 'date' in h.lower() or 'created' in h.lower():
            col_map['createdAt'] = idx
        elif '状态' in h or 'status' in h.lower():
            col_map['status'] = idx

    if 'email' not in col_map:
        col_map['email'] = 1
    if 'password' not in col_map:
        col_map['password'] = 2

    records = []
    for r in range(2, ws.max_row + 1):
        email_val = ws.cell(row=r, column=col_map.get('email', 1)).value
        if not email_val:
            continue
        email = str(email_val).strip()
        if not email:
            continue
        
        pwd = str(ws.cell(row=r, column=col_map.get('password', 2)).value or '').strip()
        last_name = str(ws.cell(row=r, column=col_map.get('lastName', 3)).value or '').strip() if 'lastName' in col_map else ''
        first_name = str(ws.cell(row=r, column=col_map.get('firstName', 4)).value or '').strip() if 'firstName' in col_map else ''
        birth = str(ws.cell(row=r, column=col_map.get('birthDate', 5)).value or '').strip() if 'birthDate' in col_map else ''
        created = str(ws.cell(row=r, column=col_map.get('createdAt', 6)).value or '').strip() if 'createdAt' in col_map else ''
        status = str(ws.cell(row=r, column=col_map.get('status', 7)).value or 'SUCCESS').strip() if 'status' in col_map else 'SUCCESS'

        records.append({
            'email': email,
            'password': pwd,
            'lastName': last_name,
            'firstName': first_name,
            'birthDate': birth,
            'createdAt': created,
            'status': status
        })
    print(json.dumps(records, ensure_ascii=False))
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
''';

    final result = await Process.run('python3', ['-c', script, filePath]);
    if (result.exitCode != 0) {
      throw StateError('Excel 解析失败: ${result.stderr}');
    }

    final rawJson = result.stdout.toString().trim();
    final decoded = jsonDecode(rawJson) as List<dynamic>;

    final accounts = <RegisteredAccount>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final email = item['email'] as String? ?? '';
        final platform = email.contains('hotmail') ? 'hotmail' : 'outlook';
        DateTime? createdAt;
        final rawCreatedAt = item['createdAt'] as String?;
        if (rawCreatedAt != null && rawCreatedAt.isNotEmpty) {
          createdAt = DateTime.tryParse(rawCreatedAt);
        }

        accounts.add(RegisteredAccount(
          platform: platform,
          email: email,
          password: item['password'] as String? ?? '',
          firstName: item['firstName'] as String? ?? '',
          lastName: item['lastName'] as String? ?? '',
          birthDate: item['birthDate'] as String? ?? '',
          status: (item['status'] as String? ?? 'SUCCESS').toUpperCase(),
          createdAt: createdAt ?? DateTime.now(),
        ));
      }
    }
    return accounts;
  }

  /// 导出为 Excel 文件
  static Future<void> exportToExcel(
    List<RegisteredAccount> accounts,
    String outputPath, {
    bool maskPassword = false,
  }) async {
    const script = r'''
import sys, json, openpyxl

out_path = sys.argv[1]
data = json.loads(sys.stdin.read())

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "已注册账号"

headers = ["平台", "邮箱账号", "密码", "姓", "名", "出生日期", "恢复邮箱", "注册时间", "状态"]
ws.append(headers)

for row in data:
    ws.append([
        row.get("platform", ""),
        row.get("email", ""),
        row.get("password", ""),
        row.get("lastName", ""),
        row.get("firstName", ""),
        row.get("birthDate", ""),
        row.get("recoveryEmail", "") or "",
        row.get("createdAt", ""),
        row.get("status", "")
    ])

wb.save(out_path)
''';

    final dataList = accounts.map((a) {
      return {
        'platform': a.platform,
        'email': a.email,
        'password': maskPassword && a.password.length > 4
            ? '${a.password.substring(0, 2)}****${a.password.substring(a.password.length - 2)}'
            : a.password,
        'lastName': a.lastName,
        'firstName': a.firstName,
        'birthDate': a.birthDate,
        'recoveryEmail': a.recoveryEmail,
        'createdAt': a.createdAt.toIso8601String(),
        'status': a.status,
      };
    }).toList();

    final process = await Process.start('python3', ['-c', script, outputPath]);
    process.stdin.write(jsonEncode(dataList));
    await process.stdin.close();

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      final err = await process.stderr.transform(utf8.decoder).join();
      throw StateError('导出 Excel 失败: $err');
    }
  }
}
