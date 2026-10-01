import 'dart:convert' as convert;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 图片块的最小宽度。与 `appflowy_editor` 内的 `ResizableImage` 取同一值，
/// 免得我们的组件比原来更容易被拖成一细条。
const double kImageMinWidth = 30.0;

/// 由「已落库宽度 + 拖拽位移」算屏幕上应呈现的宽度。
///
/// 抽成纯函数是为了能在没有编辑器、没有 widget 树的情况下单测拖拽算术——
/// 那三个易错点（下限、居中补偿、符号方向）都藏在这一次减法里。
double displayedImageWidth({
  required double committedWidth,
  required double dragDelta,
  required bool centered,
}) {
  final factor = centered ? 2.0 : 1.0;
  return math.max(kImageMinWidth, committedWidth - dragDelta * factor);
}

/// 拖拽热区宽度（左右各一条）。同样是包内同值。
const _kEdgeHotZoneWidth = 5.0;

/// 是否 base64 图片串。自带的判断而不是 `string_validator` 的 `isBase64`：
/// 那个包只是 `appflowy_editor` 的间接依赖，直接 import 它会被
/// `depend_on_referenced_packages` 拦下。
bool _isBase64(String value) => value.startsWith('data:image/');

bool _isUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://');

/// 解 base64 图片串。包里有个 `dataFromBase64String` 但它所在的
/// `base64_image.dart` 没有从 `appflowy_editor` 公开导出，够不着。
Uint8List _dataFromBase64String(String base64String) {
  final comma = base64String.indexOf(',');
  final payload = comma >= 0 ? base64String.substring(comma + 1) : base64String;
  return convert.base64Decode(payload);
}

/// 把 align 属性字符串转成 [Alignment]。
///
/// 包内有一个同名扩展（`AlignmentExtension.fromString`）但它是 `on Alignment`
/// 的静态扩展，调用处读起来像实例方法；而且我们不再复用包内的图片块，顺手
/// 用自己的小工具更直接。
Alignment imageAlignmentFromString(String? value) {
  switch (value) {
    case 'left':
      return Alignment.centerLeft;
    case 'right':
      return Alignment.centerRight;
    default:
      return Alignment.center;
  }
}

/// 图片块组件的 builder 与 widget。
///
/// **为什么不复用包内的 `ImageBlockComponentBuilder`**：它内部创建的
/// `ResizableImage` 把传入的 `width` 抄进自己的 State 字段，且只在 `initState`
/// 抄一次、没有 `didUpdateWidget`。于是拖拽边缘能改宽（直接改那个字段），
/// 而点预设百分比不能（写文档树 → 重 build → State 已存在，字段不更新）。
/// `appflowy_editor` 最新版就是 6.2.0，上游未修，且没有扩展点能替换那个
/// `ResizableImage`。所以这里自己实现一遍，宽度每次从 `node.attributes` 现读。
/// 图片块浮条的构建签名。
///
/// 不复用包内的 `ImageBlockComponentMenuBuilder`：它的第二个形参类型是包内
/// 那个 `ImageBlockComponentWidgetState`，而我们现在有自己的 State，匹配不上。
typedef NoteImageBlockMenuBuilder = Widget Function(
  Node node,
  NoteImageBlockComponentWidgetState state,
);

class NoteImageBlockComponentBuilder extends BlockComponentBuilder {
  NoteImageBlockComponentBuilder({
    this.showMenu = false,
    this.menuBuilder,
  });

  final bool showMenu;
  final NoteImageBlockMenuBuilder? menuBuilder;

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta == null && node.children.isEmpty;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    return NoteImageBlockComponentWidget(
      node: blockComponentContext.node,
      configuration: configuration,
      showActions: showActions(blockComponentContext.node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
      showMenu: showMenu,
      menuBuilder: menuBuilder,
    );
  }
}

class NoteImageBlockComponentWidget extends BlockComponentStatefulWidget {
  const NoteImageBlockComponentWidget({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
    super.showActions = false,
    super.actionBuilder,
    super.actionTrailingBuilder,
    this.showMenu = false,
    this.menuBuilder,
  });

  final bool showMenu;
  final NoteImageBlockMenuBuilder? menuBuilder;

  @override
  State<NoteImageBlockComponentWidget> createState() =>
      NoteImageBlockComponentWidgetState();
}

