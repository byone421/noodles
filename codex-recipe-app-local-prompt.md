# 食作簿：Flutter 本地菜谱 App 开发提示词

## 任务

我已经创建好了一个空的 Flutter 项目。请把它开发成一个纯本地个人菜谱记录 App，暂定名称为「食作簿」。

如果项目目录中存在 `index.html`，请先读取它。它是已有的视觉和交互参考文件，请提取其中的页面结构、颜色、间距、卡片、按钮、手机壳、搜索、分类筛选、详情页、版本切换、成品照片区域和底部导航设计，然后使用 Flutter 原生组件重建。

不要把 HTML 嵌入 Flutter，不要删除或覆盖 `index.html`，不要把 `index.html` 当作运行入口。

## 强约束

- 所有数据只保存在本机。
- 不使用任何云端服务。
- 不使用 Supabase。
- 不使用 Firebase。
- 不使用登录、注册、账号、云同步或远程 API。
- 不使用远程图片 URL。
- 菜谱、版本、材料、步骤、评分、备注和照片路径都使用本地数据。
- 开始编码前，先检查项目目录、Flutter 版本、现有文件和 `index.html`。
- 不要在没有读取现有文件的情况下覆盖项目内容。
- 先输出项目分析、`index.html` 设计分析、拟修改文件和实现计划，再开始编码。

## 技术栈

使用以下技术：

- Flutter
- Dart
- Material 3
- Riverpod
- SQLite
- `sqflite`
- `path_provider`
- `path`
- `intl`
- `image_picker`

如果确实需要其他依赖，先说明用途。不要为了未来扩展添加网络层、同步层或复杂架构。

数据库访问必须集中在 Repository 层，页面和 Widget 不允许直接执行 SQL。

## 产品目标

用户可以：

- 创建菜谱
- 记录材料
- 记录制作步骤
- 记录成品照片
- 记录评分和复盘
- 为同一道菜创建多个版本
- 修改版本的材料和步骤
- 对比两个版本的差异
- 搜索菜谱
- 按分类筛选菜谱
- 收藏菜谱
- 标记最喜欢的版本

核心价值：记录每次尝试，并通过版本对比找到更好的做法。

## 视觉方向

请延续 `index.html` 的视觉语言：

- 安静、可信、像个人厨房日志
- 低饱和深绿色主色
- 中性浅色背景
- 白色内容卡片
- 少量橙色强调
- 移动端优先
- 支持 375px 宽度
- 不允许横向溢出
- 不做成电商或社交媒体风格
- 不使用紫色渐变、玻璃拟态、霓虹发光和过度圆角
- 不使用 Emoji 作为功能图标
- 使用 Flutter 图标和语义化控件

参考颜色：

```text
背景：#F4F5F0
主文字：#17231F
辅助文字：#68756E
主色：#286B58
深色主色：#174C3E
浅绿色：#EAF1EC
强调色：#D98B45
边框：#DCE4DD
白色：#FFFFFF
```

所有颜色、字号、间距、圆角和阴影集中定义在 Theme 或设计常量中，不要散落硬编码。

## 页面范围

底部只保留两个 Tab：

1. 菜谱
2. 我的

不要创建“记录”Tab。

### 一、菜谱首页

实现：

- 顶部标题「食作簿」
- 搜索框
- 分类筛选
- 菜谱列表
- 收藏入口
- 新建菜谱按钮
- 空状态
- 搜索无结果状态

分类：

- 全部
- 家常菜
- 快手菜
- 面食
- 汤羹
- 烘焙

菜谱卡片显示：

- 菜谱名称
- 分类
- 一句话简介
- 版本数量
- 最近更新时间
- 当前最佳评分
- 收藏状态
- 最近一次成品照片，如果有

搜索必须支持：

- 按名称搜索
- 按简介搜索
- 和分类筛选组合使用
- 实时更新结果

### 二、新建菜谱页

新建菜谱使用单页表单，不使用分步骤流程。

字段：

- 菜谱名称，必填
- 分类，必选
- 一句话简介，可选
- 第一版材料，可选
- 第一版步骤，可选

要求：

- 每个输入框都有可见 Label
- 菜谱名称为空时不能提交
- 错误提示要说明原因和解决方式
- 点击创建后保存到 SQLite
- 在同一事务中自动创建版本 1
- 创建成功后进入详情页并显示反馈
- 新增页保持轻量，不放评分、成品照片、复盘和改进方向

### 三、菜谱详情页

显示：

- 菜谱名称
- 分类
- 简介
- 收藏按钮
- 版本数量
- 所有版本列表
- 当前选中的版本
- 当前版本评分
- 当前版本说明
- 材料列表
- 制作步骤
- 成品照片展示区域
- 成品复盘
- 下次改进方向

操作：

- 切换版本
- 新建版本
- 复制当前版本
- 编辑当前版本
- 删除版本
- 对比两个版本
- 标记为最佳版本
- 添加或更换成品照片
- 添加复盘备注
- 返回首页

成品照片要求：

- 使用本地照片选择
- 只保存本地文件路径
- 不使用远程图片 URL
- 没有照片时显示明确的“暂无成品照片”状态
- 不使用无意义的灰色占位框
- 图片保持原始比例，不拉伸、不错误裁切

### 四、编辑版本页

字段：

- 版本名称或版本编号
- 版本说明
- 材料列表
- 制作步骤
- 评分
- 成品照片
- 成品反馈
- 下次改进方向

材料支持：

- 新增
- 编辑
- 删除
- 调整顺序

每种材料包含：

- 名称
- 数量
- 单位

步骤支持：

