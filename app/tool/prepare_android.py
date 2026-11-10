#!/usr/bin/env python3
"""Genera la cartella android/ dal template di Flutter e applica le personalizzazioni.

Uso (da app/):  python3 tool/prepare_android.py
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID = os.path.join(APP, "android")
OVERLAY = os.path.join(APP, "android_overlay")


def run(cmd, cwd=None):
    print("+", " ".join(cmd), flush=True)
    subprocess.check_call(cmd, cwd=cwd)


def main():
    if os.path.isdir(ANDROID):
        shutil.rmtree(ANDROID)
    tmp = tempfile.mkdtemp()
    run(["flutter", "create", "--platforms=android", "--org", "it.matteo",
         "--project-name", "bet_tracker", "bet_tracker"], cwd=tmp)
    shutil.copytree(os.path.join(tmp, "bet_tracker", "android"), ANDROID)

    # --- Kotlin ---
    main_act = glob.glob(os.path.join(ANDROID, "app/src/main/**/MainActivity.kt"), recursive=True)
    if not main_act:
        sys.exit("MainActivity.kt non trovato nel template")
    kdir = os.path.dirname(main_act[0])
    for f in glob.glob(os.path.join(OVERLAY, "kotlin", "*.kt")):
        shutil.copy(f, kdir)
    print("Kotlin copiato in", kdir)

    # --- Manifest ---
    mpath = os.path.join(ANDROID, "app/src/main/AndroidManifest.xml")
    m = open(mpath).read()
    m = re.sub(r'android:label="[^"]*"', 'android:label="Bet Tracker"', m, count=1)
    if "android.permission.INTERNET" not in m:
        m = m.replace("<application", '<uses-permission android:name="android.permission.INTERNET" />\n    <application', 1)
    service = """
        <activity
            android:name=".ShareActivity"
            android:exported="true"
            android:excludeFromRecents="true"
            android:taskAffinity=""
            android:label="Bet Tracker"
            android:theme="@android:style/Theme.Translucent.NoTitleBar">
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <action android:name="android.intent.action.SEND_MULTIPLE" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="image/*" />
            </intent-filter>
        </activity>
        <service
            android:name=".BetNotificationListener"
            android:label="Bet Tracker"
            android:exported="true"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>
    </application>"""
    m = m.replace("</application>", service, 1)
    open(mpath, "w").write(m)
    print(m)

    # --- ProGuard (ML Kit include classi per altre lingue che non usiamo) ---
    shutil.copy(os.path.join(OVERLAY, "proguard-rules.pro"), os.path.join(ANDROID, "app/proguard-rules.pro"))

    # --- Firma stabile, così gli aggiornamenti si installano sopra senza perdere i dati ---
    ks = os.path.join(APP, "keystore", "bet-tracker.jks")
    kts = os.path.join(ANDROID, "app/build.gradle.kts")
    groovy = os.path.join(ANDROID, "app/build.gradle")
    if os.path.exists(kts):
        g = open(kts).read()
        block = f'''    signingConfigs {{
        create("release") {{
            storeFile = file("{ks}")
            storePassword = "bettracker"
            keyAlias = "bettracker"
            keyPassword = "bettracker"
        }}
    }}

    buildTypes {{'''
        g = g.replace("    buildTypes {", block, 1)
        g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = signingConfigs.getByName("release")\n'
                      '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")')
        open(kts, "w").write(g)
        print(g)
    elif os.path.exists(groovy):
        g = open(groovy).read()
        block = f'''    signingConfigs {{
        release {{
            storeFile file("{ks}")
            storePassword "bettracker"
            keyAlias "bettracker"
            keyPassword "bettracker"
        }}
    }}

    buildTypes {{'''
        g = g.replace("    buildTypes {", block, 1)
        g = g.replace("signingConfig signingConfigs.debug",
                      "signingConfig signingConfigs.release\n"
                      "            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'")
        open(groovy, "w").write(g)
        print(g)
    else:
        sys.exit("build.gradle non trovato")

    # --- Icone ---
    for d in glob.glob(os.path.join(OVERLAY, "icons", "mipmap-*")):
        dest = os.path.join(ANDROID, "app/src/main/res", os.path.basename(d))
        os.makedirs(dest, exist_ok=True)
        for f in glob.glob(os.path.join(d, "*.png")):
            shutil.copy(f, dest)
    print("Preparazione completata")


if __name__ == "__main__":
    main()
