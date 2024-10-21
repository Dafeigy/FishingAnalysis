## 钓鱼单历史数据分析

此次工作需要分析找到“乌龙指”。查询乌龙指相关定义为**股票中的“乌龙指”是指股票交易员、操盘手、股民等在交易的时候，不小心敲错了价格、数量、买卖方向等事件的统称,会引起股价的瞬间急剧波动。**群内给出的例子以及网上查询到的例子有：

- [中证1000期指主力合约IM2211合约一度触及跌停](https://finance.sina.com.cn/money/gzqh/futuresyspzx/2022-11-08/doc-imqmmthc3741398.shtml)： 开盘集合竞价阶段，市场曾出现一次6045.4点位的空头开仓成交，成交手数为83手。随后，9点30分开盘，该合约报价回升至6710点左右。

简单来讲就是产品中异常的接近涨/跌停的幅度变化。因此考虑两个目标来寻找乌龙指:

- DESIRED_1: 超过 10% 的涨跌的数据(和最新价对比)；

- DESIRED_2: 超过 4% 但不足 10% 的涨跌数据；

选取该两个数值主要是参考了《[华泰期货股指期货专题——历史上的乌龙指](https://htfc.com/wz_upload/png_upload/20220207/164421442828641a450.pdf)》这一篇文章的数据，期货产品的交易间隔时间较短，如果在相邻的两个数据之间出现了上述两个指标所对应的涨跌，那么肯定有异常情况出现，届时再通过人的二次检验对搜索出来的异常指标进行检验判断是否为乌龙指。



本次数据分析的目标旨在通过**寻找乌龙指的历史情况，从出现时间、出现位置以及频率等三个主要方面进行考察分析**，并根据结果考虑构建合适的钓鱼单进而获取最大收益。接下来的任务是需要找到在交易期间的目标数据。参考的数据来自服务器，涵盖2017年至2024年9月的期货tick数据，数据量较大。整体思路如下:

- 确定最小处理单元：以月份作为最小单元，对每一个月份下的数据进行汇总。汇总信息以Log形式保存，要方便读取到所需的乌龙指数据信息。最后的数据处理方法将按月份输出结果。

- 确定数据处理方法：以单个`.txt`文件为例，主要观察字段`last_price`的变化涨跌程度。主要的异常处理为无效的数据、未在开盘时间的数据，计算方法直接通过百分比函数计算得到中间结果即可。随后对得到的中间结果进行遍历，定位找到原始数据中的异常时间点。

- 工程实现：考虑到数据量大，服务器配备的CPU为多核低基频，因此考虑多线程跑程序。不会产生冲突，因为文件的IO都以月份为单元进行输出，不存在冲突问题。

- 最终处理：使用`grep`命令将目录下的所有Log中报Warning的部分重定向到一个新文件，然后在新文件中比对结果校验结果。

## 代码逻辑与结构

导入使用的库，并编写处理数据的函数：

```python
import numpy as np
import pandas as pd
import os
import math

DESIRED_1 = 0.1
DESIRED_2 = 0.04

def find_txt_files(directory: str) -> list[str]:
    """
    Find All txt files in required directory.
    """
    txt_files = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.txt'):
                txt_files.append(os.path.join(root, file))
    return txt_files

def process_month(directory: str, show_progress = True)->None:
    '''
    Find exception values fluctuate in target `dir` (in YYYY/MM/ format). Processing will be done in multi-thread.
    Each thread will saved processed log in `dir` as `output.log`.

    params: `dir`: str, Restricted to YYYY/MM level. DO NOT USE YYYY level or DD level dir!!! 
    '''
    txt_files = find_txt_files(directory)
    task_size = len(txt_files)
    fall_count = 0
    import time
    st = time.time()
    if show_progress:
        print(f"[Info] Processing {directory} now!")
    with open(rf"{directory}/output.log",'w') as f :
        for i, pth in enumerate(txt_files):
            # Note : Try to open target file:
            try:
                data = pd.read_csv(pth, sep="|")
                f.writelines(f"[Info] Processing {pth} now ({i + 1}/{task_size})>>>\n")
            except:
                f.writelines(f"[Error] Failed to open {pth}! \n")
                fall_count += 1
                continue
            # Note: Calculate Desired index and record it.
            try:
                req = data['last_price'].pct_change().fillna(0).tolist()
                # del data
                # print("HI")
                for i, sample in enumerate(req):
                    if sample >= 1.:    # 不可能自身马上翻倍，或从0翻到inf，出现这种情况就是时间不对,
                        continue
                    elif sample >= DESIRED_1:
                        f.writelines(f"[Warning] Over {DESIRED_1 * 100}% Exception :{sample} Index found in {pth}:{i+1}\n")
                    elif sample >= DESIRED_2:
                        f.writelines(f"[Warning] Over {DESIRED_2 * 100}% Exception :{sample} Index found in {pth}:{i+1}\n")
                    else:
                        continue
                        
            except:
                f.writelines(f"[Error] Cannot Calculate pct_change in {pth}!!!\n")
                fall_count += 1
                continue
        f.writelines(f"\n[Info] All Task Finished. Failed: {fall_count}, Use Time: {time.time() - st} secs.\n")
```

定义函数结束后，使用多线程加快数据的搜索与处理过程。服务器的CPU为Intel@ 6226R Golden,有较多的核心但线程数一般。考虑一般处理一个月的数据耗时为15秒，故选择多线程把64个核都吃满来跑。由于CPU本身基频不高，即便有权限设置工作在最高频率也不会有太大提升，因此就是用默认的硬件设置来运行程序即可，预估运行时间为30分钟左右：

```python
import time
import concurrent
tasks = [rf"Tick/{year}/{month}" for year in range(2017,2024) for month in range(1,13)]
t1 = time.time()
with concurrent.futures.ThreadPoolExecutor() as executor:
    # 使用map函数将my_function应用到data的每个元素上
    # map函数会返回一个迭代器，其中包含my_function应用到data每个元素的结果
    results = executor.map(process_month, tasks)
t2 = time.time()
print(rf"ThreadPool Executer using {t2-t1} to process.")
```

## 搜索结果处理

我构建了一个bash脚本用于搜索每个月份中的异常数据。具体而言是利用`grep`命令进行搜索，并将搜索结果输出到一个文件中，因此编写一个bash脚本将搜索的结果保存到`result.log`文件里：

```bash
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
```

之所以没有将2024加入搜索列表，是因为2024年国内暂时未发生有乌龙指相关的新闻，故排除掉了。我们一窥输出结果`result.log`:

- [x] ./Tick/2017/1/output.log:368:[Warning] Over 4.0% Exception :0.043724483076517995 Index found in Tick/2017/1/23/IC1703.CFFEX.txt:94
- [ ] ./Tick/2017/3/output.log:258:[Warning] Over 4.0% Exception :0.09457413249211366 Index found in Tick/2017/3/17/IC1706.CFFEX.txt:3
- [x] ./Tick/2017/3/output.log:259:[Warning] Over 4.0% Exception :0.05245304353288516 Index found in Tick/2017/3/17/IC1706.CFFEX.txt:102
- [x] ./Tick/2017/3/output.log:472:[Warning] Over 4.0% Exception :0.08860283754580478 Index found in Tick/2017/3/14/IH1703.CFFEX.txt:9700
- [x] ./Tick/2017/8/output.log:470:[Warning] Over 4.0% Exception :0.0653922798730533 Index found in Tick/2017/8/25/IH1803.CFFEX.txt:5716
- [x] ./Tick/2018/5/output.log:540:[Warning] Over 10.0% Exception :0.10017587845676013 Index found in Tick/2018/5/23/IC1809.CFFEX.txt:4207
- [ ] ./Tick/2018/7/output.log:28:[Warning] Over 4.0% Exception :0.09178743961352653 Index found in Tick/2018/7/11/IH1808.CFFEX.txt:6
- [x] ./Tick/2018/10/output.log:66:[Warning] Over 4.0% Exception :0.06801301034030782 Index found in Tick/2018/10/31/IC1906.CFFEX.txt:8190
- [x] ./Tick/2019/9/output.log:468:[Warning] Over 4.0% Exception :0.06959767275920736 Index found in Tick/2019/9/23/IF2003.CFFEX.txt:56
- [x] ./Tick/2020/2/output.log:309:[Warning] Over 4.0% Exception :0.0956210902591601 Index found in Tick/2020/2/10/IC2006.CFFEX.txt:2295
- [ ] ./Tick/2020/4/output.log:601:[Warning] Over 4.0% Exception :0.05982668042134365 Index found in Tick/2020/4/20/000852.SH.txt:18
- [x] ./Tick/2020/7/output.log:421:[Warning] Over 4.0% Exception :0.05020326514809326 Index found in Tick/2020/7/3/IH2009.CFFEX.txt:93
- [x] ./Tick/2020/7/output.log:444:[Warning] Over 4.0% Exception :0.0674608486146433 Index found in Tick/2020/7/16/IH2012.CFFEX.txt:13301
- [ ] ./Tick/2020/12/output.log:37:[Warning] Over 4.0% Exception :0.04262471426650527 Index found in Tick/2020/12/21/IC2102.CFFEX.txt:2
- [x] ./Tick/2022/11/output.log:134:[Warning] Over 10.0% Exception :0.11056340357958128 Index found in Tick/2022/11/8/IM2211.CFFEX.txt:2
- [ ] ./Tick/2023/8/output.log:386:[Warning] Over 4.0% Exception :0.05530205088991136 Index found in Tick/2023/8/28/000852.SH.txt:316
- [ ] ./Tick/2023/8/output.log:390:[Warning] Over 4.0% Exception :0.05474633200096024 Index found in Tick/2023/8/28/399300.SZ.txt:16
- [ ] ./Tick/2023/8/output.log:399:[Warning] Over 4.0% Exception :0.050577565133955726 Index found in Tick/2023/8/28/000001.SH.txt:317
- [ ] ./Tick/2023/8/output.log:405:[Warning] Over 4.0% Exception :0.054588989243840924 Index found in Tick/2023/8/28/000905.SH.txt:316
- [ ] ./Tick/2023/8/output.log:407:[Warning] Over 4.0% Exception :0.05470589483959554 Index found in Tick/2023/8/28/000906.SH.txt:316
- [ ] ./Tick/2023/8/output.log:410:[Warning] Over 4.0% Exception :0.05109047100826647 Index found in Tick/2023/8/28/000016.SH.txt:317
- [ ] ./Tick/2023/8/output.log:415:[Warning] Over 4.0% Exception :0.054588989243840924 Index found in Tick/2023/8/28/399905.SZ.txt:16
- [ ] ./Tick/2023/8/output.log:427:[Warning] Over 4.0% Exception :0.05474633200096024 Index found in Tick/2023/8/28/000300.SH.txt:316

其中被勾选的数据是经过我人为检验确认为乌龙指情况的数据，其他未被勾选的大多为盘前竞价的高开数据，并不是乌龙指。可以观察到2017年至20023年一共有13次乌龙指数据，这个数据对比华泰那篇文章列举的少了很多，但是通过检查我们的原始数据发现，**有部分合约的相关信息我们并没有获取到**，比如说20170116的IF1707；我们能找到一些**华泰并没有记录的数据**，比如20181031的IC1906；我们还发现通过对比数据发现，华泰文章中指出的20220128的IH2203并**没有出现乌龙指的情况**。

![华泰证券结果](https://s2.loli.net/2024/10/21/FGeZRX7mcIH4Aoz.png)

## 最终结果呈现

得到了数据后我们可以进行一些分析了。首先是乌龙指出现的频次：

![](imgs/Num%20of%20Woolong%20per%20year.jpg)

可以观测到乌龙指出现的次数正在逐年下降，17年市场的乌龙指特别多。那么乌龙指出现的时间点有什么特点吗？我们通过直方图可视化一下：

![](imgs/When%20woolong%20occurs.jpg)

出现乌龙指的时间基本都集中在早上的9:30分左右，因此我们考虑可以在早上9：30分左右或者开盘的时间对期货市场进行监控，看看是否可以构建钓鱼单机会；相对的其他出现乌龙指的时间则比较随机地分布在下午的时间段，没有太明显的规律而言。那么哪些期货最容易出现乌龙指呢?

![](imgs/Which%20kind%20of%20Woolong%20comes%20most.jpg)

似乎IC和IH相关的期货会出现更多的乌龙指，同时还需要注意，乌龙指很少会（因为我没有以前的数据来对比）出现在同一个期货合约上，因此在钓鱼时考虑选择一些不那么热门的合约进行钓鱼可以增加成功概率。

## 总结

综上所述，根据分析结果来看，乌龙指出现的概率会越来越小，如果考虑要做钓鱼单的话，可以**考虑在冷门市场、近年未出现过乌龙指的合约上，于早上开盘或9：30-10：00的时间进行实验**，观察是否可以成功钓鱼。
