

- 每次新启动 app，都读取一次 clipboard 获取最新的数据
- dock 中隐藏 icon
  


## Clip 去重

需要为每个 clip 根据其原始数据生成唯一的 hash id，这样才能更准的进行去重 （需要好好设计一下）。

每次复制新的 Clip 之后，如果发现已经存在重复的了，则把其 createdAt 更新为最新的时间，并把其置顶到最前面。


## 不同类型 Clip 的 context menu

对于富文本、 email、颜色、 JSON 等 可能需要作为 text 的子类型。 因为其原数据的本质依然是文本

### text
- 导出为 txt 文件
- 生成二维码
  

### 富文本
- 导出为 txt, rtf
- 生成二维码

### 图片
- 另存为

### email
- 发送邮件


### 颜色
- hex 色值
- rgb 色值
- hsl 色值

### URL
- 打开链接
- 生成二维码


### JSON
- 结构化预览
