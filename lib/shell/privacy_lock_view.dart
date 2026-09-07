import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/privacy_security_service.dart';
import '../theme/app_theme.dart';

/// 隐私空间 6 位数字 PIN 码设置与解锁界面
class PrivacyLockView extends StatefulWidget {
  final VoidCallback onUnlocked;

  const PrivacyLockView({
    super.key,
    required this.onUnlocked,
  });

  @override
  State<PrivacyLockView> createState() => _PrivacyLockViewState();
}

class _PrivacyLockViewState extends State<PrivacyLockView>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();
  final PrivacySecurityService _security = PrivacySecurityService.instance;

  bool _isFirstTimeSetup = false;
  bool _isLoading = true;
  String _firstPinInput = '';
  bool _isConfirming = false;
  String _errorMessage = '';
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final hasPin = await _security.hasPin();
    if (mounted) {
      setState(() {
        _isFirstTimeSetup = !hasPin;
        _isLoading = false;
      });
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerErrorShake(String message) {
    setState(() {
      _errorMessage = message;
      _textController.clear();
    });
    _shakeController.forward(from: 0.0);
  }

  Future<void> _handlePinComplete(String pin) async {
    if (pin.length != 6) return;

    if (_isFirstTimeSetup) {
      if (!_isConfirming) {
        setState(() {
          _firstPinInput = pin;
          _isConfirming = true;
          _errorMessage = '';
          _textController.clear();
        });
        return;
      } else {
        if (pin != _firstPinInput) {
          _triggerErrorShake('两次输入的 PIN 码不一致，请重试');
          setState(() {
            _isConfirming = false;
            _firstPinInput = '';
          });
          return;
        }

        final success = await _security.setupPin(pin);
        if (success && mounted) {
          widget.onUnlocked();
        } else if (mounted) {
          _triggerErrorShake('PIN 码设置失败，请重试');
        }
      }
    } else {
      final success = await _security.verifyAndUnlock(pin);
      if (success && mounted) {
        widget.onUnlocked();
      } else if (mounted) {
        _triggerErrorShake('PIN 码错误，请重新输入');
      }
    }
  }

  void _onDigitPressed(String digit) {
    if (_textController.text.length < 6) {
      final newText = _textController.text + digit;
      _textController.text = newText;
      setState(() {
        _errorMessage = '';
      });
      if (newText.length == 6) {
        _handlePinComplete(newText);
      }
    }
  }

  void _onBackspacePressed() {
    final text = _textController.text;
    if (text.isNotEmpty) {
      _textController.text = text.substring(0, text.length - 1);
      setState(() {
        _errorMessage = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentPin = _textController.text;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final char = event.character;
          if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
            _onDigitPressed(char);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _onBackspacePressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(AppTheme.space32),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppTheme.accent,
                    size: 32,
                  ),
                ),
                const SizedBox(height: AppTheme.space20),

                // 标题
                Text(
                  _isFirstTimeSetup
                      ? (_isConfirming ? '再次确认 PIN 码' : '设置隐私空间 PIN 码')
                      : '隐私空间安全锁',
                  style: AppTheme.fontTitle.copyWith(fontSize: 20),
                ),
                const SizedBox(height: AppTheme.space8),

                // 副标题
                Text(
                  _isFirstTimeSetup
                      ? (_isConfirming ? '请再次输入 6 位数字以完成设置' : '请输入 6 位纯数字安全密码')
                      : '此空间受密码保护，请输入 6 位 PIN 码以继续',
                  style: AppTheme.fontCaption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28.0),

                // 6 位数字圆点显示槽位 (带抖动动画)
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final offset = 10 *
                        (1 - _shakeController.value) *
                        (1 - _shakeController.value) *
                        (1 - _shakeController.value) *
                        (3 * (1 - _shakeController.value) - 2) *
                        1.5;
                    return Transform.translate(
                      offset: Offset(
                        _shakeController.isAnimating
                            ? (offset * ((_shakeController.value * 12).toInt() % 2 == 0 ? 1 : -1))
                            : 0,
                        0,
                      ),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      final hasDigit = index < currentPin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 42,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasDigit
                                ? AppTheme.accent
                                : AppTheme.borderSubtle,
                            width: hasDigit ? 1.5 : 1.0,
                          ),
                        ),
                        child: Center(
                          child: hasDigit
                              ? Container(
                                  width: 14,
                                  height: 14,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.accent,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }),
                  ),
                ),

                // 错误提示
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.space12),
                  Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 13,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: AppTheme.space20),
                ],

                const SizedBox(height: AppTheme.space16),

                // 软键盘数字面板
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Column(
                    children: [
                      for (int r = 0; r < 3; r++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (int c = 1; c <= 3; c++)
                                _buildNumButton('${r * 3 + c}'),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildActionButton(
                            icon: Icons.clear_rounded,
                            onTap: () {
                              setState(() {
                                _textController.clear();
                                _errorMessage = '';
                              });
                            },
                          ),
                          _buildNumButton('0'),
                          _buildActionButton(
                            icon: Icons.backspace_outlined,
                            onTap: _onBackspacePressed,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumButton(String num) {
    return InkWell(
      onTap: () => _onDigitPressed(num),
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Center(
          child: Text(
            num,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            icon,
            color: AppTheme.textSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
