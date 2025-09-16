# 文件夹对比工具使用说明

## 功能说明

文件夹对比工具用于对比两个文件夹中同名文件的内容差异，支持多种文件格式（目前实现 YAML 格式），并可将差异结果导出为 CSV 文件。

## 使用方法

### 1. 选择文件夹

- 点击"选择"按钮选择要对比的第一个文件夹
- 点击"选择"按钮选择要对比的第二个文件夹

### 2. 配置对比参数

- **文件类型**：选择要对比的文件类型（目前支持 YAML）
- **过滤重复记录**：勾选此选项可过滤掉两个文件夹中值完全相同的记录
- **Key 表达式**：指定用于标识文件内容的键表达式（如：Name）
- **Value 表达式**：指定要对比的值表达式，多个表达式用逗号分隔（如：Envs[0].value[0-14],ReplicaCount）

### 3. 开始对比

点击"开始对比"按钮，工具将自动对比两个文件夹中的同名文件，并显示差异结果。

### 4. 导出结果

如果发现差异，可以点击"导出结果"按钮将差异结果保存为 CSV 文件。

## 表达式语法说明

### YAML 文件表达式

- **简单路径**：直接使用键名，如 `Name`
- **嵌套路径**：使用点号分隔，如 `Metadata.Name`
- **数组访问**：使用方括号指定索引，如 `Envs[0].value`
- **字符串截取**：使用方括号指定范围，如 `Envs[0].value[0-14]` 表示截取 value 字段的第 0 到 14 个字符

## 示例

假设有两个文件夹，都包含文件 `values-dc-jd-goods.yaml`：

第一个文件内容：

```
Envs:
- name: JAVA_MEM_OPTIONS
  value: -Xmx4g -Xms4g -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:/tmp/log/gc-%t.log
    -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M -XX:HeapDumpPath=/tmp/log/ -XX:+HeapDumpOnOutOfMemoryError
    -XX:NewRatio=2 -XX:SurvivorRatio=4
Name: dc-jd-goods
ReplicaCount: 3
```

第二个文件内容：

```
Envs:
- name: JAVA_MEM_OPTIONS
  value: -Xmx2g -Xms2g -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:/tmp/log/gc-%t.log
    -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M -XX:HeapDumpPath=/tmp/log/dump.hprof
    -XX:NewRatio=2 -XX:SurvivorRatio=4
Name: dc-jd-goods
ReplicaCount: 2
```

配置参数：

- Key 表达式：`Name`
- Value 表达式：`Envs[0].value[0-14],ReplicaCount`

对比结果将显示：

- 服务名：dc-jd-goods
- 第一个文件夹的 JVM 参数：-Xmx4g -Xms4g -（截取前 15 个字符）
- 第二个文件夹的 JVM 参数：-Xmx2g -Xms2g -（截取前 15 个字符）
- 第一个文件夹的副本数：3
- 第二个文件夹的副本数：2

## 导出格式

导出的 CSV 文件包含以下列：

1. 服务名
2. 文件名
3. 第一个文件夹的值 1
4. 第二个文件夹的值 1
5. 第一个文件夹的值 2
6. 第二个文件夹的值 2
   ...
