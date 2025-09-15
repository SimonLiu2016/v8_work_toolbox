#!/bin/bash

# Password Manager 发布脚本
# 功能：推送变更到 GitHub，打标签，发布新的 Release 版本

echo "========================================="
echo "  Password Manager 发布脚本             "
echo "========================================="
echo

# 检查是否在 Git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "错误: 当前目录不是 Git 仓库"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."

# 进入项目根目录
cd "$PROJECT_ROOT" || exit 1

echo "当前工作目录: $(pwd)"
echo

# 检查是否有未提交的更改
if ! git diff-index --quiet HEAD --; then
    echo "检测到未提交的更改，请先提交所有更改"
    echo "未提交的文件："
    git status --porcelain
    echo
    read -p "是否继续发布？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消发布"
        exit 1
    fi
fi

# 获取版本信息
VERSION=$(grep "version:" pubspec.yaml | cut -d ':' -f 2 | tr -d ' ' | tr -d '"')
if [ -z "$VERSION" ]; then
    echo "错误: 无法从 pubspec.yaml 获取版本信息"
    exit 1
fi

echo "当前项目版本: $VERSION"
echo

# 获取发布说明
CHANGELOG_FILE="CHANGELOG.md"
RELEASE_NOTES_FILE="docs/RELEASE_NOTES.md"

if [ -f "$RELEASE_NOTES_FILE" ]; then
    RELEASE_NOTES_PATH="$RELEASE_NOTES_FILE"
    echo "使用发布说明文件: $RELEASE_NOTES_FILE"
elif [ -f "$CHANGELOG_FILE" ]; then
    RELEASE_NOTES_PATH="$CHANGELOG_FILE"
    echo "使用更新日志文件: $CHANGELOG_FILE"
else
    echo "警告: 未找到发布说明文件"
    RELEASE_NOTES_PATH=""
fi

echo

# 设置代理（如果存在配置文件）
echo "检查代理配置..."
if [ -f "$HOME/.proxy_profile" ]; then
    echo "加载代理配置..."
    source "$HOME/.proxy_profile"
    
    # 执行代理命令（如果存在）
    if command -v proxy &> /dev/null; then
        echo "启动代理..."
        proxy
    else
        echo "未找到 proxy 命令，跳过代理设置"
    fi
else
    echo "未找到代理配置文件 ~/.proxy_profile"
fi

echo

# 确认发布信息
echo "发布信息确认："
echo "  版本号: v$VERSION"
echo "  发布说明: ${RELEASE_NOTES_PATH:-"无"}"
echo
read -p "确认发布？(y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消发布"
    exit 1
fi

echo

# 推送所有更改到远程仓库
echo "推送所有更改到远程仓库..."
git add .
git commit -m "Release version $VERSION" || echo "无更改需要提交"
git push origin main || { echo "推送失败"; exit 1; }

echo

# 创建并推送标签
echo "创建并推送标签 v$VERSION..."
git tag -a "v$VERSION" -m "Release version $VERSION"

echo "推送标签到远程仓库..."
git push origin "v$VERSION" || { echo "标签推送失败"; exit 1; }

echo

