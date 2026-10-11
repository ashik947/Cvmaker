#!/bin/bash
set -e
D=android-app
mkdir -p $D/app/src/main/java/com/aminmanjil/cvmaker $D/app/src/main/assets

cat > $D/settings.gradle <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "CVMaker"
include ':app'
EOF

cat > $D/build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
EOF

cat > $D/gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g
android.nonTransitiveRClass=true
EOF

cat > $D/app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
}

def runNo = Integer.parseInt(System.getenv("GITHUB_RUN_NUMBER") ?: "1")

android {
    namespace 'com.aminmanjil.cvmaker'
    compileSdk 34

    defaultConfig {
        applicationId 'com.aminmanjil.cvmaker'
        minSdk 29
        targetSdk 34
        versionCode runNo
        versionName "1.0"
    }

    signingConfigs {
        release {
            storeFile file('cv.keystore')
            storePassword 'cvmaker123'
            keyAlias 'cvkey'
            keyPassword 'cvmaker123'
        }
    }

    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
EOF

cat > $D/app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:allowBackup="true"
        android:label="CV Maker"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden|screenLayout|uiMode|smallestScreenSize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > $D/app/src/main/java/com/aminmanjil/cvmaker/MainActivity.java <<'EOF'
package com.aminmanjil.cvmaker;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.OutputStream;

public class MainActivity extends Activity {

    private static final int REQ_FILE = 1001;
    private WebView web;
    private ValueCallback<Uri[]> filePathCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        web = new WebView(this);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setMediaPlaybackRequiresUserGesture(false);

        web.addJavascriptInterface(new Bridge(), "Android");
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView w, ValueCallback<Uri[]> cb, FileChooserParams params) {
                if (filePathCallback != null) {
                    filePathCallback.onReceiveValue(null);
                }
                filePathCallback = cb;
                String type = "*/*";
                try {
                    String[] t = params.getAcceptTypes();
                    if (t != null && t.length > 0 && t[0] != null && t[0].length() > 0) {
                        type = t[0];
                    }
                } catch (Exception e) {
                    type = "*/*";
                }
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType(type);
                try {
                    startActivityForResult(Intent.createChooser(i, "Select file"), REQ_FILE);
                } catch (Exception e) {
                    filePathCallback = null;
                    return false;
                }
                return true;
            }
        });

        if (savedInstanceState != null) {
            web.restoreState(savedInstanceState);
        } else {
            web.loadUrl("file:///android_asset/index.html");
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (web != null) {
            web.saveState(outState);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_FILE) {
            if (filePathCallback != null) {
                Uri[] result = null;
                if (resultCode == RESULT_OK && data != null) {
                    if (data.getData() != null) {
                        result = new Uri[]{data.getData()};
                    } else if (data.getClipData() != null) {
                        int n = data.getClipData().getItemCount();
                        result = new Uri[n];
                        for (int k = 0; k < n; k++) {
                            result[k] = data.getClipData().getItemAt(k).getUri();
                        }
                    }
                }
                filePathCallback.onReceiveValue(result);
                filePathCallback = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    private void toast(final String msg) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                Toast.makeText(MainActivity.this, msg, Toast.LENGTH_LONG).show();
            }
        });
    }

    public class Bridge {
        @JavascriptInterface
        public void saveFile(String base64, String name, String mime) {
            try {
                byte[] data = Base64.decode(base64, Base64.DEFAULT);
                String safe = name.replaceAll("[\\\\/:*?\"<>|]", "_");
                if (mime == null || mime.length() == 0) {
                    mime = "application/octet-stream";
                }
                boolean img = mime.startsWith("image/");
                ContentValues v = new ContentValues();
                v.put(MediaStore.MediaColumns.DISPLAY_NAME, safe);
                v.put(MediaStore.MediaColumns.MIME_TYPE, mime);
                Uri collection;
                if (img) {
                    v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/CVMaker");
                    collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
                } else {
                    v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                    collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI;
                }
                ContentResolver cr = getContentResolver();
                Uri uri = cr.insert(collection, v);
                if (uri == null) {
                    throw new Exception("insert failed");
                }
                OutputStream os = cr.openOutputStream(uri);
                os.write(data);
                os.close();
                toast(img ? "ছবি গ্যালারিতে সেভ হয়েছে (Pictures/CVMaker)" : "ফাইল Downloads ফোল্ডারে সেভ হয়েছে");
            } catch (Exception e) {
                toast("সেভ হয়নি: " + e.getMessage());
            }
        }
    }
}
EOF

base64 -d > $D/app/cv.keystore <<'EOF'
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
l8S8fQICJxA=
EOF

cp index.html $D/app/src/main/assets/index.html
echo "Project ready"
