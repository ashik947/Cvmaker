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
        android:icon="@mipmap/ic_launcher"
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

mkdir -p $D/app/src/main/res/mipmap-xxxhdpi
base64 -d > $D/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png <<'EOF'
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
1olZCACy5p3jwzLJ99NQm471oi4BAAABCQAgG65m67Fu1CEAACAgAQAAAQkAAAhIAABAQAIAyIYP
tqnHulGHTwIka7suv7rvQwAYJDsAQFZczU7HelGXAACyY6hNxjoxC7cAgCzNDTcfcjPO4KcJAgDI
mmEH7XALAAACEgAAEJAAAICABAAABCQAACAgAQAAAQkAAAhIAABAQAIAAAISAAAQkAAAgIAEAAAE
JAAAICABAAABCQAACEgAAEBAAgAAAhIAABDQ6r4PAGApV22/se9DyM4lW87r+xAYAAEAZMngX9zc
2ggBZuEWAJAdw38y1olZCAAgK4badKwXdQkAAAhIAADZcDVbj3WjDgEAAAEJAAAISAAAQEACAAAC
EgBANnywTT3WjToEAAAEJACArLianY71oi4BAGTHUJuMdWIWfhkQkKW54eZDbsYZ/DRBAABZM+yg
HW4BAEBAAgAAAhIAABCQAACAgAQAAAQkAAAgIAEAAAEJAAAISAAAQEACAAACEgAAEJAAAICABAAA
BCQAACAgAQAAAQkAAAhIAABAQAIAAAISAAAQkAAAgIAEAAAEJAAAICABAAABCQAACEgAAEBAAgAA
AhIAABCQAACAgAQAAAQkAAAgIAEAAAEJAAAISAAAQEACAAACEgAAEJAAAICABAAABCQAACAgAQAA
AQkAAAhIAABAQAIAAAISAAAQkAAAgIAEAAAEJAAAICABAAABCQAACGh13wcAx152cd+HAFnadfnV
fR8CAyYA6IWhD8sbfZ6IAZomAOic4d+uNx/7+nTuCSenszadmDZuOCK98qCD04FrD0i7n9mTHvz1
o+nOX9yXtt17R/ra/34/PfjEoy/9u89f9Jfp/DeeNe//2r13T/rNKz6ant63d6Kvfe1HPpXOOGbz
vMceePzhdM6n/yI9v3//7CcX2LGXXSwCaJQAoDMGf7veffKW9LG3X5he/6pjKv/80APXp0MPXJ9e
d9RvpAtOfUt67oIPpRt+9N30V//x+fT0vr3pmttuGQuA9WvXpd8+6cx0/c5ty37917zyyLHhn1JK
1+34puHfkLnnkBCgCd4ESCcM//YctPaA9Jk/+Gj63Ac/vujwr7Jq5cr07pO3pIPXHZRSSunmH+9I
j+x+Yuzvve/0cyb6/953+rmVj19z2y0THxOT8XyiCQKA1nmxas+aVavTP//pX6f3v6l6+E7j2eee
S1+tuNJ/6+ZT02EHHbLsv3/vaWePPfaDn92d7v7Vz2c+NsZ5XjErtwCgYH//ex9OW487qfLPdtx3
V7rq2zel7bvuSA89+URas2pVOuqQV6Yzjjkhnf+Gs9I7TnxTWrVy/jXAtbfdmj70lnfNe2z1ylXp
PaduTV/49k2LHsepG1+bjj/y1WOPu/qHfAkAWuUqpT2nbDwu/dGZb6v8s3+86cvpyv/+yrzH9j67
L937zAPp3oceSNd8/5a0ccMR6W/P/2DaP3J/fuf996Sf/PL+tPmojfP+7YWnnbNkAFxYcZtg33PP
TvTeAerzxkBm4RYArTH82/Xxt78/rVixYuzxf91+09jwr3L/Yw+lP/+3z6aHnnx83uPXVly1n3HM
5nTMYUdV/j+rVq5MF5yydezxr9+5Iz361JPLHgez8TyjLgEABTpg9Zr0WyecPPb47r170qdv/PeZ
/u/rdtxa+a79C0+rfjPg2ce/MR15yIaxx23/Q94EABTozGNel9atWTv2+M137khP7Hlqpv/7F088
mr559+1jj1dt86dUHQaPPPXr9PU7b5vpOIB2CQBaYVuyXa/ecHjl4zvuu7uR///a224de+y1Rxyd
Tt342nmPrVuzNp3/hrPG/u71O7elZ597rpFjYXmeb9QhAKBAh69/ReXjD1f8HH8dN/zwO2n33j1j
jy/cBXjnSWem9QesG/t713zf9j/kTgBAgSre+9eop/ftTf91+3fGHr/glK3zfnSwavv/rl/dn3be
f0+rxwfMTgBAgR56svpKf7GdgTqq3sR35CEb0tnHvzGllNJhBx2S3rb51Ip/N377AMiPAIAC/fyx
hysfP/01xzf2Nb597x3p/sceGnt87qr/3adsTatXrZr3Z8/v35++skMAQAkEABToe//347Sn4jf0
vf3E09MrXvxs/1nt378/XVcxzM9/w1npwDVrK39HwLfu+WF64PFHGvn6QLsEABTomWf3pVvuGv9R
vfVr16VPvvMPG/s6Vdv56w9Yl/7snN+p/M1/VR8iBORJANAKH0/avs/efF3l45dsPS999K0XLPvv
N244Il35gY+lIw4+dNG/c+9DD6Tb7rtr7PFPvOP3xx7bvXdPuuGH313269I8zzfqEABQqJ3335O+
/L1vVP7Z37zrA+naj3wqvfe0s9PRhx6e1qxandavXZeOO+Lo9P43nZv+6eJPpG988jPpPadsrfw4
4VFVbwZceO8/pZRuuP276am9z9Q7GaBzfhkQFOyyr/5L2nT4q9Kbjz1x7M/OOGZz5Tb9tK7fuS39
3e/+SVq7es2Sf89H/0JZ7ADQGtuS7dv77L704S/8Q/rqzm+19jUef3p3+toyH+v788ceTtvu/VFr
x8DiPM+oSwDQKi9O7dv9zJ708S99Ln3sS1emOx/82cT/7rnnn0//eft30pMT/O6A5d7cd92OW+f9
WmG64fnFLNwCgIG4fue2dP3ObWnrcSelc084OZ216cS0ccMRacNBB6cD1xyQntq7J/3y14+lOx/8
Wdp2z4/STXf8T/rFE49O9H/f/OMfpEd2P5EOW+SDhmz/Q3lWbLr0Itk+YLlcIfhlJdCsrp7bnrvD
5RYAncglRGAIPJ9oglsAdGbuRcsVBdRj8NMkOwB0zosYTM/zhqbZAaAXoy9mdgSgmqFPmwQAvfMi
B9A9twAAICABAAABCQAACEgAAEBAAgAAAhIAABCQAACAgAQAAAQkAAAgIAEAAAGt/OkVX1zR90HQ
Hp+zD9Tl9WO4fnrFF1fYAQCAgAQAAAQkAAKwjQdMy+vG8AkAAAhIAABAQAIgCNt5wKS8XsQgAAAg
oJUpvfDzgH0fCO1T9cByvE4M39zMtwMQjCc3sBivD7EIgIA8yYGFvC7EIwAAICABEJTaB+Z4PYjp
pQDwRsB4POkBrwOxjM56OwDBefJDXJ7/sa3u+wDo39yLwK7Lr+75SIAuGPykZAeAEV4UYPg8z5kz
LwC8DwAvDjBcnt+xLZzxbgEwxi0BGBaDnyoCgEWNvmiIASiLoc9yBAATEQOQP0OfaVTe89906UX7
uz4QAKAdVe/x81MAABCQAACAgCoDwI8DAsAwLDbT7QAAQEACAAACWjQA3AYAgLItNcvtAABAQEsG
gF0AACjTcjPcDgAABCQAACCgZQPAbQAAKMsks9sOAAAENFEA2AUAgDJMOrPtAABAQBMHgF0AAMjb
NLPaDgAABDRVANgFAIA8TTuj7QAAQEBTB4BdAADIS53ZbAcAAAKqFQB2AQAgD3Vnsh0AAAiodgDY
BQCAfs0yi+0AAEBAMwWAXQAA6MesM3jmHQARAADdamL2ugUAAAE1EgB2AQCgG03NXDsAABBQYwFg
FwAA2tXkrG10B0AEAEA7mp6xjd8CEAEA0Kw2Zqv3AABAQK0EgF0AAGhGWzO1tR0AEQAAs2lzlrZ6
C0AEAEA9bc9Q7wEAgIBaDwC7AAAwnS5mZyc7ACIAACbT1czs7BaACACApXU5Kzt9D4AIAIBqXc/I
zt8EKAIAYL4+ZmMvPwUgAgDgBX3NRD8GCAAB9RYAdgEAiK7PWdjrDoAIACCqvmdg77cA+l4AAOha
DrOv9wBIKY+FAIAu5DLzsjiIUZsuvWh/38cAAE3LZfDPyWIHYFRuCwQAs8pxtmUXACnluVAAUEeu
My3LAEgp3wUDgEnlPMuyDYCU8l44AFhK7jMs6wBIKf8FBICFSphd2R/gKD8hAEDOShj8c7LfARhV
0sICEEtpM6qoAEipvAUGYPhKnE3FHfAotwQA6FOJg39OcTsAo0peeADKVvoMKjoAUir/GwBAeYYw
e4o/gVFuCQDQpiEM/jmDOZFRQgCAJg1p8M8p/hZAlSF+owDox1BnyiBPapTdAADqGOrgnzPokxsl
BACYxNAH/5wQJzlKCABQJcrgnxPqZEcJAQBSijf454Q86VFCACCmqIN/TuiTHyUEAGKIPvjnWIQF
hADAMBn881mMJYgBgLIZ+ouzMBMQAgBlMfiXZ4GmJAYA8mToT8dizUAMAPTL0K/PwjVIEAC0y8Bv
joVskSAAmI2B3x4L2zFRAFDNsO+Wxc6MQACGyoDPy/8DYre2swULr4wAAAAASUVORK5CYII=
EOF
cp index.html $D/app/src/main/assets/index.html
echo "Project ready"
