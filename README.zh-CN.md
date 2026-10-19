# 奶家族 · Milk Family

**Codex / Claude Code 用量统计、桌面伙伴与养成收集。**

[English](README.md) · [简体中文](README.zh-CN.md)

奶家族是一款原生 macOS 软件，从本机日志记录真实 Token 用量，通过新增用量培养奶娃、解锁动作、孵化奶家人并收集卡片。

**1.0.0 · macOS 14+ · 中文 / English · 32 位奶家人 · 179 个连续动画动作 · 175 张卡片**

<p align="center"><img src="docs/images/adult-milk-frog.png" width="220" alt="成年奶娃 · Adult Milk Frog"></p>
<p align="center"><strong>成年奶娃 · Adult Milk Frog</strong></p>

## 下载安装

在 [Releases](https://github.com/jaysoncbh/MilkFamily/releases) 下载 **v1.0.0**。

1. 使用 **Apple Silicon（M 系列芯片）、macOS 14 或更高版本**的 Mac；当前未提供 Intel 版本。
2. 下载正式版 **`MilkFamily-1.0.0-macOS-arm64.zip`**。`Source code` 和 `MilkFamily-Source-…zip` 为源码包。
3. 双击 ZIP 解压，将 **`奶家族.app` 拖入“应用程序 / Applications”**，然后打开。
4. 默认英文，可在 **Settings → Language** 切换中文。选择普通初始伙伴，并在小铺领取待机卡。
5. 软件自动读取本机 Codex / Claude Code 日志；未找到时，在设置中选择日志文件夹。

App 已内置人物、卡片与动画，无需另外下载素材或编译。**本版为临时签名，未经过 Apple 公证**；首次打开可能需要系统确认，详见[安装说明](docs/INSTALL.md)。

## 成年奶娃

成年奶娃（A201，图鉴名“成年奶蛙”，英文 **Adult Milk Frog**）是主要人物，属于稀有伙伴，通过孵化获得。六种动作随培养解锁；**捧腹大笑**是奶娃绷不住时的代表动作。

<table>
<tr>
<td align="center" width="33%"><img src="docs/images/adult-idle.gif" width="140" alt="成年奶娃 · 待机"><br><strong>待机</strong></td>
<td align="center" width="33%"><img src="docs/images/adult-tai-chi.gif" width="140" alt="成年奶娃 · 打太极"><br><strong>打太极</strong></td>
<td align="center" width="33%"><img src="docs/images/adult-laugh.gif" width="140" alt="成年奶娃 · 捧腹大笑"><br><strong>捧腹大笑</strong></td>
</tr>
<tr>
<td align="center" width="33%"><img src="docs/images/adult-rest.gif" width="140" alt="成年奶娃 · 托腮休息"><br><strong>托腮休息</strong></td>
<td align="center" width="33%"><img src="docs/images/adult-wave.gif" width="140" alt="成年奶娃 · 挥手招呼"><br><strong>挥手招呼</strong></td>
<td align="center" width="33%"><img src="docs/images/adult-hop.gif" width="140" alt="成年奶娃 · 开心蹦跳"><br><strong>开心蹦跳</strong></td>
</tr>
</table>

## 奶家人动作示例

<table>
<tr>
<td align="center" width="33%"><img src="docs/images/milk-mouse-laugh.gif" width="140" alt="奶鼠 · 普通 · 捧腹大笑"><br><strong>奶鼠 · 普通</strong><br>捧腹大笑</td>
<td align="center" width="33%"><img src="docs/images/milk-garlic-green-puff.gif" width="140" alt="奶蒜 · 史诗 · 绿屁后狂笑"><br><strong>奶蒜 · 史诗</strong><br>绿屁后狂笑</td>
<td align="center" width="33%"><img src="docs/images/pink-milk-cat-knead.gif" width="140" alt="粉色奶猫 · 传说 · 踩奶"><br><strong>粉色奶猫 · 传说</strong><br>踩奶</td>
</tr>
</table>

## 奶家人名单

共 **32 位：普通19、稀有8、史诗4、传说1**。

| 稀有度 | 数量 | 角色 |
| --- | ---: | --- |
| 普通 | 19 | 奶鼠 · 奶牛 · 奶虎 · 奶兔 · 奶蛇 · 奶马 · 奶羊 · 奶猴 · 奶鸡 · 奶狗 · 奶猪 · 奶鱼 · 奶虾 · 奶蜗牛 · 奶便便 · 奶W · 奶大象 · 奶小象 · 奶鸟 |
| 稀有 | 8 | **成年奶娃（图鉴名：成年奶蛙）** · 奶团 · 奶朗普 · 中国奶龙 · 奶虫 · 奶绵宝宝 · 奶大星 · 奶老板 |
| 史诗 | 4 | 奶龙 · 奶佛 · 奶蒜 · 奶粉 |
| 传说 | 1 | 粉色奶猫 |

[完整中英文名称、编号与动作数量](docs/COMPANIONS.md)。

## Token 统计

首页显示 Codex 和 Claude Code 的**今日、本周、本月、累计 Token**，提供本月每日柱状图及精确数值。按本机时区统计，自然周从周一开始。

每 15 秒同步并去重本机日志。历史用量用于统计，完成初始设置后的新增用量用于养成；道具奖励不改动真实 Token 记录。软件不估算 API 费用。

<p align="center"><img src="docs/images/home-en.png" width="390" alt="首页：伙伴、孵化进度与日周月累计 Token 统计"></p>

## 桌面伙伴

支持拖动、部分进入屏幕边缘、调整大小、隐藏及固定面板。单击打开面板，右键切换已解锁动作。

**179 个动作全部具有连续动画，共 912 帧。** 全部奶家人均有**捧腹大笑**，可在详情中预览或在桌面播放。

## 养成规则

1. 选择普通奶家人，在小铺领取待机卡后开始培养。
2. 新增真实 Token 推动当前奶娃成长，逐步解锁动作。
3. 动作全部解锁后，可以开始孵蛋，获得其他奶家人。
4. 背包管理伙伴、卡片和道具，支持搜索与稀有度筛选。

**100% 难度下的基础规则：**

| 项目 | 数值 |
| --- | --- |
| 后续动作解锁 | 每20M Token解锁下一个动作 |
| 孵化 | 每颗蛋50M Token |
| 奶币 | 每1M Token获得1奶币 |
| 免费抽卡 | 每100M Token获得1次 |

难度范围为20%–500%，同步调整成长、孵化、奖励间隔及商品价格，保留已解锁动作。奶蛋分普通、稀有、史诗和传说；升阶后不再孵出更低稀有度。重复孵化会温和降低同稀有度内该角色的相对权重，最低为初始的一半，各稀有度总概率不变。

<p align="center"><img src="docs/images/collection-zh.png" width="390" alt="背包：奶家人名单与稀有度筛选"></p>

## 商店与道具

| 道具 | 基础价格 | 效果 |
| --- | ---: | --- |
| 奶糖 / Milk Candy | 150奶币 | 增加150 Token孵化奖励进度，不增加真实Token、奶币或免费次数。 |
| 奶星石 / Milk Star | 200奶币 | 30%概率使当前奶蛋提升一级。 |
| 奶卡券 / Card Ticket | 100奶币 | 从已解锁动作中抽取一张卡片。 |

购买后进入背包，使用时生效。免费抽卡与奶卡券均使用已解锁动作的卡池。

<p align="center"><img src="docs/images/shop-en.png" width="390" alt="商店：免费抽卡、奶糖、奶星石和奶卡券"></p>

## 卡片系统

共有 **175 张卡片：127普通、31闪光、14黑金、3幻影**。卡片样式与角色稀有度独立；对应动作解锁后，卡片进入可抽取范围。

其中 **20 张高级卡支持交互动效**，包括指针倾斜、视差、流动闪光、金属掠光及分层星空；其他卡片保持静态。

<p align="center"><img src="docs/images/black-gold-card.png" width="390" alt="奶佛黑金卡详情"></p>

卡面保留中文印刷字样，界面支持中英切换。商店、图鉴与卡片截图来自测试版，其“样卡”“测试”入口不在正式版显示；截图进度为示例。

## 语言、外观与隐私

- 新存档默认英文，可切换简体中文；更新保留已有语言选择。
- 支持系统、浅色、深色外观，遵循macOS减弱动态效果与降低透明度设置。
- 用量和进度保存在本机，无需API Key，不上传日志、提示词、回复或存档。
- Claude Code接入其他API时，本机日志包含受支持的用量字段即可统计；缺失用量不估算补造。

详见[使用与隐私说明](docs/使用与隐私说明.md)。

## 源码构建

源码检查：

```sh
./scripts/check.sh
```

开发者构建可运行App时，需要独立的授权运行素材包，详见[构建说明](docs/BUILD.md)。远端CI、公证和外部下载验收状态见[发布检查表](docs/RELEASE_CHECKLIST.md)。

## 许可

本项目源码与文字文档采用 [MIT](LICENSE)，署名 `Copyright (c) 2026 Milk Family contributors`。人物、卡面、动画及截图另见[素材权利说明](ASSET_RIGHTS.md)。[许可阅读说明](docs/LICENSE_GUIDE.md)。

## 致谢

界面与本机用量设计参考 [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)。其[上游MIT声明](licenses/PokeTokenBar-MIT.txt)单独保留，详情见[NOTICE](NOTICE.md)。
