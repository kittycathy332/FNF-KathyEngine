# psychmobile 收尾计划：Arrows 模式 / 数据目录 / 原生能力完善 / 设置冲突清理

## Context

此前已完成 psychmobile 的一轮移植（存储四类型、Hitbox 样式/配色/图片导入、MobileUtil+MobileBridge、Lua/HScript API、动画暂停键）。本轮收尾要解决 5 件事：

1. **Arrows 操作模式**：新增 `hitboxMode`（Four Lanes / Arrows）。Arrows = 玩家箭头放大 1.25x 排到屏幕底部、强制 Downscroll、隐藏对手轨道与触控列、触摸判定改为箭头外扩 26px 矩形、音符同步放大；**必须兼容 ExtraKeys（N 键）**。
2. **打开数据目录**：新增设置页按钮 + 极简 Gradle 模块（`DocumentsProvider`），让系统文件管理器能浏览并按存储根目录定位；按钮固定打开**根目录**。
3. **原生能力完善**：`toast/电量/充电/常亮` 从"仅 API"提升到 UI：设置页常亮开关、暂停菜单电量行、FPS 角标电量；补齐 Lua/HScript。
4. **暂停菜单返回键**：与设置页一致，**注释**（`/* */`）而不是删除。
5. **设置冲突清理**：利用现有 `Option.disabled + requirement` 淡化机制，按样式条件禁用旧选项，不重建列表。

已确认的决策：ExtraKeys 整屏等宽均分；常亮合并为单一开关且**默认开、全局生效**；电量格式"百分比 + 充电状态"，仅移动端，每 5 秒刷新；数据目录固定根目录；额外功能键（A/B/C/D）跟随 `extraButtons` 设置；`hitboxMode` 改动**下次进入歌曲生效**；电量行放暂停菜单信息列末行。

---

## 1. 构建层：Android Data 模块（先做，Haxe 才能引用）

- `Project.xml`：在 `<java path="project/android/jni" if="android"/>` 之后新增
  `<dependency name="kathyengine-data" path="project/android/data" if="android"/>`
- 新建 `project/android/data/build.gradle`：`com.android.library`，`namespace 'com.kathyengine.data'`，SDK 版本读 `project.ANDROID_BUILD_SDK_VERSION` / `ANDROID_BUILD_TOOLS_VERSION`，不依赖 extension-api。
- 新建 `project/android/data/src/main/AndroidManifest.xml`：
  ```xml
  <provider
      android:name="com.kathyengine.data.DataProvider"
      android:authorities="${applicationId}.documents"
      android:exported="true"
      android:grantUriPermissions="true"
      android:permission="android.permission.MANAGE_DOCUMENTS">
      <intent-filter>
          <action android:name="android.provider.action.DOCUMENTS_PROVIDER" />
      </intent-filter>
  </provider>
  ```
- `DataProvider.java`（`DocumentsProvider` 子类）：
  - `baseDir` 读取 `new File(context.getExternalFilesDir(null), ".kathy_storage_root")`，内容 trim 且目录存在才用，否则回退 `getExternalFilesDir(null)`。
  - docId 用绝对路径；所有入口都做 `getCanonicalPath()` 校验必须在 baseDir 之下，防目录穿越。
  - 实现 `queryRoots / queryDocument / queryChildDocuments / openDocument / createDocument / deleteDocument / renameDocument / isChildDocument / getDocumentType`；目录优先、按名排序、MIME 推断。
- `DataFolder.java`：`static boolean open()`，`activity = org.libsdl.app.SDLActivity.getContext()`（不依赖 Extension），用 `DocumentsContract.buildRootUri(pkg+".documents", "root")` + `ACTION_VIEW` + `vnd.android.document/root`，依次尝试 `com.google.android.documentsui` / `com.android.documentsui` / 不指定包；失败 Toast 并返回 false。
- `StorageUtil.hx`：新增 `ROOT_FILE_NAME = '.kathy_storage_root'`，在 `getStorageRootPathForType()` 解析出**最终可写根**后、以及 `ensureStorageRoot()` / `setStorageType()` 成功时，把绝对路径写入 `getStorageDirectory() + ROOT_FILE_NAME`（Java 与 Haxe 同源）。
- 新建 `source/mobile/backend/DataFolder.hx`：`#if android` 用 `lime.system.JNI.createStaticMethod('com/kathyengine/data/DataFolder','open','()Z')`；其他平台走 `CoolUtil.openFolder(Sys.getCwd())` 或返回 false。
- `MobileUtil.openDataFolder():Bool` 委托它。

## 2. ClientPrefs（`source/backend/ClientPrefs.hx`）

- 删除 `screensaver:Bool`（第 27 行），新增：
  - `keepScreenOn:Bool = true`
  - `hitboxMode:String = 'Four Lanes'`
- `loadPrefs()` 通用反射拷贝之后迁移旧存档：
  - 若 `FlxG.save.data` 无 `keepScreenOn` 且有 `screensaver`，`data.keepScreenOn = !(screensaver == true)`（旧默认 false = 常亮，语义一致）。
  - `hitboxMode` 非法 → `'Four Lanes'`。