- 新增
- 编辑
- 删除
- 调整顺序

如果实现拖拽排序，使用 Flutter 原生 `ReorderableListView`，不要额外引入排序依赖。

### 五、版本对比页

允许选择同一道菜的两个版本进行对比。

对比：

- 版本名称和说明
- 材料新增、删除和用量变化
- 步骤新增、删除、内容变化和顺序变化
- 评分变化
- 成品照片
- 成品反馈
- 下次改进方向

差异不能只依赖颜色，必须同时使用文字和图标：

```text
新增：冰糖 10g
删除：土豆 1 个
修改：番茄 2 个 → 3 个
步骤修改：炖煮 60 分钟 → 70 分钟
评分变化：4.2 → 4.8
```

### 六、我的页面

设计并实现“我的”页面，包含：

- 个人厨房日志标题
- 简短介绍
- 菜谱总数
- 版本总数
- 收藏数量
- 最佳版本数量
- 我的收藏
- 最近编辑
- 记录习惯提示
- 本地数据管理入口

数据管理只允许本地功能：

- 导出本地数据
- 导入本地数据
- 清空全部数据
- 清空前二次确认

如果导入导出暂时没有实现，必须明确显示“即将支持”，不能伪装成已完成，也不能调用云端服务。

## 数据模型

创建以下模型：

```dart
class Recipe {
  final String id;
  final String title;
  final String category;
  final String description;
  final String? coverImagePath;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

```dart
class RecipeVersion {
  final String id;
  final String recipeId;
  final int versionNumber;
  final String title;
  final String note;
  final double? rating;
  final bool isBest;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

```dart
class Ingredient {
  final String id;
  final String versionId;
  final String name;
  final String amount;
  final String unit;
  final int sortOrder;
}
```

```dart
class CookingStep {
  final String id;
  final String versionId;
  final String content;
  final int sortOrder;
}
```

```dart
class FinishedRecord {
  final String id;
  final String versionId;
  final String? imagePath;
  final double? rating;
  final String note;
  final String nextImprovement;
  final DateTime createdAt;
}
```

要求：

- 一道菜可以拥有多个版本
- 每个版本拥有独立材料和步骤
- 材料和步骤通过 `versionId` 关联
- 删除菜谱时级联删除关联版本、材料、步骤和成品记录
- 使用稳定的本地唯一 ID
- 时间使用稳定格式保存和读取

## SQLite 数据库

至少创建：

```text
recipes
recipe_versions
ingredients
cooking_steps
finished_records
```

实现：

- 数据库初始化
- 建表
- 外键关系
- 数据库版本和迁移
- CRUD
- Repository 层
- 错误处理
- 空数据处理
- 创建菜谱和版本 1 的事务
- 复制版本的事务
- 删除菜谱的事务

建议目录：

```text
lib/
  main.dart
  app.dart
  core/
    database/
    theme/
    utils/
  models/
  repositories/
  providers/
  features/
    recipes/
      data/
      presentation/
    versions/
      data/
      presentation/
    comparison/
      presentation/
    profile/
      presentation/
  shared/
    widgets/
```

## 状态管理与导航

使用 Riverpod 管理：

- 当前底部 Tab
- 菜谱列表
- 搜索关键词
- 分类筛选
- 当前菜谱
- 当前版本
- 版本列表
- 对比状态
- 收藏状态
- 加载、错误和保存状态

可以使用 Flutter Navigator 或 `go_router`，保持路由简单：

```text
/
/new-recipe
/recipe/:recipeId
/recipe/:recipeId/version/:versionId/edit
/recipe/:recipeId/compare
/profile
```

主要交互必须真实可用：

- 点击菜谱进入详情
- 搜索实时过滤
- 分类筛选实时更新
- 收藏状态持久化
- 切换版本改变详情内容
- 新建、复制、编辑和删除版本
- 版本对比显示真实差异
- 添加照片并保存本地路径
- 保存成功显示反馈
- 保存失败显示错误
- 空数据显示空状态
- 删除前显示确认

## 可用性要求

- 支持 375px 宽度
- 不允许横向溢出
- 所有页面可滚动
- 主要点击区域至少 44×44
- 输入框有可见 Label
- 长文本自然换行
- 评分、数量、单位和错误信息不能被截断
- 主要控件支持键盘和无障碍操作
- 有清晰的 Focus 状态
- 不依赖颜色单独表达状态
- 底部导航不遮挡内容
- 支持系统字体放大
- 动画克制，并支持减少动画

## 实现顺序

1. 检查项目目录和 `index.html`
2. 输出项目结构与设计分析
3. 创建 Theme 和基础组件
4. 创建模型
5. 创建 SQLite 数据库和迁移
6. 创建 Repository
7. 创建 Riverpod Providers
8. 实现菜谱首页
9. 实现搜索和分类筛选
10. 实现新建菜谱
11. 实现菜谱详情和版本切换
12. 实现版本编辑
13. 实现版本复制和删除
14. 实现版本对比
15. 实现本地照片选择和保存
16. 实现“我的”页面
17. 实现本地导入导出入口
18. 增加空状态、错误状态和保存反馈
19. 增加测试
20. 运行格式化和测试

## 完成后说明

完成后请说明：

1. 修改和新增了哪些文件
2. 使用了哪些依赖以及各自用途
3. 如何运行项目
4. 如何测试新建菜谱、搜索、筛选、收藏、版本切换和版本对比
5. 哪些功能暂时未完成
6. 明确说明项目没有使用任何云端服务

请先读取现有项目和 `index.html`，再输出分析与计划，然后开始编码。不要直接覆盖已有代码。