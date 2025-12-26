#!/bin/bash

# 执行当前脚本时，传入一个提交说明即可，例如：./push_codes.sh "Update codes"

# 启用别名扩展并执行 proxy 命令
shopt -s expand_aliases
source ~/.proxy_profile

export http_proxy=http://127.0.0.1:6160
export https_proxy=http://127.0.0.1:6160
export all_proxy=http://127.0.0.1:6160
export no_proxy=http://127.0.0.1:6160
export HTTP_PROXY=http://127.0.0.1:6160
export HTTPS_PROXY=http://127.0.0.1:6160
export ALL_PROXY=http://127.0.0.1:6160
export NO_PROXY=http://127.0.0.1:6160
export GOPROXY=https://goproxy.io
export G0111MODULE=on

# 提交代码
git add .
git commit -m "$1"
git push