- 不新增写盘路径。

## 3. 原生能力完善

- `source/mobile/backend/MobileUtil.hx`：
  - `setKeepScreenOn(on)`：`lime.system.System.allowScreenTimeout = !on`（每次调用都同步），JNI window flag 仅在值变化时调用。
  - 电量缓存：`_batteryLevel/_charging/_batteryStamp`，TTL 5 秒（`haxe.Timer.stamp()`），减少 JNI 次数。
  - `getBatteryText():String`：移动端且 level>=0 时返回 `LanguageBasic.getPhrase('battery_info','电量 {0}% · {1}', [level, charging ? '充电中' : '未充电'])`，否则空串。
  - `toast(text, longDuration:Bool=false)` 改 JNI 签名 `(Ljava/lang/String;Z)V`。
  - 新增 `openDataFolder():Bool`。
- `project/android/jni/com/kathyengine/mobile/MobileBridge.java`：`toast(String, boolean)`；`Toast.LENGTH_LONG/SHORT`。
- `source/Main.hx`：启动改为 `MobileUtil.setKeepScreenOn(ClientPrefs.data.keepScreenOn)`，移除旧 `allowScreenTimeout` 逻辑。

## 4. Arrows 模式（核心）

### 4.1 新触控层 `source/mobile/objects/ArrowsPad.hx`

- `extends MobileInputManager implements IMobileControls`（必需字段：`buttonLeft/Down/Up/Right/Extra..`、`instance=this`、`onButtonDown/onButtonUp` 信号）。
- 音符轨道按钮：透明 `TouchButton`（1x1 `makeGraphic` 后 `setGraphicSize(w,h)`），`statusAlphas=[1,1,1]`、无 label，`IDs` 复用 Hitbox 映射。
- 把 `Hitbox.noteIDForIndex()` 改为 `public static` 供复用。
- API：`relayout(rects:Array<FlxRect>)`、`ensureLaneCount(n:Int)`、`rebuildExtras(extraMode)`；`onDown/onUp` 回调照 Hitbox 555-556 行写法接信号。
- 额外功能键：按 `ClientPrefs.data.extraButtons`（`MobileData.extraActions`）生成 1-4 个按钮，位置沿用 `hitboxPos` 的顶部/底部 1/4 区域，配色沿用 Hitbox 的 `extraColors`。
- `MobileData.setButtonsColors()` 增加 `ArrowsPad` 早退（它没有 `label`，避免空引用）。

### 4.2 接入

- `source/backend/MusicBeatState.hx` 的 `case 3 (HITBOX)`：
  `mobileControls = (ClientPrefs.data.hitboxMode == 'Arrows') ? new ArrowsPad(extraMode) : new Hitbox(extraMode);`
- `PlayState.hx` 新增：
  - `arrowsModeActive()`：`controls != null && controls.mobileC && MobileData.mode == 3 && ClientPrefs.data.hitboxMode == 'Arrows'`（仅 PlayState 调用，编辑器天然不受影响）。
  - `calcArrowsScale(lanes)`：`Math.min(1.25, (FlxG.width / lanes) / Note.swagWidth)`。
  - `_preArrowsDownScroll:Null<Bool>` + `applyArrowsDownScrollOverride()` / `restoreArrowsDownScrollOverride()`；**不改写存档**。
- 强制 Downscroll：
  - `create()`：在 `originalGameplaySettings` 快照之后、HUD/`generateSong()` 之前 apply。
  - `destroy()`：在 `originalGameplaySettings` 恢复块之前 restore。
  - 风险缓解：若游玩中触发 `ClientPrefs.saveSettings()` 可能把 true 落盘——在 `saveSettings()` 内临时用 `PlayState.instance` 的快照值写入再还原（或仅在 Arrows 强制期间跳过 downScroll 的写盘）。
- 布局：
  - `generateStaticArrows()` 开头：`if (arrowsModeActive()) { generateArrowStrums(player); return; }`。
  - 玩家：按 `lanes` 均分整屏，`x = laneW*i + (laneW - arrow.width)/2`，`y = FlxG.height - 箭头高 - 24`（底边对齐原 4K 位置），`scale.set(s,s); updateHitbox(); centerOffsets(); centerOrigin();`。
  - 对手：同一循环但 `alpha = 0`（不改 `opponentStrums` 偏好）。
  - `applyMania()` / 多键 strumScale 计算：Arrows 时统一用 `calcArrowsScale(totalColumns)`，跳过普通多键收缩。
  - 音符放大：在音符创建/准备处套用 psychmobile 的 `prepareArrowsNote`（`scale.x *= s; if (!isSustainNote) scale.y *= s; updateHitbox(); offsetX *= s;`），对手音符直接隐藏。
  - 触控刷新：`startCountdown()` 生成 strums 之后、`changeKeyCounts()` 重建之后调用 `refreshArrowsPad()`（用 `playerSideStrums().members` 的屏幕矩形外扩 26px 交给 `ArrowsPad.relayout`）。
- 生效时机：切换 `hitboxMode` 只影响下一次进入歌曲；不重建当前 strums（设置页描述里注明）。

