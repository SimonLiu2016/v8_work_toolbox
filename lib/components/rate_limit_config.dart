import 'package:flutter/material.dart';
import '../utils/kma_package_util.dart';

class RateLimitConfig extends StatefulWidget {
  final int maxQps;
  final int intervalMs;
  final Function(int, int) onRateLimitChanged;

  const RateLimitConfig({
    Key? key,
    required this.maxQps,
    required this.intervalMs,
    required this.onRateLimitChanged,
  }) : super(key: key);

  @override
  State<RateLimitConfig> createState() => _RateLimitConfigState();
}

class _RateLimitConfigState extends State<RateLimitConfig> {
  late TextEditingController _maxQpsController;
  late TextEditingController _intervalMsController;

  @override
  void initState() {
    super.initState();
    _maxQpsController = TextEditingController(text: widget.maxQps.toString());
    _intervalMsController = TextEditingController(
      text: widget.intervalMs.toString(),
    );
  }

  @override
  void dispose() {
    _maxQpsController.dispose();
    _intervalMsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '翻译限频配置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxQpsController,
                    decoration: const InputDecoration(
                      labelText: '最大QPS (每秒请求数)',
                      hintText: '如: 8',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      int maxQps = int.tryParse(value) ?? 8;
                      widget.onRateLimitChanged(maxQps, widget.intervalMs);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _intervalMsController,
                    decoration: const InputDecoration(
                      labelText: '时间窗口 (毫秒)',
                      hintText: '如: 1000',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      int intervalMs = int.tryParse(value) ?? 1000;
                      widget.onRateLimitChanged(widget.maxQps, intervalMs);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '说明: 限制在指定时间窗口内的最大请求数，防止API频率限制',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