/// 拖拽中的中间状态。
///
/// 自绘组件必须自己区分"已落库的宽度"与"正在拖、尚未落库的偏移"——包内
/// `ResizableImage` 用两个字段 `imageWidth` / `moveDistance` 做这件事，这里
/// 收敛成一个不可变小类，便于在 `didUpdateWidget` 里整体替换。
class _DragState {
  const _DragState({
    this.committedWidth = 0,
    this.pendingDelta = 0,
    this.dragging = false,
  });

  /// 已落库（或本次拖拽起点）的宽度。
  final double committedWidth;

  /// 拖拽进行中的位移量，尚未落库。
  final double pendingDelta;

  final bool dragging;

  /// 屏幕上应呈现的宽度。
  ///
  /// 居中图片要把位移量算两份（左右各扩一半），这是包内的既有补偿；删掉它
  /// 会让居中图越拖越偏。
  double displayedWidth(Alignment alignment) => displayedImageWidth(
        committedWidth: committedWidth,
        dragDelta: pendingDelta,
        centered: alignment == Alignment.center,
      );

  _DragState copyWith({
    double? committedWidth,
    double? pendingDelta,
    bool? dragging,
  }) =>
      _DragState(
        committedWidth: committedWidth ?? this.committedWidth,
        pendingDelta: pendingDelta ?? this.pendingDelta,
        dragging: dragging ?? this.dragging,
      );
}

