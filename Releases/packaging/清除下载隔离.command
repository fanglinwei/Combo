#!/bin/zsh
set -eu
app="/Applications/Combo.app"
result=0
printf 'Combo 清除下载隔离\n递归清除 Combo 的扩展属性，包括下载隔离属性。\n\n'
if [[ ! -d "$app" ]]; then
  printf '未找到 %s\n请先将 Combo 拖入 Applications，再运行此脚本。\n' "$app"
  result=1
elif sudo /usr/bin/xattr -cr "$app"; then
  printf '\n已完成，请从「应用程序」重新打开 Combo。\n'
else
  printf '\n未能完成处理，请检查终端中的错误信息后重试。\n'
  result=1
fi
printf '\n按回车结束…'
read -r reply || true
exit "$result"
