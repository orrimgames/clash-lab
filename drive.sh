set -x
set +e
sudo apt-get install -y tesseract-ocr patchelf > /dev/null 2>&1 || true
curl -sL https://github.com/supremegamers/vendor_intel_proprietary_houdini/archive/81f2a51ef539a35aead396ab7fce2adf89f46e88.zip -o /tmp/ha.zip
unzip -q -o /tmp/ha.zip -d /tmp/ha
HA=/tmp/houdini/h/prebuilts
cd "$GITHUB_WORKSPACE"
git config user.email bot@x.co
git config user.name bot
git fetch -q origin '+refs/heads/shots:refs/remotes/origin/shots' 2>/dev/null
git checkout -B shots refs/remotes/origin/shots 2>/dev/null || git checkout -B shots
mkdir -p shots
( for i in $(seq 1 90); do git add -A 2>/dev/null; git commit -qm "s$i" 2>/dev/null; git push -qf origin shots 2>>shots/push.err; sleep 8; done ) & PUSHPID=$!
shot(){ adb exec-out screencap -p > "shots/$1.png" 2>/dev/null; tesseract "shots/$1.png" "shots/$1" 2>/dev/null; }
st(){ echo "$(date +%T) $*" >> shots/status.txt; }
waitboot(){ for i in $(seq 1 60); do b=$(timeout 15 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$b" = 1 ] && { echo "booted after $((i*5))s"; return 0; }; [ $((i % 6)) = 0 ] && timeout 15 adb reconnect > /dev/null 2>&1; sleep 5; done; echo "WAITBOOT-TIMEOUT"; }
st start-v54-play35-arm64
st installing-play35-image
sdkmanager 'system-images;android-35;google_apis_playstore;x86_64' > shots/sdk.log 2>&1
printf 'no\n' | avdmanager create avd -n crarm64 -k 'system-images;android-35;google_apis_playstore;x86_64' --force > shots/avd.log 2>&1
adb emu kill > shots/kill-emu.log 2>&1
sleep 5
nohup "$ANDROID_HOME/emulator/emulator" -avd crarm64 -no-window -noaudio -no-boot-anim -no-snapshot -gpu swiftshader_indirect -memory 3072 -cores 4 -skin 720x1280 > shots/emu32.log 2>&1 &
st api32-started
timeout 300 adb wait-for-device || { st no-adb; kill $PUSHPID; git add -A; git commit -qm noadb; git push -qf origin shots; exit 1; }
waitboot
st booted
{ echo "abilist: $(adb shell getprop ro.product.cpu.abilist | tr -d '\r')";
  echo "bridge: $(adb shell getprop ro.dalvik.vm.native.bridge | tr -d '\r')";
} > shots/props.txt 2>&1
adb shell id > shots/adbroot.txt 2>&1
sleep 4
timeout 60 adb wait-for-device

adb shell getenforce > shots/selinux.txt
st stock-bridge-unmodified
sleep 5
shot 001-boot
st downloading-arm64
python3 - <<'DOWN' > shots/download.log 2>&1
import requests,re,pathlib
u='https://api.pureapk.com/m/v3/cms/app_version?hl=en-US&package_name=com.supercell.clashroyale'
r=requests.get(u,headers={'x-cv':'3172501','x-sv':'35','x-abis':'arm64-v8a','x-gp':'1'},timeout=60)
r.raise_for_status()
data=r.content
pat=rb'(X?APKJ)..(https?://(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*))'
m=re.search(pat,data)
assert m,'no ARM64 download'
url=m.group(2).decode()
pathlib.Path('shots/arm64-source.txt').write_text(url)
r=requests.get(url,stream=True,timeout=120)
r.raise_for_status()
with open('/tmp/arm64.xapk','wb') as f:
 for chunk in r.iter_content(1048576): f.write(chunk)
DOWN
[ -s /tmp/arm64.xapk ] || { st download-failed; kill $PUSHPID; git add -A; git commit -qm downloadfail; git push -qf origin shots; exit 1; }
mkdir -p /tmp/arm64game
unzip -q /tmp/arm64.xapk -d /tmp/arm64game
ls -l /tmp/arm64game > shots/arm64-files.txt
signer=$(find "$ANDROID_HOME/build-tools" -name apksigner | head -1)
"$signer" verify --print-certs /tmp/arm64game/com.supercell.clashroyale.apk > shots/arm64-signer.txt 2>&1
"$signer" verify --print-certs /tmp/crout/x/com.supercell.clashroyale.apk > shots/arm32-signer.txt 2>&1
adb install-multiple /tmp/arm64game/com.supercell.clashroyale.apk /tmp/arm64game/config.arm64_v8a.apk /tmp/arm64game/config.en.apk /tmp/arm64game/config.xxhdpi.apk /tmp/arm64game/install_time_asset_pack.apk > shots/install.log 2>&1
rc=$?
st install-rc=$rc
shot 002-installed
adb logcat -c
adb shell monkey -p com.supercell.clashroyale -c android.intent.category.LAUNCHER 1 > shots/launch.log 2>&1
st launched
adb shell dumpsys package com.supercell.clashroyale > shots/package.txt
sleep 60
adb shell dumpsys activity activities > shots/activity.txt
adb logcat -b all -d > shots/logcat-full.txt 2>&1
adb logcat -b all -d 2>/dev/null | grep -iE 'houdini|native.?bridge|ndk|arm|zygote|clashroyale' | tail -80 > shots/nb.txt
st diagnostics-done
for i in $(seq 1 16); do sleep 30; p=$(adb shell pidof com.supercell.clashroyale | tr -d ' '); st "t=$((i*30)) pid=$p"; shot "$(printf '%03d' $((i+2)))-run"; adb logcat -b crash -d 2>/dev/null | tail -40 > shots/crash-latest.txt; done
st done
kill $PUSHPID 2>/dev/null
git add -A 2>/dev/null
git commit -qm final 2>/dev/null
git push -qf origin shots 2>>shots/push.err
st pushed-final
