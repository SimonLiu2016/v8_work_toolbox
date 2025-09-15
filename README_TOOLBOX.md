# 文件工具箱

这是一个基于 Flutter 开发的 macOS 应用程序，包含多个实用的文件处理工具。

## 功能特性

### 1. Beyond Compare 配置工具

- 自动修改 Beyond Compare 的配置文件
- 删除更新检查相关的 CheckID 和 LastChecked 标签
- 删除 BCSessions.xml 文件中的 Flags 属性
- 自动启动 Beyond Compare 应用程序

### 2. 批量重命名工具

- 支持按正则表达式规则批量重命名文件
- 可预览重命名结果
- 安全执行重命名操作

## 使用方法

### 运行开发版本

```bash
flutter run -d macos
```

### 构建发布版本

```bash
flutter build macos
```

构建后的应用程序位于: `build/macos/Build/Products/Release/V8WorkToolbox.app`

## 批量重命名工具使用说明

### 示例场景

将文件夹中所有符合 `$(service)-pet.yml` 格式的文件重命名为 `$(service).yml` 格式：

1. 在"匹配模式"中输入正则表达式: `^(.*)-pet\.yml$`
2. 在"替换格式"中输入: `$1.yml`
3. 点击"预览"查看重命名结果
4. 确认无误后点击"执行"完成重命名

### 正则表达式说明

- `^` 表示字符串开始
- `(.*)` 捕获组，匹配任意字符任意次数
- `-pet\.yml` 匹配字面量 "-pet.yml"（注意点号需要转义）
- `$` 表示字符串结束
- `$1` 在替换中引用第一个捕获组的内容

## 开发说明

### 项目结构

- `lib/main.dart` - 主应用程序入口和工具选择界面
- `lib/bc_config_tool.dart` - Beyond Compare 配置工具
- `lib/batch_rename_tool.dart` - 批量重命名工具

### 添加新工具

1. 创建新的工具页面文件
2. 在 `lib/main.dart` 中导入新工具
3. 在主界面的 GridView 中添加新的工具卡片
