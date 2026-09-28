import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../models/ops_models.dart';

class EmailService {
  EmailService._();
  static final EmailService instance = EmailService._();

  SmtpServer _buildSmtpServer(EmailAccount account) {
    return SmtpServer(
      account.smtpHost,
      port: account.smtpPort,
      ssl: account.useTls && account.smtpPort == 465,
      allowInsecure: !account.useTls,
      ignoreBadCertificate: true,
      username: account.username,
      password: account.password,
    );
  }

  Future<void> testConnection(EmailAccount account) async {
    final server = _buildSmtpServer(account);
    // Send a test connection verification
    final connection = PersistentConnection(server);
    try {
      // Check if server is reachable and credentials are valid
      final msg = Message()
        ..from = Address(account.username, account.name)
        ..recipients.add(Address(account.username, account.name))
        ..subject = 'V8WorkToolbox SMTP 连接测试'
        ..text = '连接测试成功，这是一封由运维工具箱发起的连通性校验邮件。';

      await connection.send(msg);
    } finally {
      await connection.close();
    }
  }

  Future<void> sendReportEmail({
    required EmailAccount account,
    required List<EmailRecipient> recipients,
    required String subject,
    required String htmlContent,
  }) async {
    if (recipients.isEmpty) {
      throw Exception('请至少选择一个收件人');
    }

    final server = _buildSmtpServer(account);
    final msg = Message()
      ..from = Address(account.username, account.name)
      ..recipients.addAll(recipients.map((r) => Address(r.email, r.name)))
      ..subject = subject
      ..html = htmlContent;

    await send(msg, server);
  }
}
