# Sentinel 原型美术资产

原创几何模型，由 `tools/art/generate_sentinel_assets.py` 使用 Python 标准库生成，不依赖外部模型包。重新生成后让 Godot 导入即可。

- `sentinel_robot.glb`：分段机械人形，头、胸、肩臂、膝腿、背包与发光面罩；包含 idle、walk、shoot、hit、death 五段刚性节点动画。
- `lancer_rifle.glb`：突击步枪。
- `breach_shotgun.glb`：短管霰弹枪。
- `marksman_rifle.glb`：长枪管与瞄准镜。
- `robot_visual.tscn`：游戏使用的动画和敌我配色适配场景。

单位为米，武器朝向 +Z，握持原点统一，枪口由 Muzzle 节点标记。模型已替换生产单位和三份武器资源；旧胶囊体隐藏以保留现有节点接口。

## 查看效果

打开 `scenes/presentation/sentinel_showcase.tscn`，按 F6：

1 待机、2 行走、3 射击、4 受击、5 倒地、6 枪火与命中、7 爆炸、8 转向。再次按 1 恢复站立。此场景使用实际单位与特效脚本。

## 演出接入

### 掩体与定向反馈

`scenes/presentation/cover_feedback_showcase.tscn` 可独立运行：1 低掩体射击、2 高掩体探出、3 击杀、4 恢复目标。这个演示台手动指定姿态；正式关卡由控制器读取当前格相邻边、单位所在侧的掩体 profile，在移动或掩体变化后刷新。

低掩体降低身体并屈膝，收枪沿掩体待机；高掩体采用侧身姿态。开火前用 0.16 秒打开姿态并瞄准目标胸部，再播放射击，最后收回。高掩体探出复用 TacticalStepOut 返回的合法格，仅偏移模型与武器，不移动单位根节点或占格。枪械在探出位置重新计算朝向，并保持该朝向进行后坐力动画。

受击与倒地方向来自攻击来源（爆炸采用爆心），在角色局部空间内旋转。普通命中使用短促冲击声与暖色火花，机器人装甲命中使用金属声与冷色火花，致命命中使用较长的低频破裂声和更多碎片。当前没有独立护甲数值系统，这些类型仅决定表现，不新增护甲减伤。PCM 音效在首次使用时生成并缓存。

可见击杀留下无碰撞静态网格残骸，最多保留 32 具，超出后清除最早的残骸；跳过击杀也保留最终倒地结果。撤销复活或移除原单位后清除对应残骸，重开场景时随演出节点释放。姿态是程序化刚性关节动作，尚不包含接触点 IK、贴墙碰撞求解或布娃娃。

`CombatPresentationDirector` 在武器 impact_time 前发射曳光，在命中时产生火花和碎片，爆炸事件产生扩散烟尘。受击与倒地按同一个局部演出时钟采样；慢镜头不修改 Engine.time_scale。跳过或结束会清理粒子、恢复关节和握枪位置，供撤销或重开使用。

`CombatVfx` 采用共享基础网格和独立视觉随机数，最多 256 个粒子，不添加伤害或碰撞体。碎片落地采用高度平面近似；当前动作是机械分段动画，不是布娃娃或人体动作捕捉。更多单位同时交火时，可进一步改用 MultiMesh 或 GPU 粒子。

## 验证

使用 Godot 的 `--headless --path . --script` 分别运行：

- `tests/presentation/sentinel_assets_test.gd`：动画、复位、枪口、粒子时钟和清理。
- `tests/presentation/combat_presentation_test.gd`：击杀、跳过、镜头和战斗状态隔离。
- `tests/gameplay/attack_feedback_unit_test.gd`：后坐力、中断与场景退出。
- `tests/session/mission_scene_test.gd`：完整任务流程。
