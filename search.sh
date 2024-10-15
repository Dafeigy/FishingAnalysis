#!/bin/bash

# 定义年份和月份范围
YEARS=(2017 2018 2019 2020 2021 2022 2023)
MONTHS=(1 2 3 4 5 6 7 8 9 10 11 12)

# 定义结果文件
RESULT_FILE="result.log"

# 清空结果文件
> $RESULT_FILE

# 遍历年份和月份
for YEAR in "${YEARS[@]}"; do
  for MONTH in "${MONTHS[@]}"; do
    # 构建目录路径
    DIR_PATH="./Tick/${YEAR}/${MONTH}"
    # echo "$YEAR/$MONTH: OMG"
    # 检查目录是否存在
    if [ -d "$DIR_PATH" ]; then
      # 使用grep搜索包含"over"的.log文件，并将结果追加到结果文件中
      grep -inr "over" --include=*.log "$DIR_PATH" >> $RESULT_FILE
    fi
  done
done

# 输出完成信息
echo "搜索完成，结果已保存到 $RESULT_FILE"