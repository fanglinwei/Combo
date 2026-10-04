#!/bin/zsh
set -eu
result=0
printf '允许安装任意来源（可选）\n此操作用于显示系统的「任何来源」选项，会影响其他 App 的来源限制。\n\n'
if sudo /usr/sbin/spctl --global-disable; then
  printf '\n命令已完成，还需手动确认：\n系统设置 → 隐私与安全性 → 安全性\n在「允许从以下位置下载的 App」中选择「任何来源」，按系统提示确认。\n'
  printf '\n安装 Combo 并不要求开启此选项。使用后可选回「App Store 和被认可的开发者」。\n'
else
  printf '\n未能显示该选项，请检查终端中的错误信息。受单位管理的 Mac 可能限制此设置。\n'
  result=1
fi
printf '\n按回车结束…'
read -r reply || true
exit "$result"
