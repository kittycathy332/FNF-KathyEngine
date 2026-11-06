/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package mobile.options;

import mobile.backend.MobileScaleMode;
import mobile.backend.HitboxImageImporter;
import mobile.objects.Hitbox;
import flixel.input.keyboard.FlxKey;
import options.BaseOptionsMenu;
import options.Option;

class MobileOptionsSubState extends BaseOptionsMenu
{
	final exControlTypes:Array<String> = ["0", "1", "2", "3", "4"];
	final hintOptions:Array<String> = ["No Gradient", "No Gradient (Old)", "Gradient", "Hidden"];
	var option:Option;

	// 冲突项淡化：按 hitboxStyle 动态禁用/淡化
	var hitboxTypeOption:Option;
	var hitboxImageFitOption:Option;
	var hitboxImageTintOption:Option;
	var hitboxImageImportOption:Option;
	var hitboxImageRemoveOption:Option;

	public function new()
	{
		title = Language.get('mobile_options');
		rpcTitle = 'Mobile Options Menu'; // for Discord Rich Presence, fuck it

		option = new Option(Language.get('extra_controls'), Language.get("extra_controls_desc"),
			'extraButtons', STRING, exControlTypes);
		option.onChange = () ->
		{
			// 数量变化后重新生成触屏控件，让新数量的额外键生效
			removeMobileControls();
			addMobileControls();
		};
		addOption(option);

		option = new Option(Language.get('extra_key_bindings'),
			Language.get("extra_key_bindings_desc"), '_extraKeyBindings', BUTTON);
		option.onChange = () ->
		{
			persistentUpdate = false;
			openSubState(new mobile.substates.MobileExtraControl(this));
		};
		addOption(option);

		option = new Option(Language.get('mobile_controls_opacity'),
			Language.get("mobile_controls_opacity_desc"), 'controlsAlpha', PERCENT);
		option.scrollSpeed = 1;
		option.minValue = 0.001;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = () ->
		{
			touchPad.alpha = curOption.getValue();
			ClientPrefs.toggleVolumeKeys();
		};
		addOption(option);

		#if mobile
		option = new Option(Language.getWithFallback('keep_screen_on', 'Keep Screen On'),
			Language.getWithFallback('keep_screen_on_desc', 'Prevents the screen from turning off while the game is running.'), 'keepScreenOn', BOOL);
		option.onChange = () -> MobileUtil.setKeepScreenOn(curOption.getValue());
		addOption(option);

		option = new Option(Language.get('wide_screen_mode'),
			Language.get("wide_screen_mode_desc"),
			'wideScreen', BOOL);
		option.onChange = () -> FlxG.scaleMode = new MobileScaleMode();
		addOption(option);
		#end

		if (MobileData.mode == 3)
		{
			var rebuildHitbox = () ->
			{
				removeMobileControls();
				addMobileControls();
				// 设置页实时预览：让当前样式的 Hitbox 轨道直接可见
				if (mobileControls != null && mobileControls.instance != null)
					mobileControls.instance.visible = true;
			};

			// Arrows 操作方式（下次进入歌曲生效）
			option = new Option(Language.getWithFallback('hitbox_mode', 'Hitbox Mode'),
				Language.getWithFallback('hitbox_mode_desc',
					'Four Lanes: the screen is split into four touch lanes.\nArrows: tap the enlarged arrows at the bottom. Takes effect next song.'),
				'hitboxMode', STRING, ['Four Lanes', 'Arrows']);
			option.valueLocalizations = [
				'Four Lanes' => Language.getWithFallback('hitbox_mode_val_four_lanes', 'Four Lanes'),
				'Arrows' => Language.getWithFallback('hitbox_mode_val_arrows', 'Arrows')
			];
			option.onChange = rebuildHitbox;
			addOption(option);

			// ===== psychmobile 样式 / 配色 / 自定义图片 =====
			option = new Option(Language.getWithFallback('hitbox_style', 'Hitbox Style'),
				Language.getWithFallback('hitbox_style_desc', 'Choose the hitbox rendering style. Classic keeps the legacy design option below.'),
				'hitboxStyle', STRING, Hitbox.STYLES);
			option.onChange = rebuildHitbox;
			addOption(option);

			option = new Option(Language.getWithFallback('hitbox_colors', 'Hitbox Colors'),
				Language.getWithFallback('hitbox_colors_desc', 'Color palette used by the hitbox. Notes preserves the classic arrow colors.'),
				'hitboxColors', STRING, Hitbox.COLOR_MODES);
			option.onChange = rebuildHitbox;
			addOption(option);

			option = new Option(Language.getWithFallback('hitbox_image_fit', 'Image Fit'),
				Language.getWithFallback('hitbox_image_fit_desc', 'How the custom image is scaled inside each lane (Image style only).'),
				'hitboxImageFit', STRING, Hitbox.IMAGE_FITS);
			option.onChange = rebuildHitbox;
			hitboxImageFitOption = option;
			addOption(option);

			option = new Option(Language.getWithFallback('hitbox_image_tint', 'Image Tint'),
				Language.getWithFallback('hitbox_image_tint_desc', 'Tint the custom image with the lane color (Image style only).'),
				'hitboxImageTint', BOOL);
			option.onChange = rebuildHitbox;
			hitboxImageTintOption = option;
			addOption(option);

			option = new Option(Language.getWithFallback('hitbox_image_import', 'Import Hitbox Image'),
				Language.getWithFallback('hitbox_image_import_desc', 'Pick an image through the system file picker. Saved as mobile/hitbox_image.png.'), '_hitboxImageImport',
				BUTTON);
			option.onChange = () ->
			{
				persistentUpdate = false;
				HitboxImageImporter.pick(function(ok:Bool)
				{
					persistentUpdate = true;
					if (ok)
					{
						ClientPrefs.data.hitboxStyle = 'Image';
						ClientPrefs.saveSettings();
						rebuildHitbox();
						CoolUtil.showPopUp(Language.getWithFallback('hitbox_image_import_success', 'Image imported!'), 'Hitbox');
					}
					else
						CoolUtil.showPopUp(Language.getWithFallback('hitbox_image_import_fail', 'Import cancelled or failed.'), 'Hitbox');
				});
			};
			hitboxImageImportOption = option;
			addOption(option);

			option = new Option(Language.getWithFallback('hitbox_image_remove', 'Remove Hitbox Image'),
				Language.getWithFallback('hitbox_image_remove_desc', 'Delete the imported image and fall back to the Gradient style.'), '_hitboxImageRemove',
				BUTTON);
			option.onChange = () ->
			{
				HitboxImageImporter.remove();
				ClientPrefs.data.hitboxStyle = 'Gradient';
				ClientPrefs.saveSettings();
				rebuildHitbox();
			};
			hitboxImageRemoveOption = option;
			addOption(option);

			// ===== 旧版 Hitbox 设计（hitboxStyle='Classic' 时生效）=====
			option = new Option(Language.get('hitbox_design'), Language.get("hitbox_design_desc"), 'hitboxType', STRING, hintOptions);
			option.valueLocalizations = [
				hintOptions[0] => Language.get('hitbox_design_val_no_gradient'),
				hintOptions[1] => Language.get('hitbox_design_val_no_gradient_old'),
				hintOptions[2] => Language.get('hitbox_design_val_gradient'),
				hintOptions[3] => Language.get('hitbox_design_val_hidden')
			];
			hitboxTypeOption = option;
			addOption(option);

			option = new Option(Language.get('hitbox_position'), Language.get("hitbox_position_desc"),
				'hitboxPos', BOOL);
			addOption(option);

			option = new Option(Language.get('hitbox_animation'), Language.get("hitbox_animation_desc"),
				'hitboxAnimation', BOOL);
			addOption(option);

			option = new Option(Language.get('hitbox_hide_idle'), Language.get("hitbox_hide_idle_desc"),
				'hitboxHideIdle', BOOL);
			option.onChange = rebuildHitbox;
			addOption(option);

			// Extra Keys：触屏多键轨道模式（auto = 跟随谱面键数 / 4k = 固定 4 键）
			option = new Option(Language.get('touch_lane_mode'),
				Language.get("touch_lane_mode_desc"),
				'touchLaneMode',
				STRING,
				['auto', '4k']);
			addOption(option);

			// 进入页面即显示当前样式的预览
			if (mobileControls != null && mobileControls.instance != null)
				mobileControls.instance.visible = true;
		}

		// ===== 存储位置（Data / Media / Obb / External）=====
		option = new Option(Language.getWithFallback('storage_location', 'Storage Location'),
			Language.getWithFallback('storage_location_desc', 'Where mods, saves, logs, screenshots and backups are stored. Changing it does NOT migrate existing data.'),
			'storageType', STRING, StorageUtil.STORAGE_TYPES);
		option.onChange = () ->
		{
			var storageType:String = curOption.getValue();
			ClientPrefs.data.storageType = storageType;
			var ok:Bool = StorageUtil.setStorageType(storageType);
			ClientPrefs.saveSettings();
			var path:String = StorageUtil.getStorageRootPathForType(storageType);
			CoolUtil.showPopUp(ok ? Language.getWithFallback('storage_location_changed',
				'Storage location changed to:\n{0}\n\nPlease restart the game for all paths to update.', [path]) : Language.getWithFallback('storage_location_failed',
				'Can not write to:\n{0}\nCheck storage permissions.', [path]), Language.getWithFallback('storage_location', 'Storage Location'));
		};
		addOption(option);

		// 打开数据目录（Android 走 DocumentsProvider；桌面打开工作目录）
		option = new Option(Language.getWithFallback('open_data_folder', 'Open Data Folder'),
			Language.getWithFallback('open_data_folder_desc', 'Open the game data folder in a file manager.'), '_openDataFolder', BUTTON);
		option.onChange = () ->
		{
			if (!MobileUtil.openDataFolder())
				CoolUtil.showPopUp(Language.getWithFallback('open_data_folder_failed', 'Could not open the data folder.'), 'Data Folder');
		};
		addOption(option);

		option = new Option(Language.get('dynamic_controls_color'),
			Language.get("dynamic_controls_color_desc"), 'dynamicColors',
			BOOL);
		addOption(option);

		super();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		refreshHitboxOptionStates();
	}

	/**
	 * 冲突项淡化：hitboxType 只在 Classic 样式下可用；图片相关项只在 Image 样式下可用。
	 * disabled 会影响标签淡化与交互拦截（BaseOptionsMenu 内统一处理）。
	 */
	function refreshHitboxOptionStates():Void
	{
		var style:String = ClientPrefs.data.hitboxStyle;
		var classic:Bool = style == 'Classic';
		var image:Bool = style == 'Image';
		var classicRequirement:String = Language.getWithFallback('hitbox_requirement_classic', 'Classic render style');
		var imageRequirement:String = Language.getWithFallback('hitbox_requirement_image', 'Image render style');

		if (hitboxTypeOption != null)
		{
			hitboxTypeOption.disabled = !classic;
			hitboxTypeOption.requirement = classicRequirement;
		}
		for (opt in [hitboxImageFitOption, hitboxImageTintOption, hitboxImageImportOption, hitboxImageRemoveOption])
		{
			if (opt != null)
			{
				opt.disabled = !image;
				opt.requirement = imageRequirement;
			}
		}
	}
}
