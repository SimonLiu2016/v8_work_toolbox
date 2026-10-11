## ADDED Requirements

### Requirement: Compose 工程定位

系统 SHALL 通过一个可配置的目录定位 Toonflow 的 Docker Compose 工程，该目录必须同时包含 `Dockerfile` 与 `compose.yaml`。默认值 SHALL 为 `~/Workspace/github/Toonflow-app`，用户可在工具界面修改，修改后 SHALL 持久化。

系统 SHALL 在工程目录不存在、或目录中缺少上述任一文件时报告明确的定位失败原因，而不是尝试运行 Docker 命令。

#### Scenario: 默认工程目录存在

- **WHEN** 用户首次打开 Toonflow 漫剧工坊，且 `~/Workspace/github/Toonflow-app/` 下 `Dockerfile` 与 `compose.yaml` 均存在
- **THEN** 系统使用该目录作为工程目录，不要求用户输入任何配置

#### Scenario: 工程目录缺失

- **WHEN** 配置的工程目录不存在，或目录中缺少 `Dockerfile` 或 `compose.yaml`
- **THEN** 系统报告定位失败，指出具体是哪一个条件不满足，并引导用户修改工程目录配置

#### Scenario: 用户修改工程目录

- **WHEN** 用户把工程目录改为另一个包含 `Dockerfile` 与 `compose.yaml` 的有效路径并保存
- **THEN** 后续所有容器操作都作用于新目录，且重启应用后该配置仍然生效

### Requirement: 容器启停与状态呈现

系统 SHALL 支持启动与停止 Toonflow 容器组，并向用户呈现当前状态。启动流程 SHALL 包含守护进程探活、端口预检与健康就绪等待三个步骤，只有在服务真正就绪后才报告「运行中」。

系统 SHALL 在启动失败时保留失败原因，供用户修正后重试，而不是静默回到未启动状态。系统 SHALL 在引擎已在运行时忽略重复的启动请求，保持当前运行状态。

#### Scenario: 启动成功

- **WHEN** 用户在服务未运行时触发启动，且 Docker 守护进程可达、端口无冲突、镜像已存在、服务在就绪超时内通过健康探测
- **THEN** 系统报告「运行中」，状态区展示工作台地址，并提供打开工作台的入口

#### Scenario: 停止

- **WHEN** 用户在服务运行时触发停止
- **THEN** 系统停止容器组并报告「已停止」；若停止过程本身失败，系统报告失败原因而不是假装已停止

#### Scenario: 重复启动

- **WHEN** 服务已在运行时用户再次触发启动
- **THEN** 系统不重复执行启动，保持当前运行状态

### Requirement: 健康就绪判定必须校验响应体

系统 SHALL 通过 HTTP 探测判定服务就绪。判定 SHALL 校验响应体是表示服务可用的 JSON 响应，仅 HTTP 状态码为 200 不足以判定就绪。

此要求的原因是：Toonflow 的业务 API 与静态资源由同一进程提供服务，当 API 路由尚未就绪或进程异常时，静态服务可能对任意路径返回状态码 200 的 HTML 页面。只判断状态码会把「服务未就绪」误判为「已就绪」，把用户送到一个打不开的工作台。

#### Scenario: 服务真正就绪

- **WHEN** 健康探测收到 200 且响应体为 Toonflow 业务接口的 JSON 响应
- **THEN** 系统判定服务已就绪

#### Scenario: 收到 200 但不是业务接口响应

- **WHEN** 健康探测收到 200 但响应体是 HTML 或其他非 JSON 内容
- **THEN** 系统判定未就绪，继续等待直到超时，并在超时后报告「服务未返回预期的健康响应」而不是「已就绪」

#### Scenario: 就绪超时

- **WHEN** 启动后在就绪超时内健康探测始终未通过
- **THEN** 系统报告启动失败，附上容器最后若干行日志以便定位

### Requirement: 端口分配与冲突预检

系统 SHALL 为 Toonflow 的 HTTP 端口提供可配置值，默认可由实现选定但 SHALL NOT 与本软件已托管的其他引擎端口（ARTEX 的 8787 与 8788）或本地词典桥端口冲突。系统 SHALL 在启动前侦测该端口在宿主机是否已被占用；被占用时启动失败，报告被占用的端口号，并允许用户修改端口后重新启动。

#### Scenario: 端口空闲

- **WHEN** 配置端口在宿主机可绑定
- **THEN** 系统继续启动流程

#### Scenario: 端口被占用

- **WHEN** 配置的 HTTP 端口已被其他进程监听
- **THEN** 系统在启动前报告启动失败，指明端口被占用，且不启动容器

#### Scenario: 用户改端口后重试

- **WHEN** 用户把冲突端口改为空闲值并重新触发启动
- **THEN** 系统使用新端口完成启动，且就绪判定与工作台入口都指向新端口

### Requirement: 运行时配置以 override 注入而不修改上游工程文件

系统 SHALL 通过独立的 Docker Compose override 文件注入运行时配置，而不是编辑工程目录中的 `compose.yaml`。override SHALL 至少承担三项职责：按用户配置覆盖端口映射、把数据目录改为宿主机 bind mount、使容器内进程对 bind mount 的宿主机目录可写。

override 文件的生命周期由系统管理：内容随配置变化而更新，与上游工程文件互不影响，因此上游工程升级（如 `git pull`）不会丢失这些配置。系统 SHALL 在重写已存在的 override 文件前确认该文件由本工具生成（以标记注释识别），非本工具生成的文件 SHALL 先备份而不是直接覆盖。