# 创建 GitHub Release（如果安装了 GitHub CLI）
if command -v gh &> /dev/null; then
    echo "检查 GitHub CLI 认证状态..."
    
    # 检查认证状态
    if gh auth status &> /dev/null; then
        echo "GitHub CLI 已认证"
        GH_AUTHENTICATED=1
    else
        echo "警告: GitHub CLI 未认证或认证已过期"
        echo "错误信息:"
        gh auth status || true
        echo
        echo "注意: 未认证的 GitHub API 请求有较低的速率限制"
        echo "建议重新认证以获得更高的速率限制和更好的体验"
        echo
        echo "请运行以下命令重新认证："
        echo "  gh auth logout -h github.com"
        echo "  gh auth login -h github.com"
        echo
        read -p "是否继续发布流程（跳过 GitHub Release 创建）？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "取消发布"
            exit 1
        fi
        GH_AUTHENTICATED=0
    fi
    
    if [[ $GH_AUTHENTICATED -eq 1 ]]; then
        echo "创建 GitHub Release..."
        
        # 准备发布说明
        if [ -n "$RELEASE_NOTES_PATH" ]; then
            # 提取版本对应的发布说明
            if [ -f "$RELEASE_NOTES_PATH" ]; then
                # 简单提取发布说明（从版本标题开始到下一个版本标题或文件结尾）
                RELEASE_NOTES_TEMP=$(mktemp)
                if [[ "$RELEASE_NOTES_PATH" == *"CHANGELOG"* ]]; then
                    # 对于 CHANGELOG 文件，提取特定版本的信息
                    awk "/\\[$VERSION\\]/,/(\\[.*\\]|^==)/" "$RELEASE_NOTES_PATH" | sed '/^==/d' > "$RELEASE_NOTES_TEMP"
                else
                    # 对于 RELEASE_NOTES 文件，使用整个文件
                    cp "$RELEASE_NOTES_PATH" "$RELEASE_NOTES_TEMP"
                fi
                
                # 创建 Release
                gh release create "v$VERSION" \
                    --title "Password Manager v$VERSION" \
                    --notes-file "$RELEASE_NOTES_TEMP"
                
                # 检查命令执行结果
                if [ $? -eq 0 ]; then
                    echo "✓ GitHub Release 创建成功"
                else
                    echo "✗ GitHub Release 创建失败"
                    echo
                    echo "可能的原因："
                    echo "1. GitHub API 速率限制 (未认证请求限制较低)"
                    echo "2. 网络连接问题"
                    echo "3. 认证信息过期"
                    echo
                    echo "解决方法："
                    echo "1. 重新认证 GitHub CLI:"
                    echo "   gh auth logout -h github.com"
                    echo "   gh auth login -h github.com"
                    echo "2. 或者手动在 GitHub 上创建 Release:"
                    echo "   访问 https://github.com/v8en/password_manager/releases/new"
                fi
                
                # 清理临时文件
                rm "$RELEASE_NOTES_TEMP"
            else
                # 没有发布说明文件，创建简单的 Release
                gh release create "v$VERSION" \
                    --title "Password Manager v$VERSION" \
                    --notes "Release version $VERSION"
                
                if [ $? -eq 0 ]; then
                    echo "✓ GitHub Release 创建成功"
                else
                    echo "✗ GitHub Release 创建失败"
                    echo
                    echo "可能的原因："
                    echo "1. GitHub API 速率限制 (未认证请求限制较低)"
                    echo "2. 网络连接问题"
                    echo "3. 认证信息过期"
                    echo
                    echo "解决方法："
                    echo "1. 重新认证 GitHub CLI:"
                    echo "   gh auth logout -h github.com"
                    echo "   gh auth login -h github.com"
                    echo "2. 或者手动在 GitHub 上创建 Release:"
                    echo "   访问 https://github.com/v8en/password_manager/releases/new"
                fi
            fi
        else
            # 没有发布说明，创建简单的 Release
            gh release create "v$VERSION" \
                --title "Password Manager v$VERSION" \
                --notes "Release version $VERSION"
            
            if [ $? -eq 0 ]; then
                echo "✓ GitHub Release 创建成功"
            else
                echo "✗ GitHub Release 创建失败"
                echo
                echo "可能的原因："
                echo "1. GitHub API 速率限制 (未认证请求限制较低)"
                echo "2. 网络连接问题"
                echo "3. 认证信息过期"
                echo
                echo "解决方法："
                echo "1. 重新认证 GitHub CLI:"
                echo "   gh auth logout -h github.com"
                echo "   gh auth login -h github.com"
                echo "2. 或者手动在 GitHub 上创建 Release:"
                echo "   访问 https://github.com/v8en/password_manager/releases/new"
            fi
        fi
    else
        echo "跳过 GitHub Release 创建"
        echo
        echo "您可以稍后手动创建 Release："
        echo "1. 重新认证 GitHub CLI (可提高 API 速率限制):"
        echo "   gh auth logout -h github.com"
        echo "   gh auth login -h github.com"
        echo "2. 或者手动在 GitHub 上创建 Release:"
        echo "   访问 https://github.com/v8en/password_manager/releases/new"
        echo "3. 选择标签 v$VERSION"
        echo "4. 标题填写: Password Manager v$VERSION"
        echo "5. 添加发布说明"
        echo "6. 点击发布"
    fi
else
    echo "未安装 GitHub CLI (gh)，跳过自动创建 Release"
    echo "请注意：未认证的 GitHub API 请求有较低的速率限制"
    echo "建议安装 GitHub CLI 并进行认证以获得更好的体验"
    echo
    echo "手动创建 Release 的步骤："
    echo "1. 访问 https://github.com/v8en/password_manager/releases/new"
    echo "2. 选择标签 v$VERSION"
    echo "3. 标题填写: Password Manager v$VERSION"
    echo "4. 添加发布说明"
    echo "5. 点击发布"
fi

echo
echo "========================================="
echo "  发布完成！                            "
echo "  版本: v$VERSION                       "
echo "========================================="