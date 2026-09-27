# ML Kit Text Recognition - ignore optional language modules
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit Document Scanner
-keep class com.google.mlkit.vision.documentscanner.** { *; }
-dontwarn com.google.mlkit.vision.documentscanner.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