## 5. 设置页（`source/mobile/options/MobileOptionsSubState.hx`）

- 用 `keep_screen_on`（BOOL）替换第 77-80 行 `allow_phone_screensaver`，绑定 `keepScreenOn`，`onChange = () -> MobileUtil.setKeepScreenOn(curOption.getValue())`。
- mode==3 分支顶部新增 `hitbox_mode`（STRING，`['Four Lanes','Arrows']` + `valueLocalizations`），`onChange = rebuildHitbox`，描述注明"下次进入歌曲生效"。
- mode==3 分支新增 `open_data_folder`（BUTTON），调用 `MobileUtil.openDataFolder()`，失败弹 `open_data_folder_failed`。
- 冲突项淡化（不重建列表）：
  - 把 `hitboxType`、`hitboxImageFit`、`hitboxImageTint`、`hitboxImageImport`、`hitboxImageRemove` 的 `Option` 存为字段。
  - 新增 `override function update(elapsed)` → `refreshHitboxOptionStates()`：
    - `hitboxTypeOption.disabled = ClientPrefs.data.hitboxStyle != 'Classic'`，`requirement = hitbox_requirement_classic`
    - 四个 Image 项 `disabled = ClientPrefs.data.hitboxStyle != 'Image'`，`requirement = hitbox_requirement_image`
  - 复用 `OptionsConfig.SUBMENU_DISABLED_ALPHA_MULT` 的现成淡化与交互拦截。

## 6. 暂停菜单 / FPS / Lua / HScript

- `source/substates/PauseSubState.hx`
  - 信息列末行（`blueballedTxt.y + 32`）新增 `batteryText:FlxText`（32 号 vcr 字体、左对齐、`FlxG.onMobile` 才显示）。
  - `update()` 每 5 秒刷新 `MobileUtil.getBatteryText()`。
  - 第 267-272 行动画返回键整段 `/* ... */` 注释。
- `source/debug/FPSCounter.hx`：`FlxG.onMobile` 时把 `MobileUtil.getBatteryText()` 追加进现有 `textLines`（缓存已天然节流）。
- `source/mobile/psychlua/Functions.hx`：`mobileToast(text, ?longDuration)` 传 longDuration；新增 `openDataFolder`；`keepScreenOn` 保留。
- `source/psychlua/HScript.hx`：同步 `mobileToast` / `openDataFolder` 别名。

## 7. 本地化（en_us / zh_cn / zh_tw 三份 options json）

新增：`keep_screen_on(_desc)`、`hitbox_mode(_desc)`、`hitbox_mode_val_four_lanes`、`hitbox_mode_val_arrows`、`hitbox_requirement_classic`、`hitbox_requirement_image`、`open_data_folder(_desc/_failed)`、`battery_info`、`battery_charging`、`battery_not_charging`。

## 关键文件

- `Project.xml`、`project/android/data/**`（新模块）
- `source/mobile/backend/StorageUtil.hx`、`MobileUtil.hx`、`DataFolder.hx`（新）
- `source/backend/ClientPrefs.hx`、`MusicBeatState.hx`、`Paths.hx`
- `source/mobile/objects/ArrowsPad.hx`（新）、`Hitbox.hx`、`MobileData.hx`
- `source/states/PlayState.hx`
- `source/mobile/options/MobileOptionsSubState.hx`、`source/substates/PauseSubState.hx`、`source/debug/FPSCounter.hx`
- `source/mobile/psychlua/Functions.hx`、`source/psychlua/HScript.hx`、`source/Main.hx`
- `assets/languages/options/{en_us,zh_cn,zh_tw}.json`

## 验证

1. `lime build windows -D officialBuild`（桌面类型检查，ArrowsPad 的非 Android 分支）
2. `lime clean android` → `lime build android -D officialBuild`（必须 clean，依赖模块与 settings.gradle 才会重新生成）
3. 检查 `export/release/android/bin/app/build/intermediates/merged_manifests/**` 中 provider authority 为 `com.kittycathy.kathyengine.documents`
4. 实机/模拟器：4K、6K、9K、`changeKeyCount` 中途变键数；Arrows 开关；暂停/结算/重开；旧存档 `screensaver=true/false` 迁移；设置页淡化与按钮跳转

## 风险

- `MANAGE_DOCUMENTS` 是 signature 级权限：系统 DocumentsUI 可访问，第三方文件管理器通常看不到该 provider（预期行为）。
- Android 11+ 未授予 `MANAGE_EXTERNAL_STORAGE` 时 provider 根会回退到应用私有目录（与 StorageUtil 的回退一致）。
- 强制 Downscroll 是运行时覆盖，任何在游玩中调用 `saveSettings()` 的路径都可能落盘 true，需要在写盘处做快照保护。
- ArrowsPad 与 Hitbox 的 `IDs` 映射必须完全一致，否则按键会错位；改动 `noteIDForIndex` 可见性后要回归 Four Lanes。
- 设置页预览仍是 Hitbox 轨道；Arrows 模式下预览不代表实际游戏布局（可在描述中注明）。