class NoteImageBlockComponentWidgetState
    extends State<NoteImageBlockComponentWidget>
    with SelectableMixin {
  final imageKey = GlobalKey();
  final showActionsNotifier = ValueNotifier<bool>(false);
  bool alwaysShowMenu = false;
  bool _hovering = false;

  late final EditorState editorState =
      Provider.of<EditorState>(context, listen: false);

  _DragState _drag = const _DragState();

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  Node get node => widget.node;

  double? get _storedWidth =>
      node.attributes[ImageBlockKeys.width]?.toDouble();

  Alignment get _alignment =>
      imageAlignmentFromString(node.attributes[ImageBlockKeys.align]);

  @override
  void didUpdateWidget(NoteImageBlockComponentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 这正是修掉预设缩放的那一步：文档树里的 width 变了（可能来自预设按钮，
    // 也可能来自另一个客户端），拖拽状态要按新值重算，而不是沿用出生时的值。
    final stored = _storedWidth;
    if (stored == null) return;
    // 无论当时是否在拖拽，都以新落库的宽度为基准重来。
    //
    // 拖拽中被预设打断这一路尤其要丢掉了 in-flight 偏移：否则松手时会拿一个
    // 更旧的起点回写，把预设刚设好的宽度覆盖回旧值。
    _drag = _DragState(committedWidth: stored);
  }

  @override
  Widget build(BuildContext context) {
    final src = node.attributes[ImageBlockKeys.url]?.toString() ?? '';
    final width = _storedWidth ?? _fallbackWidth();
    if (!_drag.dragging) {
      _drag = _DragState(committedWidth: width);
    }

    Widget child = Padding(
      key: imageKey,
      padding: padding,
      child: _ResizableNoteImage(
        src: src,
        width: _drag.displayedWidth(_alignment),
        height: node.attributes[ImageBlockKeys.height]?.toDouble(),
        alignment: _alignment,
        editable: editorState.editable,
        showHandle: _hovering && editorState.editable,
        onHoverChanged: (value) => setState(() => _hovering = value),
        onDragDelta: (delta) => setState(() {
          _drag = _drag.copyWith(
            committedWidth: _drag.committedWidth == 0
                ? width
                : _drag.committedWidth,
            pendingDelta: delta,
            dragging: true,
          );
        }),
        onDragCommit: () {
          final committed = _drag.displayedWidth(_alignment);
          _drag = _DragState(committedWidth: committed);
          _writeWidth(committed);
        },
      ),
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (!widget.showMenu || widget.menuBuilder == null) return child;

    return MouseRegion(
      onEnter: (_) => showActionsNotifier.value = true,
      onExit: (_) {
        if (!alwaysShowMenu) showActionsNotifier.value = false;
      },
      hitTestBehavior: HitTestBehavior.opaque,
      opaque: false,
      child: ValueListenableBuilder<bool>(
        valueListenable: showActionsNotifier,
        builder: (context, value, child) {
          return Stack(
            children: [
              child!,
              if (value) widget.menuBuilder!(widget.node, this),
            ],
          );
        },
        child: child,
      ),
    );
  }

  EdgeInsets get padding =>
      const EdgeInsets.symmetric(vertical: 6, horizontal: 0);

  /// 没有 width 属性时的兜底宽度：编辑器内容区宽度。
  double _fallbackWidth() => editorContentWidth(context);

  void _writeWidth(double width) {
    final transaction = editorState.transaction
      ..updateNode(node, {ImageBlockKeys.width: width});
    editorState.apply(transaction);
  }

  @override
  Position start() => Position(path: node.path, offset: 0);

  @override
  Position end() => Position(path: node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return Offset.zero & imageBox.size;
    }
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return null;
    final size = _renderBox!.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return [];
    final parentBox = context.findRenderObject();
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && imageBox is RenderBox) {
      return [
        imageBox.localToGlobal(Offset.zero, ancestor: parentBox) & imageBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox!.localToGlobal(offset);
}

/// 编辑器内容区宽度。
///
/// 预设百分比与拖拽都以它为基准——原先两路不同源（预设用整窗宽度、拖拽用
/// 内部像素值），导致「拖到最宽」与「点 100%」结果不一致。这里从块自身的
/// 渲染盒取宽度，取不到再退回内容区的 [MediaQuery]。
double editorContentWidth(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && box.size.width.isFinite) {
    return box.size.width;
  }
  return MediaQuery.of(context).size.width;
}

/// 图片本体 + 左右拖拽热区。
class _ResizableNoteImage extends StatefulWidget {
  const _ResizableNoteImage({
    required this.src,
    required this.width,
    required this.height,
    required this.alignment,
    required this.editable,
    required this.showHandle,
    required this.onHoverChanged,
    required this.onDragDelta,
    required this.onDragCommit,
  });

  final String src;
  final double width;
  final double? height;
  final Alignment alignment;
  final bool editable;
  final bool showHandle;
  final ValueChanged<bool> onHoverChanged;

  /// 拖拽进行中，参数为位移量（尚未落库）。
  final ValueChanged<double> onDragDelta;

  /// 拖拽结束，调用方负责把当前宽度写进文档树。
  final VoidCallback onDragCommit;

  @override
  State<_ResizableNoteImage> createState() => _ResizableNoteImageState();
}

class _ResizableNoteImageState extends State<_ResizableNoteImage> {
  double _initialOffset = 0;
  Image? _cachedImage;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        width: math.max(kImageMinWidth, widget.width),
        height: widget.height,
        child: MouseRegion(
          onEnter: (_) => setState(() => _focused = true),
          onExit: (_) => setState(() => _focused = false),
          child: Stack(
            children: [
              _buildImage(),
              if (widget.editable) ...[
                _buildEdgeGesture(
                  left: _kEdgeHotZoneWidth,
                  onUpdate: (d) => widget.onDragDelta(d),
                ),
                _buildEdgeGesture(
                  right: _kEdgeHotZoneWidth,
                  onUpdate: (d) => widget.onDragDelta(-d),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final src = widget.src;
    if (_isBase64(src)) {
      _cachedImage ??= Image.memory(_dataFromBase64String(src));
    } else if (_isUrl(src)) {
      _cachedImage ??= Image.network(
        src,
        width: widget.width,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildError(),
      );
    } else {
      _cachedImage ??= Image.file(
        File(src),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildError(),
      );
    }
    return _cachedImage!;
  }

  Widget _buildError() {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(width: 1, color: Colors.black26),
      ),
      child: const Text('图片加载失败'),
    );
  }

  Widget _buildEdgeGesture({
    double? left,
    double? right,
    required ValueChanged<double> onUpdate,
  }) {
    return Positioned(
      top: 0,
      left: left,
      right: right,
      bottom: 0,
      width: _kEdgeHotZoneWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          _initialOffset = details.globalPosition.dx;
          widget.onHoverChanged(true);
        },
        onHorizontalDragUpdate: (details) {
          var offset = details.globalPosition.dx - _initialOffset;
          if (widget.alignment == Alignment.center) {
            offset *= 2.0;
          }
          onUpdate(offset);
        },
        onHorizontalDragEnd: (_) {
          _initialOffset = 0;
          widget.onDragCommit();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: Center(
            child: (widget.showHandle && _focused)
                ? Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(width: 1, color: Colors.white),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