#### Scenario: 首次生成 override

- **WHEN** 系统首次为某工程目录启动 Toonflow，且该目录中没有 override 文件
- **THEN** 系统生成 override 文件，其中包含端口映射、bind mount 与用户对齐配置

#### Scenario: 端口配置变化

- **WHEN** 用户修改端口配置
- **THEN** 系统更新 override 文件中的端口映射，使下次启动使用新端口

#### Scenario: 上游工程升级后配置不丢

- **WHEN** 上游 `compose.yaml` 被更新或替换
- **THEN** 系统生成维护的 override 文件内容保持不变，端口映射、bind mount 与用户对齐继续生效

#### Scenario: 用户手工编辑的 override 被备份

- **WHEN** 工程目录中已存在 override 文件但缺少本工具的生成标记
- **THEN** 系统备份该文件后写入自己的 override，而不是直接覆盖用户内容

### Requirement: 数据目录位于本软件数据根下且可被资产桥读写

系统 SHALL 把 Toonflow 的数据目录绑定到本软件数据根下的一个子目录（`toonflow_data/`），使资产桥能够直接通过文件系统读写工作区与素材，而不必经过 HTTP 传输媒体文件。

系统 SHALL 在首次启动前创建该目录及 `workspaces/` 子目录。系统 SHALL 在工具界面以「数据位置」卡片明确说明：该目录内的 `settings.json` 保存 Toonflow 自己的供应商密钥，本软件不读取、不修改、不导出该文件。

#### Scenario: 首次启动自动创建工作区目录

- **WHEN** 用户首次启动 Toonflow 且 `toonflow_data/` 为空
- **THEN** 系统创建 `toonflow_data/` 与 `toonflow_data/workspaces/`，并确保容器内进程对其可写

#### Scenario: 数据位置说明可见

- **WHEN** 用户打开 Toonflow 漫剧工坊工具页面
- **THEN** 系统在首次进入即可见的位置展示数据位置说明，包含 `settings.json` 的密钥边界声明，而不是仅存在于文档中

#### Scenario: 备份范围提示

- **WHEN** 用户查看数据位置说明
- **THEN** 系统说明删除本软件不会删除 Toonflow 数据，备份时需一并考虑 `toonflow_data/`

### Requirement: 镜像构建入口与失败诊断

系统 SHALL 提供触发镜像构建的入口，以流式方式向用户呈现构建进度。构建 SHALL 支持可配置的依赖源参数（包管理器镜像站）并有默认值。

系统 SHALL 对构建失败做模式识别，把已知失败类别转换为可操作提示，而不是把构建工具的原始输出直接呈现给用户。至少 SHALL 识别四类：Docker 守护进程不可达、镜像源返回 403、网络请求超时、缺少 compose 要求的环境变量。

#### Scenario: 构建进行中

- **WHEN** 用户触发构建
- **THEN** 系统以流式日志呈现构建进度，构建期间禁止重复触发

#### Scenario: Docker 未运行

- **WHEN** 触发构建或启动时 Docker 守护进程不可达
- **THEN** 系统报告「Docker 未运行」并提供跳转到 Docker 应用的方式

#### Scenario: 镜像源 403

- **WHEN** 构建输出中出现镜像源返回 403 的失败
- **THEN** 系统提示镜像加速器失效，引导用户检查或移除 Docker 的镜像源配置

#### Scenario: 网络超时

- **WHEN** 构建输出中出现请求超时或连接被取消
- **THEN** 系统提示网络不通，引导用户检查代理或 VPN，并说明已完成的构建层有缓存、重试不会从零开始

#### Scenario: 构建锁冲突被避免

- **WHEN** 构建进行中用户再次触发构建
- **THEN** 系统不发起第二次构建，而是复用当前构建的进度，不产生两个并发的 `docker compose build`

### Requirement: 打开工作台与容器未就绪时的引导

系统 SHALL 在服务就绪后提供打开工作台的入口，使用系统默认浏览器打开 `http://127.0.0.1:<配置端口>`。

工作台入口 SHALL 仅在服务就绪时可点击；未就绪时系统 SHALL 说明当前阻塞原因（未启动 / 启动中 / 失败及原因）。

#### Scenario: 就绪后打开工作台

- **WHEN** 服务状态为运行中且用户点击「打开工作台」
- **THEN** 系统用系统默认浏览器打开配置端口对应的工作台地址

#### Scenario: 未就绪时入口不可用

- **WHEN** 服务状态为未启动或启动中
- **THEN** 系统禁用「打开工作台」入口，并展示当前状态与阻塞原因

### Requirement: 应用退出时的容器处置

系统 SHALL 提供「退出时是否停止容器」的配置项，默认值为停止。系统 SHALL 在应用进程收到终止信号或主窗口关闭时按该配置处置容器，且 SHALL NOT 因为停止容器失败而阻塞应用退出。

#### Scenario: 默认退出即停

- **WHEN** 用户未修改过该配置，且 Toonflow 容器正在运行时应用退出
- **THEN** 系统停止容器组后退出，不留下继续占用端口的孤儿容器

#### Scenario: 用户配置为退出不停

- **WHEN** 用户把该配置改为退出时不停止，且容器正在运行时应用退出
- **THEN** 系统不停止容器，容器继续在后台运行，用户下次打开工具时能直接看到运行中状态

#### Scenario: 停止失败不阻塞退出

- **WHEN** 应用退出时停止容器失败或超时
- **THEN** 系统仍然完成退出，不无限期等待，并在日志中记录停止失败
