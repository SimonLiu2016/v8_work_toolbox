import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/clipboard_service.dart';
import '../services/totp_service.dart';

/// TOTP 徽章（spec：TOTP two-factor codes）
///
/// 显示当前 6 位码 + 剩余秒数倒计时 + 上一码/下一码辅助显示。
class TotpBadge extends StatefulWidget {
  const TotpBadge({super.key, required this.seed});

  final String seed;

  @override
  State<TotpBadge> createState() => _TotpBadgeState();
}

class _TotpBadgeState extends State<TotpBadge> {
  final TotpService _totp = TotpService();
  Timer? _timer;
  String _current = '------';
  String _prev = '';
  String _next = '';
  int _remaining = 30;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    try {
      final now = DateTime.now();
      final current = _totp.generateCode(widget.seed, time: now);
      final prev = _totp.generateCode(widget.seed, time: now, periodOffset: -1);
      final next = _totp.generateCode(widget.seed, time: now, periodOffset: 1);
      final remaining = _totp.remainingSeconds(time: now);
      if (mounted) {
        setState(() {
          _current = current;
          _prev = prev;
          _next = next;
          _remaining = remaining;
          _invalid = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('TOTP Seed 无效',
            style: TextStyle(color: context.errorText, fontSize: 12)),
      );
    }
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('两步验证码',
                    style:
                        TextStyle(color: context.textTertiary, fontSize: 11)),
                SizedBox(height: 4),
                Text(
                  '${_current.substring(0, 3)} ${_current.substring(3)}',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '上一码 $_prev · 下一码 $_next',
                  style: TextStyle(
                      color: context.textTertiary, fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _remaining / 30,
                      strokeWidth: 3,
                      color: _remaining <= 5
                          ? context.errorSolid
                          : context.accentSolid,
                      backgroundColor: context.borderSubtle,
                    ),
                    Text(
                      '$_remaining',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  await ClipboardHygieneService.instance.copySecret(_current);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('验证码已复制'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded,
                      size: 16, color: context.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
