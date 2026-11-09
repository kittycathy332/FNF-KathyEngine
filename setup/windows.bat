@echo off
color 0a
cd ..
echo Installing dependencies...
echo This might take a few moments depending on your internet speed.
haxelib git hxcpp https://github.com/kittycathy332/hxcpp-SDE.git main-261101 --quiet
REM hxcpp git 源码版需要重新编译命令行工具（hxcpp.n），否则构建时会卡在交互提示
for /f "delims=" %%p in ('haxelib config') do set "HAXELIB_PATH=%%p"
pushd "%HAXELIB_PATH%hxcpp\git\tools\hxcpp"
haxe compile.hxml
popd
haxelib install lime 8.3.2 --quiet --skip-dependencies
haxelib install libhxcpp 6.0.0-rc.1 --skip-dependencies
haxelib install openfl 9.5.2 --quiet --skip-dependencies
haxelib install flixel 5.9.0 --quiet --skip-dependencies
haxelib install flixel-addons 4.0.2 --quiet --skip-dependencies
haxelib install flixel-tools 1.5.1 --quiet --skip-dependencies
haxelib install flixel-ui 2.6.5 --quiet --skip-dependencies
haxelib git flixel-text-input https://github.com/kittycathy332/flixel-text-input.git --quiet --skip-dependencies
haxelib install hscript-iris 1.1.3 --quiet
haxelib install hscript 2.7.0 --quiet
haxelib install polymod 1.8.0 --quiet
haxelib install tjson 1.4.0 --quiet
haxelib install away3d 5.0.9 --quiet
haxelib install haxe-concurrent 5.1.5 --quiet
haxelib install flixel-waveform 2.1.2 --quiet --skip-dependencies
haxelib git flxanimate https://github.com/Dot-Stuff/flxanimate 768740a56b26aa0c072720e0d1236b94afe68e3e --quiet
haxelib git linc_luajit https://github.com/kittycathy233/linc_luajit --quiet
haxelib install hxdiscord_rpc 1.3.0--quiet --skip-dependencies
haxelib install hxvlc 2.3.0 --quiet --skip-dependencies
haxelib install flxgif 1.0.3 --quiet --skip-dependencies
haxelib install yagp 1.1.4 --quiet --skip-dependencies
haxelib install flxsvg 1.1.0 --quiet --skip-dependencies
haxelib install svg 1.2.0 --quiet --skip-dependencies
haxelib install sl-windows-api 1.4.0 --quiet --skip-dependencies
haxelib git extension-androidtools https://github.com/kittycathy332/extension-androidtools.git --quiet --skip-dependencies
haxelib git haxeui-core https://github.com/kittycathy332/haxeui-core.git --quiet --skip-dependencies
haxelib git haxeui-flixel https://github.com/kittycathy332/haxeui-flixel.git master --quiet --skip-dependencies
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis 22b1ce089dd924f15cdc4632397ef3504d464e90 --quiet --skip-dependencies
haxelib git grig.audio https://gitlab.com/haxe-grig/grig.audio.git cbf91e2180fd2e374924fe74844086aab7891666 --quiet
haxelib git spine-haxe https://github.com/kittycathy332/spine-haxe-Archive.git  --quiet --skip-dependencies
haxelib run libhxcpp setup
echo Finished!
pause
